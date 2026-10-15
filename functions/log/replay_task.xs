// LOG-1 (US-LOG-1-05) — Replay one task's log and compare it with
// the stored row.
//
// THE TRUTH CHECK. `work_task.status` is a cache of this result. If
// the two disagree, the LOG is right and the row is wrong — something
// wrote the status outside the engine, or a write went half in.
//
// It reports, it does not repair. A silent fix would destroy the only
// evidence that something is writing status behind the engine's back,
// and the second occurrence would look like the first.
//
// The transition table comes from `log/next_status`, the same
// function the record-event endpoint uses, so the audit cannot
// disagree with the engine it audits.
//
// Events are replayed in `occurred_at` order, with `id` breaking
// ties — two taps inside the same millisecond still replay in the
// order they were written.
function "log/replay_task" {
  input {
    int work_task_id filters=min:1
  }

  stack {
    db.get work_task {
      field_name = "id"
      field_value = $input.work_task_id
    } as $task

    db.query activity_log {
      where = $db.activity_log.work_task_id == $input.work_task_id
      sort = {occurred_at: "asc", id: "asc"}
      return = {type: "list"}
    } as $events

    var $status {
      value = "not_started"
    }

    var $started {
      value = 0
    }

    var $completed {
      value = 0
    }

    var $rejected {
      value = 0
    }

    foreach ($events) {
      each as $e {
        function.run "log/next_status" {
          input = {from: $status, event: $e.event_type}
        } as $r

        conditional {
          if ($r.to == "") {
            var.update $rejected {
              value = $rejected + 1
            }
          }

          else {
            // The FIRST start is kept. A task reopened and finished
            // again was still started when it was first started.
            conditional {
              if ($e.event_type == "started" && $started == 0) {
                var.update $started {
                  value = $e.occurred_at
                }
              }
            }

            conditional {
              if ($e.event_type == "completed" || $e.event_type == "skipped") {
                var.update $completed {
                  value = $e.occurred_at
                }
              }
            }

            conditional {
              if ($e.event_type == "reopened") {
                var.update $completed {
                  value = 0
                }
              }
            }

            var.update $status {
              value = $r.to
            }
          }
        }
      }
    }

    var $stored_started {
      value = 0
    }

    conditional {
      if ($task.started_at != null && $task.started_at != 0) {
        var.update $stored_started {
          value = $task.started_at
        }
      }
    }

    var $stored_completed {
      value = 0
    }

    conditional {
      if ($task.completed_at != null && $task.completed_at != 0) {
        var.update $stored_completed {
          value = $task.completed_at
        }
      }
    }

    var $status_matches {
      value = ($task.status == $status)
    }

    var $times_match {
      value = ($stored_started == $started && $stored_completed == $completed)
    }
  }

  response = {
    work_task_id        : $input.work_task_id
    work_item_id        : $task.work_item_id
    event_count         : $events|count
    rejected_count      : $rejected
    stored_status       : $task.status
    derived_status      : $status
    status_matches      : $status_matches
    stored_started_at   : $stored_started
    derived_started_at  : $started
    stored_completed_at : $stored_completed
    derived_completed_at: $completed
    times_match         : $times_match
    matches             : ($status_matches && $times_match)
  }
}
