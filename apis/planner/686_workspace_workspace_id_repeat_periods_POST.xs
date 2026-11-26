// REPEAT-1 story 06 — Work out the periods of a repeat for several periods: each one's dates, its own free name, and whether it was already made. Writes nothing (a POST only because the screen sends a small body). The app then makes each period with its own request to POST workspace/{id}/repeat, so each is its own all-or-nothing write. All of the answer comes from repeat/list_periods. Another account's plan is "not found". More than 8 periods (E-REPEAT-010), a bad start date (E-REPEAT-002) or a start that overlaps the source (E-REPEAT-003) is refused with a plain message, and the refusal is logged as plan.repeat_periods / rejected. Every input is passed to function.run explicitly, because an omitted one silently inherits this endpoint's input of the same name.
query "workspace/{workspace_id}/repeat-periods" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text start_date? filters=trim
    int periods?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "repeat/list_periods" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id, start_date: $input.start_date, periods: $input.periods}
    } as $list

    conditional {
      if ($list.reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature    : "REPEAT-1"
            step       : "plan.repeat_periods"
            outcome    : "rejected"
            severity   : "info"
            error_code : $list.reject_code
            message    : $list.reject_msg
            user_id    : $actor.user_id
            account_id : $actor.account_id
            entity_type: "planner_workspace"
            entity_id  : $input.workspace_id
            metadata   : {start_date: $input.start_date, periods: $input.periods}
          }
        } as $_logged
      }
    }

    precondition ($list.reject_code == "") {
      error_type = "inputerror"
      error = $list.reject_msg
    }
  }

  response = {
    source : $list.source
    periods: $list.periods
  }
}
