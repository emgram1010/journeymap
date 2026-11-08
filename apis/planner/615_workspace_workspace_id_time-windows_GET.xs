// TW-1 (US-TW-1-02) — Every time window in a plan, for the planner to
// merge onto its jobs and cards.
//
// WHY A SEPARATE READ, NOT A JOIN IN 548/555/558: a side table nobody
// reads is invisible to the frontend forever (CLAUDE.md, AUTH-1). Adding
// it here touches none of the three large existing reads; the client
// fetches this once alongside them and merges by work_item_id.
// Cancelled jobs are included — the client already hides those jobs.
query "workspace/{workspace_id}/time-windows" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {
        account_id  : $actor.account_id
        workspace_id: $input.workspace_id
      }
    } as $guard

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $jobs

    var $job_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }
      }
    }

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id in $job_ids
      return = {type: "list"}
    } as $rows

    var $windows {
      value = []
    }

    foreach ($rows) {
      each as $r {
        array.push $windows {
          value = {work_item_id: $r.work_item_id, start_date: $r.start_date, start_time: $r.start_time, end_date: $r.end_date, end_time: $r.end_time, note: $r.note}
        }
      }
    }
  }

  response = {
    workspace_id: $input.workspace_id
    windows     : $windows
  }
}
