// PLN-3 (US-PLN-3-02) — List the account's plans, newest first.
//
// Four queries total, however many plans there are: one for the plans,
// then one each for agents, timelines and tasks across all of them
// (`workspace_id in $ids`), tallied in memory. US-PLN-3-02 forbids a
// per-row loop, so there is deliberately no "count this plan" call
// inside the loop over plans.
//
// P3A-1 (US-P3A-1-02): archived plans are hidden unless asked for.
//
// WHY THE TALLIES ARE PRE-SEEDED WITH ZEROS: `|get` with a VARIABLE key
// silently ignores its default argument and returns null when the key is
// missing (`{}|get:$k:0` is null, while `{}|get:"k":0` is 0 — confirmed
// live). Seeding every plan's key to 0 first means no lookup here ever
// misses, so the broken default is never relied on. Without this the
// counts all came back null.
query "workspace" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    bool include_archived?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $actor.account_id && ($input.include_archived == true || $db.planner_workspace.is_archived == false)
      sort = {planner_workspace.created_at: "desc"}
      return = {type: "list"}
    } as $workspaces

    var $ids {
      value = []
    }

    var $agent_tally {
      value = {}
    }

    var $timeline_tally {
      value = {}
    }

    var $task_tally {
      value = {}
    }

    var $backlog_tally {
      value = {}
    }

    var $key {
      value = ""
    }

    var $cur {
      value = 0
    }

    var $next {
      value = 0
    }

    foreach ($workspaces) {
      each as $w {
        array.push $ids {
          value = $w.id
        }

        var.update $key {
          value = $w.id|to_text
        }

        var.update $agent_tally {
          value = $agent_tally|set:$key:0
        }

        var.update $timeline_tally {
          value = $timeline_tally|set:$key:0
        }

        var.update $task_tally {
          value = $task_tally|set:$key:0
        }

        var.update $backlog_tally {
          value = $backlog_tally|set:$key:0
        }
      }
    }

    var $result {
      value = []
    }

    conditional {
      if (($ids|count) > 0) {
        db.query planner_agent {
          where = $db.planner_agent.workspace_id in $ids
          return = {type: "list"}
        } as $agents

        db.query planner_timeline {
          where = $db.planner_timeline.workspace_id in $ids
          return = {type: "list"}
        } as $timelines

        db.query planner_task {
          where = $db.planner_task.workspace_id in $ids
          return = {type: "list"}
        } as $tasks

        foreach ($agents) {
          each as $a {
            var.update $key {
              value = $a.workspace_id|to_text
            }

            var.update $cur {
              value = $agent_tally|get:$key:0
            }

            var.update $next {
              value = $cur + 1
            }

            var.update $agent_tally {
              value = $agent_tally|set:$key:$next
            }
          }
        }

        foreach ($timelines) {
          each as $t {
            var.update $key {
              value = $t.workspace_id|to_text
            }

            var.update $cur {
              value = $timeline_tally|get:$key:0
            }

            var.update $next {
              value = $cur + 1
            }

            var.update $timeline_tally {
              value = $timeline_tally|set:$key:$next
            }
          }
        }

        foreach ($tasks) {
          each as $k {
            var.update $key {
              value = $k.workspace_id|to_text
            }

            var.update $cur {
              value = $task_tally|get:$key:0
            }

            var.update $next {
              value = $cur + 1
            }

            var.update $task_tally {
              value = $task_tally|set:$key:$next
            }

            conditional {
              if ($k.timeline_id == 0) {
                var.update $cur {
                  value = $backlog_tally|get:$key:0
                }

                var.update $next {
                  value = $cur + 1
                }

                var.update $backlog_tally {
                  value = $backlog_tally|set:$key:$next
                }
              }
            }
          }
        }

        foreach ($workspaces) {
          each as $w {
            var.update $key {
              value = $w.id|to_text
            }

            array.push $result {
              value = {
                workspace: $w
                counts   : {
                  agent_count   : ($agent_tally|get:$key:0)
                  timeline_count: ($timeline_tally|get:$key:0)
                  task_count    : ($task_tally|get:$key:0)
                  backlog_count : ($backlog_tally|get:$key:0)
                }
              }
            }
          }
        }
      }
    }
  }

  response = {workspaces: $result}
}
