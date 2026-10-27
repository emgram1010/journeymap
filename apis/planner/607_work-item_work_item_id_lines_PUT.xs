// EST-1 (US-EST-1-02) — Replace a job's whole set of order lines in
// one call: [{item_type_id, quantity}]. Query-then-loop, inside one
// db.transaction (CLAUDE.md: db.del by field_name/field_value only
// removes the first match).
//
// FROZEN ONCE WORK HAS STARTED (E-EST-007): refused the moment any of
// this job's work_task rows has left `not_started`. The estimate a
// plan was scheduled against must not drift under live work.
//
// "IN THE VERSION'S ITEM SET" (E-EST-003) IS READ FROM `stage_rate`,
// NOT `journey_lens_item`: the chosen-item list is a live DRAFT table
// (ITEM-1), never pinned to a version, so it cannot answer "was this
// item really part of THIS published version." `stage_rate` can —
// it is written only at publish, one row per (version, stage, item,
// method) that actually had a rate. An item with zero rates anywhere
// (every stage per_order, or chosen but never given a line) cannot be
// ordered, which is correct: nothing on the map scales with it.
//
// AFTER A SUCCESSFUL REPLACE, every unscheduled-or-untweaked task of
// this job is refreshed to the fresh estimate (D-1: silently, logged
// as success — the planner never expressed an opinion on an untweaked
// number). A TWEAKED slot (planner_task.tweak_reason != "") is left
// exactly as the planner set it, and the refusal to touch it is its
// own `warn` event, estimate_changed_under_tweak, so a founder looking
// at the Health page can see where the two numbers have diverged.
query "work-item/{work_item_id}/lines" verb=PUT {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
    // EST-1 Opus review fix (finding #9b, 2026-10-25): this endpoint
    // REPLACES a job's whole line set. Optional + `?? []` meant an
    // omitted body silently cleared every existing line instead of
    // being refused — required means the caller must send `[]`
    // explicitly to mean "clear everything."
    json lines
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($version == null) {
        var.update $reject_code {
          value = "E-EST-005"
        }

        var.update $reject_msg {
          value = "This job isn't linked to a published version yet. (E-EST-005)"
        }
      }
    }

    var $schema_version {
      value = 1
    }

    conditional {
      if ($version != null) {
        var.update $schema_version {
          value = $version.snapshot.schema_version ?? 1
        }
      }
    }

    var $has_items_row {
      value = ($schema_version >= 2)
    }

    conditional {
      if ($reject_code == "" && $has_items_row == false) {
        var.update $reject_code {
          value = "E-EST-004"
        }

        var.update $reject_msg {
          value = "This work type doesn't track items. Add an Items row to the map and publish a new version. (E-EST-004)"
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id && $db.work_task.status != "not_started"
      return = {type: "count"}
    } as $started_count

    conditional {
      if ($reject_code == "" && $started_count > 0) {
        var.update $reject_code {
          value = "E-EST-007"
        }

        var.update $reject_msg {
          value = "Work has started on this order, so its items are locked. Create a new order for the extra items. (E-EST-007)"
        }
      }
    }

    // `lines` is required now (finding #9b); `?? []` is defensive only.
    var $lines_in {
      value = $input.lines ?? []
    }

    // The version's own item set, by key (see header).
    var $rate_item_keys {
      value = {}
    }

    conditional {
      if ($reject_code == "") {
        db.query stage_rate {
          where = $db.stage_rate.journey_map_version_id == $version.id
          return = {type: "list"}
        } as $version_rates

        foreach ($version_rates) {
          each as $vr {
            var.update $rate_item_keys {
              value = $rate_item_keys|set:$vr.quantity_key:true
            }
          }
        }
      }
    }

    var $seen_items {
      value = {}
    }

    var $normalized_lines {
      value = []
    }

    foreach ($lines_in) {
      each as $line {
        // EST-1 Opus review fix (finding #7, 2026-10-25): the range
        // check alone let a decimal (e.g. 2.5) through — not null,
        // not <1, not >9999. Hoisted into its own var rather than a
        // bare `|to_int` sitting inside this larger `||` chain
        // (CLAUDE.md: a piped filter in the middle of a boolean chain
        // can swallow the rest of the chain into its own argument).
        var $quantity_is_integer {
          value = ($line.quantity == ($line.quantity|to_int))
        }

        conditional {
          if ($reject_code == "" && ($line.quantity == null || $line.quantity < 1 || $line.quantity > 9999 || $quantity_is_integer == false)) {
            var.update $reject_code {
              value = "E-EST-001"
            }

            var.update $reject_msg {
              value = "Enter how many, from 1 to 9999. (E-EST-001)"
            }
          }
        }

        conditional {
          if ($reject_code == "") {
            var $dup_key {
              value = $line.item_type_id|to_text
            }

            var $dup_hit {
              value = $seen_items|get:$dup_key:null
            }

            conditional {
              if ($dup_hit != null) {
                var.update $reject_code {
                  value = "E-EST-006"
                }

                var.update $reject_msg {
                  value = "That item is already on this order — change its quantity instead. (E-EST-006)"
                }
              }

              else {
                var.update $seen_items {
                  value = $seen_items|set:$dup_key:true
                }
              }
            }
          }
        }

        conditional {
          if ($reject_code == "") {
            db.get item_type {
              field_name = "id"
              field_value = $line.item_type_id
            } as $item

            conditional {
              if ($item == null || $item.account_id != $actor.account_id) {
                var.update $reject_code {
                  value = "E-EST-003"
                }

                var.update $reject_msg {
                  value = "That item isn't on this map. Add it to the map's Items row and publish a new version. (E-EST-003)"
                }
              }
            }

            conditional {
              if ($reject_code == "" && $item.is_active == false) {
                var.update $reject_code {
                  value = "E-EST-002"
                }

                var.update $reject_msg {
                  value = "That item has been deactivated. Pick another or reactivate it in Settings → Items. (E-EST-002)"
                }
              }
            }

            conditional {
              if ($reject_code == "") {
                var $present {
                  value = $rate_item_keys|get:$item.key:null
                }

                conditional {
                  if ($present == null) {
                    var.update $reject_code {
                      value = "E-EST-003"
                    }

                    var.update $reject_msg {
                      value = "That item isn't on this map. Add it to the map's Items row and publish a new version. (E-EST-003)"
                    }
                  }
                }
              }
            }

            conditional {
              if ($reject_code == "") {
                array.push $normalized_lines {
                  value = {item_type_id: $line.item_type_id, quantity: $line.quantity}
                }
              }
            }
          }
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "EST-1"
            step          : "lines_set"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Lines update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.query work_item_line {
      where = $db.work_item_line.work_item_id == $input.work_item_id
      return = {type: "list"}
    } as $existing_lines

    db.transaction {
      stack {
        foreach ($existing_lines) {
          each as $el {
            db.del work_item_line {
              field_name = "id"
              field_value = $el.id
            }
          }
        }

        foreach ($normalized_lines) {
          each as $nl {
            db.add work_item_line {
              data = {
                created_at      : "now"
                work_item_id    : $input.work_item_id
                item_type_id    : $nl.item_type_id
                quantity        : $nl.quantity
                flagged_quantity: 0
                created_by      : $actor.user_id
              }
            } as $_added_line
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "EST-1"
        step          : "lines_set"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_item"
        entity_id     : $input.work_item_id
        correlation_id: $input.correlation_id
        message       : "Lines updated."
        metadata      : {line_count: ($normalized_lines|count)}
      }
    }

    function.run "estimate/estimate_job" {
      input = {work_item_id: $input.work_item_id}
    } as $fresh

    conditional {
      if ($fresh.complete == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "EST-1"
            step        : "estimate_incomplete"
            outcome     : "failure"
            severity    : "warn"
            user_id     : $actor.user_id
            account_id  : $actor.account_id
            entity_type : "work_item"
            entity_id   : $input.work_item_id
            message     : "Estimate is incomplete after the lines update."
            metadata    : {missing: $fresh.missing, reasons: $fresh.reasons}
          }
        }
      }

      else {
        function.run "ops/log_event" {
          input = {
            feature    : "EST-1"
            step       : "estimate_computed"
            outcome    : "success"
            severity   : "info"
            user_id    : $actor.user_id
            account_id : $actor.account_id
            entity_type: "work_item"
            entity_id  : $input.work_item_id
            message    : "Estimate computed."
            metadata   : {total_minutes: $fresh.total_minutes, journey_map_version_id: $fresh.journey_map_version_id}
          }
        }
      }
    }

    // ── Refresh scheduled, untweaked slots to the fresh estimate ────────
    // EXC-1 (2026-10-26): the refresh rule lives in ONE place,
    // `estimate/refresh_job_slots`, shared with the exception spawn
    // (which shrinks a parent's lines). Extracted verbatim from this
    // section; FT-EXC-1-15 re-ran this endpoint before/after and the
    // results matched.
    function.run "estimate/refresh_job_slots" {
      input = {
        work_item_id  : $input.work_item_id
        estimate      : $fresh
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        feature       : "EST-1"
        message       : "Lines changed, but a scheduled slot keeps its tweaked duration."
        correlation_id: $input.correlation_id
      }
    } as $refresh

    var $refreshed_count {
      value = $refresh.refreshed_count
    }

    var $tweaked_skipped_count {
      value = $refresh.tweaked_skipped_count
    }
  }

  response = {
    work_item_id        : $input.work_item_id
    line_count          : ($normalized_lines|count)
    estimate            : $fresh
    refreshed_count     : $refreshed_count
    tweaked_skipped_count: $tweaked_skipped_count
  }
}
