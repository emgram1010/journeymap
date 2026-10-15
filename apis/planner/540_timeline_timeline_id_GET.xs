// PLN-6 (US-PLN-6-02) — One timeline, with the same derived fields the
// list returns.
//
// Same derivation rules as the list endpoint: the label and the agent's
// name are computed here, never stored, so renaming the agent changes
// them on the next read without writing to this timeline.
//
// ⚠️ `status` RETURNS THE REAL COLUMN. It used to be hardcoded to
// "draft", which was true while publishing was on hold (PLN-6
// Non-Goals) and became a lie the moment LIVE-1 shipped: a published
// timeline still read as a draft, so nothing could tell the two
// apart. Caught while testing LIVE-1's first successful publish.
query "timeline/{timeline_id}" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int timeline_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $guard

    var $timeline {
      value = $guard.timeline
    }

    db.get planner_agent {
      field_name = "id"
      field_value = $timeline.agent_id
    } as $agent

    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id
      return = {type: "list"}
    } as $tasks

    var $total_minutes {
      value = 0
    }

    foreach ($tasks) {
      each as $t {
        var.update $total_minutes {
          value = $total_minutes + $t.duration_minutes
        }
      }
    }

    var $agent_name {
      value = ""
    }

    conditional {
      if ($agent != null) {
        var.update $agent_name {
          value = $agent.name
        }
      }
    }

    var $label {
      value = ($timeline.planned_date|format_timestamp:"M j":"UTC") ~ " — " ~ $agent_name
    }

    var $oow {
      value = ($timeline.planned_date < $guard.workspace.planning_window_start || $timeline.planned_date > $guard.workspace.planning_window_end)
    }
  }

  response = {
    id           : $timeline.id
    workspace_id : $timeline.workspace_id
    agent_id     : $timeline.agent_id
    agent_name   : $agent_name
    label        : $label
    planned_date : $timeline.planned_date
    start_time   : $timeline.start_time
    status       : $timeline.status
    task_count   : ($tasks|count)
    total_minutes: $total_minutes
    out_of_window: $oow
  }
}
