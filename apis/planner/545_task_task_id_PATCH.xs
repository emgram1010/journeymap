// PLN-7 (US-PLN-7-05) — Edit a task's own fields.
//
// THIS NEVER MOVES A TASK. Changing where a task sits is
// `POST task/{id}/place`, which is the only thing allowed to touch
// `timeline_id` and `seq`. Keeping the two apart means an edit can
// never accidentally reorder a day.
//
// CHANGING A DURATION WRITES ONE ROW. Every later task's start time
// shifts on the next read because starts are derived, never stored
// (US-PLN-7-05, US-PLN-7-06). Confirmed live: 30 → 120 minutes on the
// second task of seven moved every later start by 90 minutes with no
// other row written.
//
// `needs_info` REQUIRES A REASON. A task flagged as blocked with no
// explanation is worse than one not flagged at all — the planner sees
// a problem and has nothing to act on. Setting the status back to
// `planned` clears the reason automatically, so a stale explanation
// cannot linger.
//
// `assignee_agent_id: 0` CLEARS the override, returning the task to
// "whoever owns the day". There are no real nullable foreign keys
// here, so 0 is how "no override" is spelled.
query "task/{task_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int task_id filters=min:1
    text title? filters=trim
    int duration_minutes?
    text notes? filters=trim
    int assignee_agent_id?
    enum status? {
      values = ["planned", "needs_info"]
    }

    text needs_info_reason? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_task" {
      input = {account_id: $actor.account_id, task_id: $input.task_id}
    } as $guard

    var $existing {
      value = $guard.task
    }

    var $workspace_id {
      value = $guard.workspace.id
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-7"
        step       : "update_task"
        entity_type: "planner_task"
        entity_id  : $input.task_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_title {
      value = $existing.title
    }

    conditional {
      if ($raw_input|has:"title") {
        var.update $next_title {
          value = $input.title
        }
      }
    }

    var $next_duration {
      value = $existing.duration_minutes
    }

    conditional {
      if ($raw_input|has:"duration_minutes") {
        var.update $next_duration {
          value = $input.duration_minutes
        }
      }
    }

    var $next_notes {
      value = $existing.notes
    }

    conditional {
      if ($raw_input|has:"notes") {
        var.update $next_notes {
          value = $input.notes
        }
      }
    }

    var $next_assignee {
      value = $existing.assignee_agent_id
    }

    conditional {
      if ($raw_input|has:"assignee_agent_id") {
        var.update $next_assignee {
          value = $input.assignee_agent_id
        }
      }
    }

    var $next_status {
      value = $existing.status
    }

    conditional {
      if ($raw_input|has:"status") {
        var.update $next_status {
          value = $input.status
        }
      }
    }

    var $next_reason {
      value = $existing.needs_info_reason
    }

    conditional {
      if ($raw_input|has:"needs_info_reason") {
        var.update $next_reason {
          value = $input.needs_info_reason
        }
      }
    }

    // Back to planned = the explanation no longer applies.
    conditional {
      if ($next_status == "planned") {
        var.update $next_reason {
          value = ""
        }
      }
    }

    // An override must be an agent of this same plan.
    conditional {
      if ($next_assignee != 0) {
        function.run "planner/assert_agent" {
          input = {account_id: $actor.account_id, agent_id: $next_assignee}
        } as $ag_guard

        function.run "planner/assert_same_workspace" {
          input = {workspace_id_a: $workspace_id, workspace_id_b: $ag_guard.agent.workspace_id}
        }
      }
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($next_title == null || $next_title == "") {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give the task a title. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_title|strlen) > 200) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "That title is too long — 200 characters at most. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_duration < 1 || $next_duration > 1440)) {
        var.update $reject_code {
          value = "E-PLN-013"
        }

        var.update $reject_msg {
          value = "How long should this take? Enter between 1 minute and 24 hours. (E-PLN-013)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $next_status == "needs_info" && $next_reason == "") {
        var.update $reject_code {
          value = "E-PLN-014"
        }

        var.update $reject_msg {
          value = "Say what's missing, so whoever picks this up knows what to chase. (E-PLN-014)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-7"
            step          : "update_task"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_task"
            entity_id     : $input.task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Task update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch planner_task {
      field_name = "id"
      field_value = $input.task_id
      data = {
        title            : $next_title
        duration_minutes : $next_duration
        notes            : $next_notes
        assignee_agent_id: $next_assignee
        status           : $next_status
        needs_info_reason: $next_reason
        updated_at       : "now"
      }
    } as $updated

    function.run "planner/derive_tasks" {
      input = {workspace_id: $workspace_id, timeline_id: $existing.timeline_id}
    } as $view

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-7"
        step          : "update_task"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $input.task_id
        correlation_id: $input.correlation_id
        message       : "Task updated."
      }
    }
  }

  response = {
    task     : $updated
    container: $view.tasks
  }
}
