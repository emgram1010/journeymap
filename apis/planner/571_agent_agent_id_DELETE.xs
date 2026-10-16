// PLN-5 (US-PLN-5-04) + P3A-1 (US-P3A-1-03) — Remove an agent from a
// plan. Created 2026-10-16 on the founder's explicit approval of the
// two non-destructive deletes; task and plan delete remain held.
//
// NOTHING A PERSON DID IS LOST, AND NO TASK IS DELETED. The cascade
// returns every task on the agent's days to the backlog first, clears
// any per-task override pointing at them, then removes their (now
// empty) timelines and the agent row. That is the whole reason this
// one was safe to approve ahead of the others.
//
// AN AGENT WITH HISTORY IS REFUSED, NOT DELETED (US-P3A-1-03) —
// `planner/agent_has_history` is the gate: a published timeline, or
// any activity_log event performed as them. Their work is referenced
// by a frozen publication and by the log, and removing the row those
// point at would turn real history into dangling ids.
//
// THE REFUSAL DOES NOT SAY "DEACTIVATE THEM INSTEAD", which is what
// the story's text specifies, because that feature does not exist:
// `is_active` is set to true once at creation and is never read,
// filtered on, or settable. Promising it would be exactly the kind of
// message that sends a planner looking for a button that isn't there.
// It points at hiding the agent instead, which is real and already
// works (`is_visible`, endpoint 537). Flagged for a proper deactivate
// story in PLN-9's Test Results.
query "agent/{agent_id}" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int agent_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_agent" {
      input = {account_id: $actor.account_id, agent_id: $input.agent_id}
    } as $guard

    var $agent {
      value = $guard.agent
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-5"
        step       : "delete_agent"
        entity_type: "planner_agent"
        entity_id  : $input.agent_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    function.run "planner/agent_has_history" {
      input = {agent_id: $input.agent_id}
    } as $history

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($history.has_history == true) {
        var.update $reject_code {
          value = "E-P3A-002"
        }

        var.update $reject_msg {
          value = $agent.name ~ " has recorded work, so they can't be removed. Hide them from the roster instead. (E-P3A-002)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-5"
            step          : "delete_agent"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_agent"
            entity_id     : $input.agent_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Agent delete refused."
            metadata      : {published_days: $history.published_days, logged_events: $history.logged_events}
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    function.run "planner/delete_agent_cascade" {
      input = {workspace_id: $agent.workspace_id, agent_id: $input.agent_id}
    } as $removed

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-5"
        step          : "delete_agent"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_agent"
        entity_id     : $input.agent_id
        correlation_id: $input.correlation_id
        message       : "Agent removed from plan."
        metadata      : {
          agent_name         : $agent.name
          workspace_id       : $agent.workspace_id
          timelines_removed  : $removed.timelines_removed
          tasks_returned     : $removed.tasks_returned
          assignments_cleared: $removed.assignments_cleared
        }
      }
    }
  }

  response = {
    deleted_agent_id   : $input.agent_id
    timelines_removed  : $removed.timelines_removed
    tasks_returned     : $removed.tasks_returned
    assignments_cleared: $removed.assignments_cleared
  }
}
