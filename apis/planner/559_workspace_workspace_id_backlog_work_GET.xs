// SCHED-1 (US-SCHED-1-03) — The job work waiting to be scheduled.
//
// Everything in this plan's jobs that has no slot on the schedule
// yet, with its text and expected minutes read from each job's
// PINNED version — so the backlog shows what was agreed, not what
// the live map says today.
//
// CANCELLED JOBS ARE EXCLUDED. Their steps are history, not work
// waiting to happen, and offering them for scheduling would put
// abandoned work back in front of the planner.
//
// In the MVP one backlog row is one work task. Blocks
// (US-SCHED-1-02) will group consecutive steps later; the link table
// is already many-to-one so that arrives without a migration.
//
// "Unscheduled" is decided by absence from `planner_task_work_task`.
// Two passes, as everywhere in this codebase: the link lookup is
// recorded as a FIELD first, then filtered on a loop item's own
// field, because branching on a variable set earlier in the same
// iteration silently loses the write (CLAUDE.md).
query "workspace/{workspace_id}/backlog_work" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id && $db.work_item.status != "cancelled"
      return = {type: "list"}
    } as $jobs

    var $job_ids {
      value = []
    }

    var $version_ids {
      value = []
    }

    var $key {
      value = ""
    }

    var $job_by_id {
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

    var $rows {
      value = []
    }

    conditional {
      if (($job_ids|count) > 0) {
        db.query work_task {
          where = $db.work_task.work_item_id in $job_ids
          sort = {work_task.id: "asc"}
          return = {type: "list"}
        } as $work_tasks

        db.query journey_map_version {
          where = $db.journey_map_version.id in $version_ids
          return = {type: "list"}
        } as $versions

        // Cell text and minutes, keyed version~stage~lens.
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
                  value = ($v.id|to_text) ~ "~" ~ $c.stage_key
                }

                var.update $part_b {
                  value = $c.lens_key
                }

                var.update $key {
                  value = $part_a ~ "~" ~ $part_b
                }

                var.update $cell_map {
                  value = $cell_map|set:$key:$c
                }
              }
            }
          }
        }

        // Which work tasks already have a slot.
        db.query planner_task_work_task {
          return = {type: "list"}
        } as $links

        var $linked {
          value = {}
        }

        foreach ($links) {
          each as $l {
            var.update $key {
              value = $l.work_task_id|to_text
            }

            var.update $linked {
              value = $linked|set:$key:1
            }
          }
        }

        // Pass 1 — candidates carrying their lookups as fields.
        var $candidates {
          value = []
        }

        var $job {
          value = null
        }

        var $cell {
          value = null
        }

        foreach ($work_tasks) {
          each as $wt {
            var.update $key {
              value = $wt.work_item_id|to_text
            }

            var.update $job {
              value = $job_by_id|get:$key:null
            }

            var.update $part_a {
              value = ($job.journey_map_version_id|to_text) ~ "~" ~ $wt.stage_key
            }

            var.update $part_b {
              value = $wt.lens_key
            }

            var.update $key {
              value = $part_a ~ "~" ~ $part_b
            }

            var.update $cell {
              value = $cell_map|get:$key:null
            }

            var.update $key {
              value = $wt.id|to_text
            }

            array.push $candidates {
              value = {
                work_task_id    : $wt.id
                work_item_id    : $wt.work_item_id
                job_title       : $job.title
                stage_key       : $wt.stage_key
                lens_key        : $wt.lens_key
                status          : $wt.status
                task            : ($cell.task ?? null)
                done_when       : ($cell.done_when ?? null)
                expected_minutes: ($cell.duration_minutes ?? null)
                is_linked       : ($linked|get:$key:null)
              }
            }
          }
        }

        // Pass 2 — keep only the unscheduled ones.
        foreach ($candidates) {
          each as $c {
            conditional {
              if ($c.is_linked == null) {
                array.push $rows {
                  value = {
                    work_task_id    : $c.work_task_id
                    work_item_id    : $c.work_item_id
                    job_title       : $c.job_title
                    stage_key       : $c.stage_key
                    lens_key        : $c.lens_key
                    status          : $c.status
                    task            : $c.task
                    done_when       : $c.done_when
                    expected_minutes: $c.expected_minutes
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    workspace_id: $input.workspace_id
    count       : ($rows|count)
    backlog     : $rows
  }
}
