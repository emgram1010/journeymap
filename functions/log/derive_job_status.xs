// JOB-1 / LOG-1 — Derive a job's status from its tasks. READ-ONLY.
//
// Split out of `log/sync_job_status` so the audit and the writer use
// the same rule. An audit with its own copy of the rule is worse
// than no audit: it reports healthy data as broken, or misses the
// real drift, and sounds equally certain either way.
//
// Precedence, matching `jobModel.ts::deriveJobStatus`:
//   cancelled (stored on the job, wins outright — a person set it)
//   blocked   (one blocked task holds the job up)
//   completed (every task finished, done or skipped)
//   in_progress
//   open
//
// A job with NO tasks stays `open`, never `completed`. "Every task is
// finished" is vacuously true for no tasks.
function "log/derive_job_status" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      return = {type: "list"}
    } as $tasks

    var $any_blocked {
      value = false
    }

    var $all_finished {
      value = true
    }

    var $any_progress {
      value = false
    }

    var $earliest_start {
      value = 0
    }

    var $latest_finish {
      value = 0
    }

    foreach ($tasks) {
      each as $t {
        conditional {
          if ($t.status == "blocked") {
            var.update $any_blocked {
              value = true
            }
          }
        }

        conditional {
          if ($t.status != "done" && $t.status != "skipped") {
            var.update $all_finished {
              value = false
            }
          }
        }

        conditional {
          if ($t.status == "in_progress" || $t.status == "done" || $t.status == "skipped") {
            var.update $any_progress {
              value = true
            }
          }
        }

        conditional {
          if ($t.started_at != null && $t.started_at != 0 && ($earliest_start == 0 || $t.started_at < $earliest_start)) {
            var.update $earliest_start {
              value = $t.started_at
            }
          }
        }

        conditional {
          if ($t.completed_at != null && $t.completed_at > $latest_finish) {
            var.update $latest_finish {
              value = $t.completed_at
            }
          }
        }
      }
    }

    var $derived {
      value = "open"
    }

    conditional {
      if ($any_progress) {
        var.update $derived {
          value = "in_progress"
        }
      }
    }

    conditional {
      if (($tasks|count) > 0 && $all_finished) {
        var.update $derived {
          value = "completed"
        }
      }
    }

    conditional {
      if ($any_blocked) {
        var.update $derived {
          value = "blocked"
        }
      }
    }

    conditional {
      if ($job.status == "cancelled") {
        var.update $derived {
          value = "cancelled"
        }
      }
    }

    // A job that is no longer complete has not finished.
    var $next_finished {
      value = 0
    }

    conditional {
      if ($derived == "completed") {
        var.update $next_finished {
          value = $latest_finish
        }
      }
    }
  }

  response = {
    work_item_id : $input.work_item_id
    stored_status: $job.status
    status       : $derived
    matches      : ($job.status == $derived)
    started_at   : $earliest_start
    finished_at  : $next_finished
    task_count   : $tasks|count
  }
}
