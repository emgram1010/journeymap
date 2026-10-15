// LOG-1 (US-LOG-1-05, FT-LOG-1-G06) — Integrity audit for the
// execution layer. Read-only.
//
// COMPANION TO `ops/audit_integrity`, not a replacement. That one
// walks the DEFINITION layer (maps, stages, lenses, cells); this one
// walks COMMITMENT and RECORD (jobs, tasks, the log, schedule links,
// publications). They are separate functions because PLN-8 showed
// this workspace rejects a single audit function once it grows past
// a certain size ("Invalid syntax"), and because a nightly job can
// run them independently.
//
// It closes the three checks earlier epics left open:
//   JOB-1  FT-G05 — a job whose stored status disagrees with its tasks
//   LIVE-1 FT-G06 — a publication whose timeline no longer exists
//   LOG-1  FT-G06 — a task whose stored status disagrees with its log
//
// THE REPLAY CHECK IS THE IMPORTANT ONE. `work_task.status` is a
// cache of replaying `activity_log`. If they disagree, something
// wrote a status outside the engine. It REPORTS, it does not repair:
// a silent fix would erase the only evidence that this is happening,
// and the second occurrence would look exactly like the first.
//
// Both rules come from the same functions the live write paths use
// (`log/replay_task`, `log/derive_job_status`), so this cannot
// disagree with the engine it audits.
//
// Cost: one replay query per task. Intended for a nightly job at MVP
// volumes, not for a request path.
function "ops/audit_execution" {
  input {
    int max_detail?=100 filters=min:1|max:500 {
      description = "How many findings to return in full. The counts are always complete."
    }
  }

  stack {
    db.query work_task {
      return = {type: "list"}
    } as $tasks

    db.query work_item {
      return = {type: "list"}
    } as $jobs

    db.query activity_log {
      return = {type: "list"}
    } as $logs

    db.query planner_task_work_task {
      return = {type: "list"}
    } as $links

    db.query plan_publication {
      return = {type: "list"}
    } as $pubs

    db.query planner_timeline {
      return = {type: "list"}
    } as $timelines

    // Lookups. Keys are text because a map key must be; the |to_text
    // is hoisted into its own var every time, because a pipe nested
    // inside a filter argument parses and then fails at runtime.
    var $task_job {
      value = {}
    }

    foreach ($tasks) {
      each as $t {
        var $tk {
          value = $t.id|to_text
        }

        var.update $task_job {
          value = $task_job|set:$tk:$t.work_item_id
        }
      }
    }

    var $timeline_exists {
      value = {}
    }

    foreach ($timelines) {
      each as $tl {
        var $tlk {
          value = $tl.id|to_text
        }

        var.update $timeline_exists {
          value = $timeline_exists|set:$tlk:true
        }
      }
    }

    var $findings {
      value = []
    }

    var $finding_count {
      value = 0
    }

    var $c_replay {
      value = 0
    }

    var $c_log_task {
      value = 0
    }

    var $c_log_job {
      value = 0
    }

    var $c_job_status {
      value = 0
    }

    var $c_link_task {
      value = 0
    }

    var $c_pub_timeline {
      value = 0
    }

    // 1. Replay each task's log and compare with the stored row.
    foreach ($tasks) {
      each as $task {
        function.run "log/replay_task" {
          input = {work_task_id: $task.id}
        } as $rp

        conditional {
          if ($rp.matches == false) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_replay {
              value = $c_replay + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"work_task.replay"|set:"entity_type":"work_task"|set:"entity_id":$task.id|set:"owner":"engineer"|set:"detail":("stored status " ~ $rp.stored_status ~ " but the log replays to " ~ $rp.derived_status ~ " over " ~ ($rp.event_count|to_text) ~ " events")
                }
              }
            }
          }
        }
      }
    }

    // 2. A log row whose task no longer exists, and 3. a log row
    //    whose denormalised job disagrees with its task's.
    foreach ($logs) {
      each as $row {
        var $rk {
          value = $row.work_task_id|to_text
        }

        var $owner_job {
          value = $task_job|get:$rk:null
        }

        conditional {
          if ($owner_job == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_log_task {
              value = $c_log_task + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"activity_log.work_task"|set:"entity_type":"activity_log"|set:"entity_id":$row.id|set:"owner":"engineer"|set:"detail":("points at work_task " ~ $rk ~ ", which does not exist")
                }
              }
            }
          }

          else {
            conditional {
              if ($owner_job != $row.work_item_id) {
                var.update $finding_count {
                  value = $finding_count + 1
                }

                var.update $c_log_job {
                  value = $c_log_job + 1
                }

                conditional {
                  if (($findings|count) < $input.max_detail) {
                    array.push $findings {
                      value = {}|set:"check":"activity_log.work_item"|set:"entity_type":"activity_log"|set:"entity_id":$row.id|set:"owner":"engineer"|set:"detail":("says job " ~ ($row.work_item_id|to_text) ~ " but its task belongs to job " ~ ($owner_job|to_text))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // 4. A job whose stored status disagrees with its tasks (JOB-1).
    foreach ($jobs) {
      each as $job {
        function.run "log/derive_job_status" {
          input = {work_item_id: $job.id}
        } as $dj

        conditional {
          if ($dj.matches == false) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_job_status {
              value = $c_job_status + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"work_item.status"|set:"entity_type":"work_item"|set:"entity_id":$job.id|set:"owner":"engineer"|set:"detail":("stored status " ~ $dj.stored_status ~ " but its " ~ ($dj.task_count|to_text) ~ " tasks derive " ~ $dj.status)
                }
              }
            }
          }
        }
      }
    }

    // 5. A schedule link pointing at a task that no longer exists.
    foreach ($links) {
      each as $link {
        var $lk {
          value = $link.work_task_id|to_text
        }

        var $link_job {
          value = $task_job|get:$lk:null
        }

        conditional {
          if ($link_job == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_link_task {
              value = $c_link_task + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"planner_task_work_task.work_task"|set:"entity_type":"planner_task_work_task"|set:"entity_id":$link.id|set:"owner":"engineer"|set:"detail":("points at work_task " ~ $lk ~ ", which does not exist")
                }
              }
            }
          }
        }
      }
    }

    // 6. A publication whose timeline is gone (LIVE-1). The frozen
    //    snapshot survives on purpose, but nothing should be able to
    //    remove the day it was taken of.
    foreach ($pubs) {
      each as $pub {
        var $pk {
          value = $pub.timeline_id|to_text
        }

        var $tl_ok {
          value = $timeline_exists|get:$pk:null
        }

        conditional {
          if ($tl_ok == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_pub_timeline {
              value = $c_pub_timeline + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"plan_publication.timeline"|set:"entity_type":"plan_publication"|set:"entity_id":$pub.id|set:"owner":"engineer"|set:"detail":("points at planner_timeline " ~ $pk ~ ", which does not exist")
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    finding_count: $finding_count
    findings     : $findings
    truncated    : ($finding_count > ($findings|count))
    counts_by_check: {
      work_task_replay                : $c_replay
      activity_log_work_task          : $c_log_task
      activity_log_work_item          : $c_log_job
      work_item_status                : $c_job_status
      planner_task_work_task_work_task: $c_link_task
      plan_publication_timeline       : $c_pub_timeline
    }
    rows_checked: {
      work_task             : ($tasks|count)
      work_item             : ($jobs|count)
      activity_log          : ($logs|count)
      planner_task_work_task: ($links|count)
      plan_publication      : ($pubs|count)
    }
  }
}
