// EXC-1 (US-EXC-1-05/06) — A job's family and what each of its steps can
// send away: `parent`, `children[]` and `send_options[]` from
// exceptions/job_links. The planner's job detail and the performer's
// step screen both read this ONE list, so "Send to…" can never offer a
// target on one screen that the other doesn't.
//
// Read-only. Same tenancy rule as 555: the job must be in the caller's
// account. A performer can read it (they can already read the job's
// steps); the spawn endpoint (610) re-checks everything on send.
query "work_item/{work_item_id}/links" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    function.run "exceptions/job_links" {
      input = {work_item_id: $input.work_item_id}
    } as $links
  }

  response = {
    work_item_id: $input.work_item_id
    parent      : $links.parent
    children    : $links.children
    send_options: $links.send_options
  }
}
