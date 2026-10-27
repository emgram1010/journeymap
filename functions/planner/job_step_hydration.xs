// GAP-FIX W1 (2026-10-17) — What a scheduled JOB STEP actually says.
//
// SCHED-1's own header already names this gap: "`planner_task.title` is
// left empty for a linked slot on purpose — the real title lives in the
// job's pinned version and is read through the link… ⚠️ Known gap:
// PLN-7's task list does not yet hydrate linked slots, so a scheduled
// job step currently reads with a blank title there." That is still
// "reference, do not copy" done right; it just left the reading half
// unbuilt, so every job step placed on the board showed as an empty
// card. This is the reading half.
//
// ONE PASS FOR THE WHOLE PLAN, not one lookup per task. Four queries
// total regardless of how many jobs or steps there are, in the same
// shape `apis/planner/559_..._backlog_work_GET.xs` already uses — which
// is also why this is a FUNCTION and not inlined into the board: 559
// and 548 would otherwise each hold their own copy of the same join,
// and the two would eventually disagree about what a step says.
//
// CANCELLED JOBS ARE INCLUDED here, unlike the backlog (559). A
// cancelled job's steps must never be offered for NEW scheduling, but
// one that was already placed on a day still occupies that slot, and a
// slot that silently loses its text when the job is cancelled is the
// blank-card bug all over again.
//
// BLK-1 (US-BLK-1-07, 2026-10-21) — `position` IS NOW RETURNED, and the
// links are read in position order. A slot can cover a whole card since
// story 02, and this function was the only thing that told the board
// what a slot holds — without the position the frontend could group a
// card's steps but not put them in the order they were agreed in, and
// "first stage" would have meant "whichever row the query returned
// first". Additive to the response, so no caller breaks.
//
// Composite keys use "::" — a literal "|" inside a quoted string
// breaks the parser (CLAUDE.md).
function "planner/job_step_hydration" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $jobs

    var $job_ids {
      value = []
    }

    var $version_ids {
      value = []
    }

    var $job_by_id {
      value = {}
    }

    var $key {
      value = ""
    }

    // EST-1 (US-EST-1-05) — one estimate per job, looked up below by
    // "job_id::stage_key" so a step's expected_minutes becomes its
    // stage's real estimate (baseline only when that stage has a
    // missing rate) on any map with an Items row. A map with no Items
    // row is untouched: $items_row_by_job stays false for it.
    var $items_row_by_job {
      value = {}
    }

    // EST-1 Opus review fix — job_id -> estimate.complete, mirrored
    // from 559. Read with `|has` to test presence, never `== null`/
    // `!= null`: `complete` is legitimately `false` for an incomplete
    // job, and this engine's null comparison is PHP-style loose
    // equality where `false == null` is TRUE (CLAUDE.md), so a null
    // check would silently discard every real `false`.
    var $job_complete_by_job {
      value = {}
    }

    var $stage_est_by_jobstage {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }

        array.push $version_ids {
          value = $j.journey_map_version_id
        }

        var.update $key {
          value = $j.id|to_text
        }

        var.update $job_by_id {
          value = $job_by_id|set:$key:$j
        }
      }
    }

    // CHEAP PRE-CHECK before paying for `estimate/estimate_job` — see
    // apis/planner/559_..._backlog_work_GET.xs's identical comment. One
    // query for every distinct version instead of one estimate call
    // per job regardless of need.
    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $prelim_versions

    var $schema_version_by_version_id {
      value = {}
    }

    foreach ($prelim_versions) {
      each as $pv {
        var $pv_id_key {
          value = $pv.id|to_text
        }

        var.update $schema_version_by_version_id {
          value = $schema_version_by_version_id|set:$pv_id_key:($pv.snapshot.schema_version ?? 1)
        }
      }
    }

    foreach ($jobs) {
      each as $j3 {
        var $j3_key {
          value = $j3.id|to_text
        }

        var $j3_version_key {
          value = $j3.journey_map_version_id|to_text
        }

        var $j3_schema_version {
          value = $schema_version_by_version_id|get:$j3_version_key:1
        }

        conditional {
          if ($j3_schema_version >= 2) {
            function.run "estimate/estimate_job" {
              input = {work_item_id: $j3.id}
            } as $job_estimate

            var.update $items_row_by_job {
              value = $items_row_by_job|set:$j3_key:$job_estimate.has_items_row
            }

            var.update $job_complete_by_job {
              value = $job_complete_by_job|set:$j3_key:$job_estimate.complete
            }

            foreach ($job_estimate.stages) {
              each as $jes {
                var $jobstage_key {
                  value = $j3_key ~ "::" ~ $jes.stage_key
                }

                var.update $stage_est_by_jobstage {
                  value = $stage_est_by_jobstage|set:$jobstage_key:$jes
                }
              }
            }
          }
        }
      }
    }

    var $steps {
      value = []
    }

    conditional {
      if (($job_ids|count) > 0) {
        db.query work_task {
          where = $db.work_task.work_item_id in $job_ids
          return = {type: "list"}
        } as $work_tasks

        var $wt_by_id {
          value = {}
        }

        var $wt_ids {
          value = []
        }

        foreach ($work_tasks) {
          each as $wt {
            var.update $key {
              value = $wt.id|to_text
            }

            var.update $wt_by_id {
              value = $wt_by_id|set:$key:$wt
            }

            array.push $wt_ids {
              value = $wt.id
            }
          }
        }

        // Reuses $prelim_versions (queried above for the schema-version
        // pre-check) instead of a second, identical query.
        var $versions {
          value = $prelim_versions
        }

        var $cell_map {
          value = {}
        }

        var $part_a {
          value = ""
        }

        var $part_b {
          value = ""
        }

        foreach ($versions) {
          each as $v {
            foreach ($v.snapshot.cells) {
              each as $c {
                var.update $part_a {
                  value = ($v.id|to_text) ~ "::" ~ $c.stage_key
                }

                var.update $part_b {
                  value = $c.lens_key
                }

                var.update $key {
                  value = $part_a ~ "::" ~ $part_b
                }

                var.update $cell_map {
                  value = $cell_map|set:$key:$c
                }
              }
            }
          }
        }

        db.query planner_task_work_task {
          where = $db.planner_task_work_task.work_task_id in $wt_ids
          sort = {position: "asc"}
          return = {type: "list"}
        } as $links

        var $wt {
          value = null
        }

        var $job {
          value = null
        }

        var $cell {
          value = null
        }

        foreach ($links) {
          each as $l {
            var.update $key {
              value = $l.work_task_id|to_text
            }

            var.update $wt {
              value = $wt_by_id|get:$key:null
            }

            var.update $key {
              value = $wt.work_item_id|to_text
            }

            var.update $job {
              value = $job_by_id|get:$key:null
            }

            var.update $part_a {
              value = ($job.journey_map_version_id|to_text) ~ "::" ~ $wt.stage_key
            }

            var.update $part_b {
              value = $wt.lens_key
            }

            var.update $key {
              value = $part_a ~ "::" ~ $part_b
            }

            var.update $cell {
              value = $cell_map|get:$key:null
            }

            var $step_expected_minutes {
              value = ($cell.duration_minutes ?? null)
            }

            var $step_estimate_status {
              value = "n/a"
            }

            var $step_estimate_source {
              value = "n/a"
            }

            var $hyd_job_item_key {
              value = $wt.work_item_id|to_text
            }

            var $hyd_job_has_items_row {
              value = $items_row_by_job|get:$hyd_job_item_key:false
            }

            // EST-1 Opus review fixes (2026-10-25), mirrored from 555/
            // 559/560/583: the override only applies to the task whose
            // lens_key is the stage's OWNER — a second actor at the
            // same stage keeps the raw cell scan's number, never the
            // combined stage total (double-counting otherwise). And a
            // stage also counts as incomplete when the WHOLE job is
            // incomplete for a reason that isn't this stage's own (no
            // lines at all), not only when this stage's own `missing`
            // is non-empty.
            conditional {
              if ($hyd_job_has_items_row == true) {
                var $hyd_jobstage_key {
                  value = $hyd_job_item_key ~ "::" ~ $wt.stage_key
                }

                var $hyd_stage_est {
                  value = $stage_est_by_jobstage|get:$hyd_jobstage_key:null
                }

                conditional {
                  if ($hyd_stage_est != null && $hyd_stage_est.owner_lens_key == $wt.lens_key) {
                    var.update $step_estimate_source {
                      value = $hyd_stage_est.source
                    }

                    var $hyd_job_complete {
                      value = true
                    }

                    conditional {
                      if ($job_complete_by_job|has:$hyd_job_item_key) {
                        var.update $hyd_job_complete {
                          value = $job_complete_by_job|get:$hyd_job_item_key:true
                        }
                      }
                    }

                    var $hyd_incomplete {
                      value = (($hyd_stage_est.missing|count) > 0)
                    }

                    conditional {
                      if ($hyd_stage_est.scales_with != "per_order" && $hyd_job_complete == false) {
                        var.update $hyd_incomplete {
                          value = true
                        }
                      }
                    }

                    conditional {
                      if ($hyd_incomplete == true) {
                        var.update $step_expected_minutes {
                          value = $hyd_stage_est.baseline_minutes
                        }

                        var.update $step_estimate_status {
                          value = "incomplete"
                        }
                      }

                      else {
                        var.update $step_expected_minutes {
                          value = $hyd_stage_est.total_minutes
                        }

                        var.update $step_estimate_status {
                          value = "complete"
                        }
                      }
                    }
                  }
                }
              }
            }

            array.push $steps {
              value = {
                planner_task_id : $l.planner_task_id
                work_task_id    : $l.work_task_id
                position        : $l.position
                work_item_id    : $wt.work_item_id
                job_title       : $job.title
                job_status      : $job.status
                stage_key       : $wt.stage_key
                lens_key        : $wt.lens_key
                step_status     : $wt.status
                step_title      : ($cell.task ?? null)
                done_when       : ($cell.done_when ?? null)
                expected_minutes: $step_expected_minutes
                estimate_status : $step_estimate_status
                estimate_source : $step_estimate_source
              }
            }
          }
        }
      }
    }
  }

  response = {steps: $steps}
}
