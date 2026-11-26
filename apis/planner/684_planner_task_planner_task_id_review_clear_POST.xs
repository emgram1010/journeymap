// REPEAT-1 story 05 — Mark ONE slot as reviewed: its "needs review" mark is cleared and kept as history (who, when, how: "one"). A person's action: an AI identity is refused with the shared E-COP-025 (one code means one thing, GUARD-REG-01), so an AI cannot clear marks to make a plan look ready. Another account's slot is "Task not found" (planner/assert_task). An archived plan refuses, like every write on it. A slot with no open mark answers 200 with cleared 0 (clicking twice is harmless). The write is review/clear_marks, the one place a mark is cleared. Logged as plan.review_cleared. Every input is passed to function.run explicitly, because an omitted one silently inherits this endpoint's input of the same name.
query "planner_task/{planner_task_id}/review-clear" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int planner_task_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "review_clear", entity_type: "planner_task", entity_id: $input.planner_task_id}
    } as $_person_only

    function.run "planner/assert_task" {
      input = {account_id: $actor.account_id, task_id: $input.planner_task_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "REPEAT-1"
        step          : "review_clear"
        entity_type   : "planner_task"
        entity_id     : $input.planner_task_id
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    function.run "review/clear_marks" {
      input = {account_id: $actor.account_id, user_id: $actor.user_id, how: "one", planner_task_id: $input.planner_task_id, timeline_id: 0}
    } as $cleared

    function.run "ops/log_event" {
      input = {
        feature       : "REPEAT-1"
        step          : "plan.review_cleared"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "Needs-review mark cleared on one slot."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $input.planner_task_id
        correlation_id: $input.correlation_id
        metadata      : {how: "one", cleared: $cleared.cleared, workspace_id: $guard.workspace.id}
      }
    } as $_logged
  }

  response = {
    planner_task_id: $input.planner_task_id
    cleared        : $cleared.cleared
  }
}
