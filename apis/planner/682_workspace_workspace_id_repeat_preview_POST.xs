// REPEAT-1 story 01 — Preview a repeat. Returns what repeating this plan would copy and what it would leave out, and writes nothing to the plan. It is a POST only because it takes a list (the jobs the planner unticked); it is a read. The whole answer comes from repeat/preview, the SAME function the AI's plan_repeat tool calls (story 07), and that function runs the same two functions the real copy executes (repeat/build_plan and repeat/plan_work), so the screen, the AI and the copy cannot disagree. Another account's plan is "not found" (planner/assert_workspace, inside build_plan). A bad start date (E-REPEAT-002) or a window that overlaps the source (E-REPEAT-003) is refused with a plain message, and the refusal is logged as plan.repeat_preview / rejected. A successful preview logs nothing: it is a read. Every input is passed to function.run explicitly, because an omitted one silently inherits this endpoint's input of the same name.
query "workspace/{workspace_id}/repeat-preview" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text start_date? filters=trim
    int[] skip_job_ids?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "repeat/preview" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id, start_date: $input.start_date, skip_job_ids: $input.skip_job_ids}
    } as $preview

    conditional {
      if ($preview.reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature    : "REPEAT-1"
            step       : "plan.repeat_preview"
            outcome    : "rejected"
            severity   : "info"
            error_code : $preview.reject_code
            message    : $preview.reject_msg
            user_id    : $actor.user_id
            account_id : $actor.account_id
            entity_type: "planner_workspace"
            entity_id  : $input.workspace_id
            metadata   : {start_date: $input.start_date}
          }
        } as $_logged
      }
    }

    precondition ($preview.reject_code == "") {
      error_type = "inputerror"
      error = $preview.reject_msg
    }
  }

  response = {
    source      : $preview.source
    offer       : $preview.offer
    counts      : $preview.counts
    people      : $preview.people
    jobs        : $preview.jobs
    step_changes: $preview.step_changes
    left_out    : $preview.left_out
  }
}
