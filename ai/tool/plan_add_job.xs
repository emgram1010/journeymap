// COP-5 story 01 — the copilot adds a job to a plan from a published map. The job and its tasks
// are written by planner_ops/create_work_item — the same rule the planner's own endpoint (554)
// holds — so the checks, the pinned version, the events and the tasks are exactly a person's.
// Narrower than a person, on purpose:
//   - only in a copilot conversation about one business; the map must be in it (the gate checks
//     account + business) and so must the plan (copilot/plan_in_business, the one rule);
//   - never a child job: no parent and no attributes are passed, so a job made here can never be
//     an exception child;
//   - it only adds the job to the plan. It schedules nothing and publishes nothing to live.
tool plan_add_job {
  instructions = "Add a job to a plan (workspace_id) from one map (journey_map_id), with a short title (up to 120 characters, no HTML). The job gets its tasks from the map's latest published version and stays pinned to that version. Before calling: the plan must already accept the map (use plan_accept_map first) and the map must have a published version - otherwise this is refused and the message says which. Returns work_item_id, title, task_count and skipped_stages (stages that produced no task, with the reason). It never puts the job on anyone's day, never makes a job under another job, and never publishes anything to live."

  input {
    int workspace_id filters=min:1 {
      description = "The plan to add the job to."
    }

    int journey_map_id filters=min:1 {
      description = "The map the job follows. The plan must already accept it and it must have a published version."
    }

    text title filters=trim {
      description = "A short name for the job, up to 120 characters."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "plan_add_job", kind: "write"}
    } as $cop1_gate

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    // Like any planner, the caller needs the Planner grant.
    function.run "usr/assert_module_access" {
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_add_job"}
    } as $_plan_ok

    // Is this plan in this business? The one rule, in one place.
    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $input.workspace_id, architecture_id: $pin, user_id: $caller_user}
    } as $plan_check

    var $plan_reason {
      value = $plan_check.reason ?? ""
    }

    var $plan_ok {
      value = ($plan_check.ok == true)
    }

    precondition ($plan_reason != "not_found") {
      error_type = "notfound"
      error = "Plan not found"
    }

    precondition ($plan_ok == true) {
      error_type = "accessdenied"
      error = "That plan isn't part of this business. This conversation works on one business only. (E-COP-038)"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    // No attributes and no parent: a job made by the copilot is never an exception child.
    function.run "planner_ops/create_work_item" {
      input = {
        actor              : $actor
        workspace_id       : $input.workspace_id
        journey_map_id     : $input.journey_map_id
        title              : $input.title
        attributes         : {}
        parent_work_item_id: 0
        correlation_id     : ""
      }
    } as $created

    var $job_row {
      value = $created.work_item
    }
  }

  response = {
    work_item_id  : $job_row.id
    title         : $job_row.title
    task_count    : $created.task_count
    skipped_stages: $created.skipped_stages
  }
}
