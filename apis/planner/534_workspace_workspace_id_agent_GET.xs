// PLN-5 (US-PLN-5-05) — Everyone in a plan, including the hidden ones.
//
// HIDDEN AGENTS ARE INCLUDED ON PURPOSE. `is_visible` controls whether
// someone shows in the Plan and Schedule views, but the Agents popover
// is where you go to un-hide them, so filtering them out here would
// make hiding a one-way trip.
//
// The model summary is resolved with ONE extra query for the whole
// list, not one per agent (US-PLN-5-05 forbids an N+1): every model in
// the account is read once and indexed by id in memory.
//
// Keys in that index are pre-seeded from the model rows themselves, so
// every lookup hits an existing key — `|get` with a variable key
// ignores its default on a miss and returns null (see CLAUDE.md). Here
// a miss is handled explicitly instead, because an agent CAN legitimately
// point at no model (`model_id = 0`).
query "workspace/{workspace_id}/agent" verb=GET {
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

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      sort = {planner_agent.created_at: "asc", planner_agent.id: "asc"}
      return = {type: "list"}
    } as $agents

    db.query planner_model {
      where = $db.planner_model.account_id == $actor.account_id
      return = {type: "list"}
    } as $models

    var $model_index {
      value = {}
    }

    var $mkey {
      value = ""
    }

    foreach ($models) {
      each as $m {
        var.update $mkey {
          value = $m.id|to_text
        }

        var.update $model_index {
          value = $model_index|set:$mkey:{model_id: $m.id, model_key: $m.model_key, label: $m.label}
        }
      }
    }

    var $result {
      value = []
    }

    var $summary {
      value = null
    }

    foreach ($agents) {
      each as $a {
        var.update $summary {
          value = null
        }

        conditional {
          if ($a.model_id != 0) {
            var.update $mkey {
              value = $a.model_id|to_text
            }

            var.update $summary {
              value = $model_index|get:$mkey:null
            }
          }
        }

        array.push $result {
          value = {
            agent: $a
            model: $summary
          }
        }
      }
    }
  }

  response = {agents: $result}
}
