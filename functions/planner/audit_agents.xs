// PLN-8 (US-PLN-8-02) — Agent-level integrity checks. Read-only.
//
// One of four audit parts. They are separate functions because a
// single function holding all ten checks failed at runtime with
// "Invalid syntax" — the parser appears to have a complexity ceiling.
// Splitting also means each check can be proven on its own, and that
// when the audit fires you can re-run just the failing part.
//
// Codes: MODEL_DANGLING, PERSON_WITH_MODEL, ORPHAN_AGENT.
//
// Every check is two passes: pass 1 records the lookup result as a
// FIELD, pass 2 branches on that field of the loop item. Branching on
// a variable updated earlier in the same iteration silently discards
// the branch's writes (CLAUDE.md).
function "planner/audit_agents" {
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

    var $key {
      value = ""
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

    conditional {
      if (($ws_ids|count) > 0) {
        db.query planner_agent {
          where = $db.planner_agent.workspace_id in $ws_ids
          return = {type: "list"}
        } as $agents

        db.query planner_model {
          where = $db.planner_model.account_id == $input.account_id
          return = {type: "list"}
        } as $models

        var $model_ids {
          value = {}
        }

        foreach ($models) {
          each as $m {
            var.update $key {
              value = $m.id|to_text
            }

            var.update $model_ids {
              value = $model_ids|set:$key:$m.id
            }
          }
        }

        var $agent_checks {
          value = []
        }

        foreach ($agents) {
          each as $a {
            var.update $key {
              value = $a.model_id|to_text
            }

            array.push $agent_checks {
              value = {
                id         : $a.id
                kind       : $a.kind
                model_id   : $a.model_id
                model_found: ($model_ids|get:$key:null)
              }
            }
          }
        }

        foreach ($agent_checks) {
          each as $c {
            conditional {
              if ($c.model_id != 0 && $c.model_found == null) {
                array.push $violations {
                  value = {code: "MODEL_DANGLING", entity: "planner_agent", id: $c.id, detail: $c.model_id}
                }
              }
            }

            conditional {
              if ($c.kind == "person" && $c.model_id != 0) {
                array.push $violations {
                  value = {code: "PERSON_WITH_MODEL", entity: "planner_agent", id: $c.id, detail: $c.model_id}
                }
              }
            }
          }
        }
      }
    }

    // ORPHAN_AGENT is scanned across the whole table: an agent whose
    // workspace was deleted is no longer reachable from this account's
    // workspace list, which is exactly the case worth catching.
    db.query planner_agent {
      return = {type: "list"}
    } as $all_agents

    db.query planner_workspace {
      return = {type: "list"}
    } as $all_workspaces

    var $all_ws {
      value = {}
    }

    foreach ($all_workspaces) {
      each as $w {
        var.update $key {
          value = $w.id|to_text
        }

        var.update $all_ws {
          value = $all_ws|set:$key:$w.account_id
        }
      }
    }

    var $orphan_checks {
      value = []
    }

    foreach ($all_agents) {
      each as $a {
        var.update $key {
          value = $a.workspace_id|to_text
        }

        array.push $orphan_checks {
          value = {id: $a.id, workspace_id: $a.workspace_id, ws_account: ($all_ws|get:$key:null)}
        }
      }
    }

    foreach ($orphan_checks) {
      each as $c {
        conditional {
          if ($c.ws_account == null) {
            array.push $violations {
              value = {code: "ORPHAN_AGENT", entity: "planner_agent", id: $c.id, detail: $c.workspace_id}
            }
          }
        }
      }
    }
  }

  response = {violations: $violations}
}
