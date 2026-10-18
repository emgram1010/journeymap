// PLN-8 (US-PLN-8-01) — The whole plan in one request.
//
// The planner frontend's `loadStoredData()` hands the app everything
// at once, so the backend has to offer the same shape or the UI
// becomes a waterfall of requests on every load.
//
// QUERY COUNT IS CONSTANT per entity type — not one per agent,
// timeline or task. A plan with 4 agents and 60 tasks costs the same
// per-entity as one with 1 and 1, which is what US-PLN-8-01 asks for.
// (The one derive call per timeline is a function call, not a scan of
// the whole table; see the Deviations note in the epic.)
//
// Derived values are NOT recomputed here. Timelines reuse the same
// label/out-of-window rules as the timeline list, and tasks come from
// planner/derive_tasks — the single implementation PLN-7 built. The
// epic is explicit that the hydrated read must not re-implement the
// maths, because two implementations will eventually disagree and the
// UI will show one time while the API believes another.
//
// FOUND 2026-10-16 (PLN-9, the first real UI consumer of this
// endpoint): `status` was hardcoded to `"draft"` here, never
// `$tl.status` — the exact same bug LIVE-1 already found and fixed on
// the timeline list and single-timeline read endpoints (539, 540),
// just never applied here. Every published day would have shown as
// still a draft on the one screen built to actually read this field.
// Fixed the same way: read the real column.
//
// Backlog tasks are included in `tasks[]` with `timeline_id: 0` (the
// local spelling of "no timeline") and `planned_start: null`.
//
// GAP-FIX W1 (2026-10-17) — `linked_steps[]` says what each SCHEDULED
// JOB STEP actually is. A slot created by SCHED-1 carries no title on
// purpose (the real text lives in the job's pinned version and is read
// through the link), and nothing had ever read it back, so every job
// step placed on the board rendered as a blank card. One extra
// function call for the whole plan — see planner/job_step_hydration
// for why the join lives there rather than inline here.
query "workspace/{workspace_id}/board" verb=GET {
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
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    var $workspace {
      value = $guard.workspace
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      sort = {planner_agent.created_at: "asc", planner_agent.id: "asc"}
      return = {type: "list"}
    } as $agents

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      sort = {planner_timeline.planned_date: "asc", planner_timeline.id: "asc"}
      return = {type: "list"}
    } as $timelines

    db.get planner_settings {
      field_name = "account_id"
      field_value = $actor.account_id
    } as $settings

    db.query planner_model {
      where = $db.planner_model.account_id == $actor.account_id
      sort = {planner_model.id: "asc"}
      return = {type: "list"}
    } as $models

    var $agent_names {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($agents) {
      each as $a {
        var.update $key {
          value = $a.id|to_text
        }

        var.update $agent_names {
          value = $agent_names|set:$key:$a.name
        }
      }
    }

    // Backlog first, then each day — every task in one flat list, as
    // the frontend's store expects.
    function.run "planner/derive_tasks" {
      input = {workspace_id: $input.workspace_id, timeline_id: 0}
    } as $backlog_view

    var $tasks {
      value = []
    }

    foreach ($backlog_view.tasks) {
      each as $t {
        array.push $tasks {
          value = $t
        }
      }
    }

    var $timeline_views {
      value = []
    }

    var $agent_name {
      value = ""
    }

    var $label {
      value = ""
    }

    var $oow {
      value = false
    }

    foreach ($timelines) {
      each as $tl {
        function.run "planner/derive_tasks" {
          input = {workspace_id: $input.workspace_id, timeline_id: $tl.id}
        } as $tl_view

        foreach ($tl_view.tasks) {
          each as $t {
            array.push $tasks {
              value = $t
            }
          }
        }

        var.update $key {
          value = $tl.agent_id|to_text
        }

        var.update $agent_name {
          value = $agent_names|get:$key:""
        }

        var.update $label {
          value = ($tl.planned_date|format_timestamp:"M j":"UTC") ~ " — " ~ $agent_name
        }

        var.update $oow {
          value = ($tl.planned_date < $workspace.planning_window_start || $tl.planned_date > $workspace.planning_window_end)
        }

        array.push $timeline_views {
          value = {
            id           : $tl.id
            workspace_id : $tl.workspace_id
            agent_id     : $tl.agent_id
            agent_name   : $agent_name
            label        : $label
            planned_date : $tl.planned_date
            start_time   : $tl.start_time
            status       : $tl.status
            out_of_window: $oow
          }
        }
      }
    }

    function.run "planner/job_step_hydration" {
      input = {workspace_id: $input.workspace_id}
    } as $hydration
  }

  response = {
    workspace   : $workspace
    agents      : $agents
    timelines   : $timeline_views
    tasks       : $tasks
    linked_steps: $hydration.steps
    settings    : {
      currency_symbol  : $settings.currency_symbol
      human_hourly_rate: $settings.human_hourly_rate
    }

    models      : $models
  }
}
