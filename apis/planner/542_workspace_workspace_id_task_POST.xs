// PLN-7 (US-PLN-7-02) — Create a task, in the backlog or straight into
// a day.
//
// Omitting `timeline_id` means the backlog. The task is appended at the
// end of whichever container it lands in, and that container is then
// resequenced, so `seq` is always exactly 1..n and no caller ever
// invents a sequence number.
//
// An explicit `assignee_agent_id` is an OVERRIDE, not the normal way to
// assign work: a task in a timeline already belongs to that timeline's
// agent. The override exists for "this one is actually someone else's",
// and it must be an agent of the same plan.
query "workspace/{workspace_id}/task" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text title filters=trim
    int duration_minutes?
    text notes? filters=trim
    int timeline_id?
    int assignee_agent_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-7"
        step       : "create_task"
        entity_type: "planner_workspace"
        entity_id  : $input.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $duration {
      value = 30
    }

    conditional {
      if ($raw_input|has:"duration_minutes") {
        var.update $duration {
          value = $input.duration_minutes
        }
      }
    }

    // Destination must be a timeline of THIS plan, or the backlog.
    conditional {
      if ($input.timeline_id != 0) {
        function.run "planner/assert_timeline" {
          input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
        } as $tl_guard

        function.run "planner/assert_same_workspace" {
          input = {workspace_id_a: $input.workspace_id, workspace_id_b: $tl_guard.timeline.workspace_id}
        }
      }
    }

    // An override assignee must be an agent of THIS plan.
    conditional {
      if ($input.assignee_agent_id != 0) {
        function.run "planner/assert_agent" {
          input = {account_id: $actor.account_id, agent_id: $input.assignee_agent_id}
        } as $ag_guard

        function.run "planner/assert_same_workspace" {
          input = {workspace_id_a: $input.workspace_id, workspace_id_b: $ag_guard.agent.workspace_id}
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
      if ($input.title == null || $input.title == "") {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give the task a title. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input.title|strlen) > 200) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "That title is too long — 200 characters at most. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($duration < 1 || $duration > 1440)) {
        var.update $reject_code {
          value = "E-PLN-013"
        }

        var.update $reject_msg {
          value = "How long should this take? Enter between 1 minute and 24 hours. (E-PLN-013)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-7"
            step          : "create_task"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_task"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Task create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Append at the end; resequence then makes it exactly 1..n.
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id && $db.planner_task.timeline_id == $input.timeline_id
      return = {type: "count"}
    } as $existing_count

    var $append_seq {
      value = $existing_count + 1
    }

    db.add planner_task {
      data = {
        workspace_id     : $input.workspace_id
        timeline_id      : $input.timeline_id
        assignee_agent_id: $input.assignee_agent_id
        title            : $input.title
        seq              : $append_seq
        duration_minutes : $duration
        notes            : $input.notes
        status           : "planned"
        needs_info_reason: ""
        tweak_reason     : ""
      }
    } as $task

    function.run "planner/resequence" {
      input = {workspace_id: $input.workspace_id, timeline_id: $input.timeline_id}
    } as $reseq

    function.run "planner/derive_tasks" {
      input = {workspace_id: $input.workspace_id, timeline_id: $input.timeline_id}
    } as $derived

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-7"
        step          : "create_task"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $task.id
        correlation_id: $input.correlation_id
        message       : "Task created."
      }
    }
  }

  response = {
    task_id  : $task.id
    container: $derived.tasks
  }
}
