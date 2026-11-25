// REPEAT-1 story 02 — Repeat a plan: make the new plan, its accepted maps, its people and their days (stories 03-04 add jobs and slots to the same write). All of the work is repeat/create_plan; this endpoint only resolves who is asking. A refusal (E-REPEAT-002/003/004, E-PLN-001) is a 400 with a plain message, logged as plan.repeat / rejected. "Already repeated to that date" (E-REPEAT-005, including a lost race) is NOT an error: it answers 200 with outcome "exists" and existing_workspace_id, so the screen can link to the plan that was made. A failed write (E-REPEAT-006) is rolled back and logged as plan.repeat_failed. Every input is passed to function.run explicitly (an omitted one inherits this endpoint's input of the same name), and test_fail_at is always 0 here. Hidden in the app until stories 03-04 land.
query "workspace/{workspace_id}/repeat" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text start_date? filters=trim
    text name? filters=trim
    int[] skip_job_ids?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "repeat/create_plan" {
      input = {
        account_id    : $actor.account_id
        user_id       : $actor.user_id
        workspace_id  : $input.workspace_id
        start_date    : $input.start_date
        name          : $input.name
        skip_job_ids  : $input.skip_job_ids
        correlation_id: $input.correlation_id
        test_fail_at  : 0
      }
    } as $result
  }

  response = $result
}
