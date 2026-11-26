// REPEAT-2 story 03 — Delete a plan. Only an ADMIN PERSON may (a member is refused by usr/assert_team_admin, E-USR-001; an AI identity by copilot/assert_person_only, E-COP-025), only in their own account (another account's plan is "Plan not found"), and only when the plan has NO history (planner/delete_check: a day ever published or work recorded -> E-P3A-001; customer orders or exception work -> E-P3A-004; orders routed into it -> E-P3A-005). A refusal says to archive instead and is logged as plan.delete_refused. The write is planner/delete_workspace_cascade: one all-or-nothing transaction, every row by its own id. A failure inside it removes nothing, is logged as plan.delete_failed and answered with E-P3A-006. After the write this endpoint RE-COUNTS what is left under the plan id (never trusting the function's own tally) and logs a failure if anything is. Deleting a repeated copy also removes its plan_repeat row, so its original can be repeated to that date again. Success is logged as plan.deleted with the counts. Every input is passed to function.run explicitly.
query "workspace/{workspace_id}" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "delete_plan", entity_type: "planner_workspace", entity_id: $input.workspace_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "planner/delete_plan", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "planner/delete_check" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $check

    conditional {
      if ($check.allowed == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-2"
            step          : "plan.delete_refused"
            outcome       : "rejected"
            severity      : "info"
            error_code    : $check.code
            message       : $check.message
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            metadata      : {found: $check.found, name: $check.name}
          }
        } as $_logged_refused
      }
    }

    precondition ($check.allowed == true) {
      error_type = "inputerror"
      error = $check.message
    }

    var $deleted {
      value = {}
    }

    var $write_ok {
      value = false
    }

    var $fail_msg {
      value = ""
    }

    try_catch {
      try {
        group {
          stack {
            function.run "planner/delete_workspace_cascade" {
              input = {workspace_id: $input.workspace_id}
            } as $cascade

            var.update $deleted {
              value = $cascade.deleted
            }

            var.update $write_ok {
              value = true
            }
          }
        }
      }

      catch {
        var.update $fail_msg {
          value = ($error.message ?? "")
        }
      }
    }

    conditional {
      if ($write_ok == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-2"
            step          : "plan.delete_failed"
            outcome       : "failure"
            severity      : "error"
            error_code    : "E-P3A-006"
            message       : "A plan delete failed and removed nothing."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            metadata      : {cause: $fail_msg, name: $check.name}
          }
        } as $_logged_failed
      }
    }

    precondition ($write_ok == true) {
      error_type = "inputerror"
      error = "The plan couldn't be deleted. Nothing was removed. Try again. (E-P3A-006)"
    }

    // Never trust the tally: count what is still there under this plan id.
    db.query planner_workspace {
      where = $db.planner_workspace.id == $input.workspace_id
      return = {type: "count"}
    } as $left_plan

    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $left_slots

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $left_days

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $left_people

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $left_jobs

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $left_maps

    var $left_total {
      value = $left_plan + $left_slots + $left_days + $left_people + $left_jobs + $left_maps
    }

    var $left {
      value = {plan: $left_plan, slots: $left_slots, days: $left_days, people: $left_people, jobs: $left_jobs, maps: $left_maps}
    }

    conditional {
      if ($left_total > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-2"
            step          : "plan.delete_failed"
            outcome       : "failure"
            severity      : "error"
            error_code    : "E-P3A-006"
            message       : "A plan delete reported success but rows were left behind."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            metadata      : {left: $left, deleted: $deleted}
          }
        } as $_logged_left
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "REPEAT-2"
        step          : "plan.deleted"
        outcome       : "success"
        severity      : "warn"
        error_code    : ""
        message       : "A plan was deleted by an admin."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        correlation_id: $input.correlation_id
        metadata      : {name: $check.name, deleted: $deleted, left: $left, freed_repeat_date: $check.frees_repeat_date}
      }
    } as $_logged
  }

  response = {
    deleted_workspace_id: $input.workspace_id
    name                : $check.name
    deleted             : $deleted
    left_behind         : $left_total
    freed_repeat_date   : $check.frees_repeat_date
  }
}
