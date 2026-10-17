// PLN-8 (US-PLN-8-02) — Task-level integrity checks. Read-only.
//
// Codes: ORPHAN_TASK, CROSS_WORKSPACE_TASK.
//
// A task can dangle two ways — its timeline or its assignee override
// — and can be cross-workspace the same two ways, so all four are
// reported separately with the offending id in `detail`. Knowing
// WHICH reference is broken is the difference between a fixable
// report and a shrug.
//
// `timeline_id = 0` and `assignee_agent_id = 0` mean "not set" and are
// never violations: the backlog is a legitimate home for a task, and
// no override is the normal case.
//
// Two passes per check, for the reason in planner/audit_agents.
function "planner/audit_tasks" {
  input {
    int account_id filters=min:1
  }

  stack {
    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $input.account_id
      return = {type: "list"}
    } as $workspaces

    var $ws_ids {
      value = []
    }

    foreach ($workspaces) {
      each as $w {
        array.push $ws_ids {
          value = $w.id
        }
      }
    }

    var $violations {
      value = []
    }

    var $key {
      value = ""
    }

    conditional {
      if (($ws_ids|count) > 0) {
        db.query planner_agent {
          where = $db.planner_agent.workspace_id in $ws_ids
          return = {type: "list"}
        } as $agents

        db.query planner_timeline {
          where = $db.planner_timeline.workspace_id in $ws_ids
          return = {type: "list"}
        } as $timelines

        db.query planner_task {
          where = $db.planner_task.workspace_id in $ws_ids
          return = {type: "list"}
        } as $tasks

        var $agent_ws {
          value = {}
        }

        foreach ($agents) {
          each as $a {
            var.update $key {
              value = $a.id|to_text
            }

            var.update $agent_ws {
              value = $agent_ws|set:$key:$a.workspace_id
            }
          }
        }

        var $timeline_ws {
          value = {}
        }

        foreach ($timelines) {
          each as $t {
            var.update $key {
              value = $t.id|to_text
            }

            var.update $timeline_ws {
              value = $timeline_ws|set:$key:$t.workspace_id
            }
          }
        }

        var $checks {
          value = []
        }

        var $tl_ws {
          value = null
        }

        var $as_ws {
          value = null
        }

        foreach ($tasks) {
          each as $tk {
            var.update $key {
              value = $tk.timeline_id|to_text
            }

            var.update $tl_ws {
              value = $timeline_ws|get:$key:null
            }

            var.update $key {
              value = $tk.assignee_agent_id|to_text
            }

            var.update $as_ws {
              value = $agent_ws|get:$key:null
            }

            array.push $checks {
              value = {
                id               : $tk.id
                workspace_id     : $tk.workspace_id
                timeline_id      : $tk.timeline_id
                assignee_agent_id: $tk.assignee_agent_id
                timeline_ws      : $tl_ws
                assignee_ws      : $as_ws
              }
            }
          }
        }

        foreach ($checks) {
          each as $c {
            conditional {
              if ($c.timeline_id != 0 && $c.timeline_ws == null) {
                array.push $violations {
                  value = {code: "ORPHAN_TASK", entity: "planner_task", id: $c.id, detail: $c.timeline_id}
                }
              }
            }

            conditional {
              if ($c.assignee_agent_id != 0 && $c.assignee_ws == null) {
                array.push $violations {
                  value = {code: "ORPHAN_TASK", entity: "planner_task", id: $c.id, detail: $c.assignee_agent_id}
                }
              }
            }

            conditional {
              if ($c.timeline_ws != null && $c.timeline_ws != $c.workspace_id) {
                array.push $violations {
                  value = {code: "CROSS_WORKSPACE_TASK", entity: "planner_task", id: $c.id, detail: $c.timeline_id}
                }
              }
            }

            conditional {
              if ($c.assignee_ws != null && $c.assignee_ws != $c.workspace_id) {
                array.push $violations {
                  value = {code: "CROSS_WORKSPACE_TASK", entity: "planner_task", id: $c.id, detail: $c.assignee_agent_id}
                }
              }
            }
          }
        }
      }
    }
  }

  response = {violations: $violations}
}
