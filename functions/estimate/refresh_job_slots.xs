// EXC-1 (extraction before US-EXC-1-03) — THE ONE PLACE a job's
// scheduled slots are refreshed to a fresh estimate. Extracted
// verbatim from 607's "Refresh scheduled, untweaked slots" section so
// the lines PUT (607) and the exception spawn (which shrinks the
// parent's lines) refresh slots through the same code.
//
// EST-1 D-1: an UNTWEAKED slot (planner_task.tweak_reason == "") takes
// the fresh estimate silently — the planner never expressed an opinion
// on that number. A TWEAKED slot keeps exactly what the planner set,
// and the refusal is its own `warn` event, estimate_changed_under_tweak,
// so Health shows where the two numbers diverge.
//
// `estimate` is the caller's fresh `estimate/estimate_job` result —
// passed in, not recomputed, so the caller's estimate events and this
// refresh describe the same numbers.
//
// Two-actor stages: `$stage_by_key` holds one estimate per STAGE; a
// non-owner task falls back to its own raw cell duration (EST-1 Opus
// review fix, 2026-10-25 — otherwise a non-owner slot is refreshed to
// the owner's whole stage total).
//
// Must run OUTSIDE any db.transaction: it calls ops/log_event.
function "estimate/refresh_job_slots" {
  input {
    int work_item_id filters=min:1
    json estimate
    int user_id?
    int account_id?
    text feature filters=trim
    text message? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    precondition ($job != null) {
      error_type = "notfound"
      error = "Job not found"
    }

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    precondition ($version != null) {
      error_type = "notfound"
      error = "Version not found"
    }

    var $fresh {
      value = $input.estimate
    }

    var $stage_by_key {
      value = {}
    }

    foreach ($fresh.stages) {
      each as $fs {
        var.update $stage_by_key {
          value = $stage_by_key|set:$fs.stage_key:$fs
        }
      }
    }

    var $refresh_cell_by_key {
      value = {}
    }

    foreach ($version.snapshot.cells) {
      each as $rc {
        var $refresh_cell_key {
          value = $rc.stage_key ~ "::" ~ $rc.lens_key
        }

        var.update $refresh_cell_by_key {
          value = $refresh_cell_by_key|set:$refresh_cell_key:$rc
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      return = {type: "list"}
    } as $job_tasks

    var $wt_ids {
      value = [-1]
    }

    var $wt_by_id {
      value = {}
    }

    foreach ($job_tasks) {
      each as $wt {
        array.push $wt_ids {
          value = $wt.id
        }

        var $wt_id_key {
          value = $wt.id|to_text
        }

        var.update $wt_by_id {
          value = $wt_by_id|set:$wt_id_key:$wt
        }
      }
    }

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id in $wt_ids
      return = {type: "list"}
    } as $job_links

    // slot_id (text key) -> array of work_task_id, built incrementally.
    // `|get` with a VARIABLE key ignores its default (CLAUDE.md), so the
    // "does this key exist yet" check is explicit.
    var $wt_ids_by_slot {
      value = {}
    }

    var $slot_order {
      value = []
    }

    var $slot_seen {
      value = {}
    }

    foreach ($job_links) {
      each as $link {
        var $slot_key {
          value = $link.planner_task_id|to_text
        }

        var $existing_list {
          value = $wt_ids_by_slot|get:$slot_key:null
        }

        var $base_list {
          value = []
        }

        conditional {
          if ($existing_list != null) {
            var.update $base_list {
              value = $existing_list
            }
          }
        }

        var.update $wt_ids_by_slot {
          value = $wt_ids_by_slot|set:$slot_key:($base_list|push:$link.work_task_id)
        }

        var $already_seen {
          value = $slot_seen|get:$slot_key:null
        }

        conditional {
          if ($already_seen == null) {
            array.push $slot_order {
              value = $link.planner_task_id
            }

            var.update $slot_seen {
              value = $slot_seen|set:$slot_key:true
            }
          }
        }
      }
    }

    var $refreshed_count {
      value = 0
    }

    var $tweaked_skipped_count {
      value = 0
    }

    foreach ($slot_order) {
      each as $slot_id {
        db.get planner_task {
          field_name = "id"
          field_value = $slot_id
        } as $slot

        conditional {
          if ($slot != null && $slot.tweak_reason == "") {
            var $slot_key2 {
              value = $slot_id|to_text
            }

            var $slot_wt_ids {
              value = $wt_ids_by_slot|get:$slot_key2:[]
            }

            var $slot_total {
              value = 0
            }

            foreach ($slot_wt_ids) {
              each as $swid {
                var $swid_key {
                  value = $swid|to_text
                }

                var $swt {
                  value = $wt_by_id|get:$swid_key:null
                }

                var $stage_entry {
                  value = $stage_by_key|get:$swt.stage_key:null
                }

                var $refresh_cell_lookup {
                  value = $swt.stage_key ~ "::" ~ $swt.lens_key
                }

                var $refresh_cell {
                  value = $refresh_cell_by_key|get:$refresh_cell_lookup:null
                }

                // Default: this task's own raw cell duration — correct
                // for a non-owner task at a two-actor stage, and for
                // any v1 (no Items row) map.
                var $contribution {
                  value = ($refresh_cell.duration_minutes ?? 0)
                }

                conditional {
                  if ($stage_entry != null && $stage_entry.owner_lens_key == $swt.lens_key) {
                    var $refresh_incomplete {
                      value = (($stage_entry.missing|count) > 0)
                    }

                    conditional {
                      if ($stage_entry.scales_with != "per_order" && $fresh.complete == false) {
                        var.update $refresh_incomplete {
                          value = true
                        }
                      }
                    }

                    conditional {
                      if ($refresh_incomplete) {
                        var.update $contribution {
                          value = $stage_entry.baseline_minutes
                        }
                      }

                      else {
                        var.update $contribution {
                          value = $stage_entry.total_minutes
                        }
                      }
                    }
                  }
                }

                var.update $slot_total {
                  value = $slot_total + $contribution
                }
              }
            }

            db.patch planner_task {
              field_name = "id"
              field_value = $slot_id
              data = {duration_minutes: $slot_total, updated_at: "now"}
            } as $_refreshed

            var.update $refreshed_count {
              value = $refreshed_count + 1
            }
          }

          else {
            conditional {
              if ($slot != null) {
                var.update $tweaked_skipped_count {
                  value = $tweaked_skipped_count + 1
                }
              }
            }
          }
        }
      }
    }

    var $warn_message {
      value = "A scheduled slot keeps its tweaked duration after the estimate changed."
    }

    conditional {
      if ($input.message != null && $input.message != "") {
        var.update $warn_message {
          value = $input.message
        }
      }
    }

    conditional {
      if ($tweaked_skipped_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : $input.feature
            step          : "estimate_changed_under_tweak"
            outcome       : "success"
            severity      : "warn"
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            message       : $warn_message
            metadata      : {tweaked_skipped_count: $tweaked_skipped_count, refreshed_count: $refreshed_count}
          }
        }
      }
    }
  }

  response = {
    refreshed_count      : $refreshed_count
    tweaked_skipped_count: $tweaked_skipped_count
  }
}
