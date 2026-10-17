// PLN-4 (US-PLN-4-05) — Refuse to delete a model any agent still uses.
//
// ⚠️ NOT PUSHED TO XANO, and neither is the DELETE endpoint that would
// call it. CLAUDE.md requires the founder to approve any delete, and
// the session's permission layer refused the push independently. Held
// for review alongside functions/planner/delete_workspace_cascade.xs.
//
// WHY IT NAMES THE AGENTS: "Model in use" tells someone nothing about
// what to do next. "Model in use by 2 agents: Quote Bot, Triage Bot"
// tells them exactly which rows to go and change. PLN-1 put a btree on
// `planner_agent(model_id)` specifically so this check is cheap.
//
// This guard only answers "is it safe?". The endpoint does the delete,
// after also calling planner/assert_model for tenancy — so a model in
// another account is "not found" and never reaches this check.
//
// The names are joined here rather than in the endpoint so the message
// is identical wherever the rule is enforced.
function "planner/delete_model_guard" {
  input {
    int model_id filters=min:1
  }

  stack {
    db.query planner_agent {
      where = $db.planner_agent.model_id == $input.model_id
      return = {type: "list"}
    } as $users

    var $names {
      value = []
    }

    foreach ($users) {
      each as $a {
        array.push $names {
          value = $a.name
        }
      }
    }

    var $count {
      value = $names|count
    }

    var $joined {
      value = $names|join:", "
    }

    var $message {
      value = ""
    }

    conditional {
      if ($count > 0) {
        var.update $message {
          value = "This model is still used by " ~ $count ~ " agent(s): " ~ $joined ~ ". Point them at another model first. (E-PLN-006)"
        }
      }
    }
  }

  response = {
    safe_to_delete: ($count == 0)
    agent_count   : $count
    agent_names   : $names
    message       : $message
  }
}
