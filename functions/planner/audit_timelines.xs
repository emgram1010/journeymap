// PLN-8 (US-PLN-8-02) — Timeline-level integrity checks. Read-only.
//
// Codes: ORPHAN_TIMELINE, CROSS_WORKSPACE_TIMELINE, NON_DRAFT_STATUS,
// DUP_AGENT_DAY.
//
// DUP_AGENT_DAY should be impossible — there is a unique index on
// (agent_id, planned_date) — and it is checked anyway. An index that
// is quietly dropped or rebuilt wrong is exactly the kind of thing an
// audit exists to notice. It is also the one code that could not be
// provoked in testing: every attempt to seed a duplicate was refused
// by the index, which is the right outcome and leaves this check
// unexercised by construction.
//
// NON_DRAFT_STATUS catches a timeline that somehow left `draft` while
// publishing is on hold (PLN-6 Non-Goals). Today only LIVE-1 may ever
// move it, so anything else is a bug or a direct database edit.
//
// Two passes per check, for the reason in planner/audit_agents.
// Composite keys are built from pre-hoisted vars: concatenating piped
// expressions inline fails at runtime with "Invalid syntax".
function "planner/audit_timelines" {
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

    var $part_a {
      value = ""
    }

    var $part_b {
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

        var $checks {
          value = []
        }

        var $day_seen {
          value = {}
        }

        foreach ($timelines) {
          each as $t {
            var.update $key {
              value = $t.agent_id|to_text
            }

            var.update $part_a {
              value = $t.agent_id|to_text
            }

            var.update $part_b {
              value = $t.planned_date|to_text
            }

            array.push $checks {
              value = {
                id          : $t.id
                workspace_id: $t.workspace_id
                agent_id    : $t.agent_id
                status      : $t.status
                agent_ws    : ($agent_ws|get:$key:null)
                day_key     : ($part_a ~ "-" ~ $part_b)
              }
            }
          }
        }

        var $dup_checks {
          value = []
        }

        foreach ($checks) {
          each as $c {
            array.push $dup_checks {
              value = {id: $c.id, day_key: $c.day_key, seen_before: ($day_seen|get:$c.day_key:null)}
            }

            var.update $day_seen {
              value = $day_seen|set:$c.day_key:$c.id
            }
          }
        }

        foreach ($checks) {
          each as $c {
            conditional {
              if ($c.agent_ws == null) {
                array.push $violations {
                  value = {code: "ORPHAN_TIMELINE", entity: "planner_timeline", id: $c.id, detail: $c.agent_id}
                }
              }
            }

            conditional {
              if ($c.agent_ws != null && $c.agent_ws != $c.workspace_id) {
                array.push $violations {
                  value = {code: "CROSS_WORKSPACE_TIMELINE", entity: "planner_timeline", id: $c.id, detail: $c.agent_id}
                }
              }
            }

            conditional {
              if ($c.status != "draft") {
                array.push $violations {
                  value = {code: "NON_DRAFT_STATUS", entity: "planner_timeline", id: $c.id, detail: $c.status}
                }
              }
            }
          }
        }

        foreach ($dup_checks) {
          each as $d {
            conditional {
              if ($d.seen_before != null) {
                array.push $violations {
                  value = {code: "DUP_AGENT_DAY", entity: "planner_timeline", id: $d.id, detail: $d.day_key}
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
