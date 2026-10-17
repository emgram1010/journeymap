// APP-1 (US-APP-1-02) — Which agent(s), across this account's plans,
// does this login perform work as?
//
// Plural on purpose (the epic's own wording): a user could be the
// linked login for an agent in more than one workspace. Split out of
// the main "today" build because PLN-8 already showed this workspace
// rejects a single function that tries to do too much at once.
function "perform/resolve_agents" {
  input {
    int account_id filters=min:1
    int user_id filters=min:1
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

    db.query planner_agent {
      where = $db.planner_agent.workspace_id in $ws_ids && $db.planner_agent.user_id == $input.user_id
      return = {type: "list"}
    } as $agents

    var $agent_ids {
      value = []
    }

    foreach ($agents) {
      each as $a {
        array.push $agent_ids {
          value = $a.id
        }
      }
    }
  }

  response = {agent_ids: $agent_ids}
}
