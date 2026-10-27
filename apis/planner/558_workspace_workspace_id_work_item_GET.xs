// JOB-1 — The jobs in a plan.
//
// CANCELLED JOBS ARE EXCLUDED BY DEFAULT (US-JOB-1-05): they must not
// appear in planning views or scheduling, but they are still history,
// so `include_cancelled=true` brings them back rather than them being
// unreachable.
//
// Each job carries its task counts from ONE query across the whole
// list. The caller can compare those against the stored status; the
// single-job read returns a full `derived_status` for the same
// purpose.
query "workspace/{workspace_id}/work_item" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    bool include_cancelled?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id && ($input.include_cancelled == true || $db.work_item.status != "cancelled")
      sort = {work_item.created_at: "desc"}
      return = {type: "list"}
    } as $jobs

    var $ids {
      value = []
    }

    var $key {
      value = ""
    }

    var $totals {
      value = {}
    }

    var $blocked {
      value = {}
    }

    var $finished {
      value = {}
    }

    var $progressed {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        array.push $ids {
          value = $j.id
        }

        var.update $key {
          value = $j.id|to_text
        }

        var.update $totals {
          value = $totals|set:$key:0
        }

        var.update $blocked {
          value = $blocked|set:$key:0
        }

        var.update $finished {
          value = $finished|set:$key:0
        }

        var.update $progressed {
          value = $progressed|set:$key:0
        }
      }
    }

    var $cur {
      value = 0
    }

    var $next {
      value = 0
    }

    conditional {
      if (($ids|count) > 0) {
        db.query work_task {
          where = $db.work_task.work_item_id in $ids
          return = {type: "list"}
        } as $tasks

        foreach ($tasks) {
          each as $t {
            var.update $key {
              value = $t.work_item_id|to_text
            }

            var.update $cur {
              value = $totals|get:$key:0
            }

            var.update $next {
              value = $cur + 1
            }

            var.update $totals {
              value = $totals|set:$key:$next
            }
          }
        }

        foreach ($tasks) {
          each as $t {
            var.update $key {
              value = $t.work_item_id|to_text
            }

            conditional {
              if ($t.status == "blocked") {
                var.update $blocked {
                  value = $blocked|set:$key:1
                }
              }
            }

            conditional {
              if ($t.status == "done" || $t.status == "skipped") {
                var.update $cur {
                  value = $finished|get:$key:0
                }

                var.update $finished {
                  value = $finished|set:$key:($cur + 1)
                }
              }
            }

            conditional {
              if ($t.status == "in_progress" || $t.status == "done" || $t.status == "skipped") {
                var.update $progressed {
                  value = $progressed|set:$key:1
                }
              }
            }
          }
        }
      }
    }

    // EXC-1 (US-EXC-1-05) — child jobs per job (any status), one query.
    var $child_counts {
      value = {}
    }

    conditional {
      if (($ids|count) > 0) {
        db.query work_item {
          where = $db.work_item.parent_work_item_id in $ids
          return = {type: "list"}
        } as $children

        foreach ($children) {
          each as $ch {
            var $ch_parent_key {
              value = $ch.parent_work_item_id|to_text
            }

            var $ch_prev {
              value = ($child_counts|get:$ch_parent_key:null) ?? 0
            }

            var.update $child_counts {
              value = $child_counts|set:$ch_parent_key:($ch_prev + 1)
            }
          }
        }
      }
    }

    var $result {
      value = []
    }

    var $total_n {
      value = 0
    }

    var $fin_n {
      value = 0
    }

    foreach ($jobs) {
      each as $j {
        var.update $key {
          value = $j.id|to_text
        }

        var.update $total_n {
          value = $totals|get:$key:0
        }

        var.update $fin_n {
          value = $finished|get:$key:0
        }

        var $j_child_count {
          value = ($child_counts|get:$key:null) ?? 0
        }

        array.push $result {
          value = {
            work_item     : $j
            child_count   : $j_child_count
            task_count    : $total_n
            finished_count: $fin_n
            has_blocked   : (($blocked|get:$key:0) == 1)
            has_progress  : (($progressed|get:$key:0) == 1)
          }
        }
      }
    }
  }

  response = {work_items: $result}
}
