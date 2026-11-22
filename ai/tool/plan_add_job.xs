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
  instructions = "Add a job to a plan (workspace_id) from one map (journey_map_id), with a short title (up to 120 characters, no HTML). The job gets its tasks from the map's latest published version and stays pinned to that version. Optional items: a JSON list of {item_key, quantity} for what the order contains, e.g. [{\"item_key\": \"chair-adult\", \"quantity\": 14}]. item_key is the catalog item's key; quantity is a whole number 1 to 9999; the same key twice is added together. With items the job's planned time scales with the quantities. A bad quantity refuses the whole call and nothing is added. A key that is not in the catalog is returned under unknown_items, and an item the map has no time for under not_on_map: the job is still created and shows 'no time set' for them. Before calling: the plan must already accept the map (use plan_accept_map first) and the map must have a published version - otherwise this is refused and the message says which. Returns work_item_id, title, task_count, skipped_stages, lines, unknown_items, not_on_map, estimated_minutes and estimate_complete. It never puts the job on anyone's day, never makes a job under another job, and never publishes anything to live."

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

    json items? {
      description = "Optional. What the order contains: [{item_key, quantity}]. Leave out for a job with no items."
    }

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    int journey_architecture_id? {
      description = "Only for an outside assistant (no ticket): the business (architecture id) to plan in. Leave 0 in a copilot chat: the chat's business is used."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // Final review R1: the tool declares its action type, so the owner's level for it is really
    // applied (runs on its own / runs then tells you / waits for you). The summary is what the
    // owner reads; the payload is this tool's exact input, never the ticket.
    var $act_summary {
      value = "Add a job to plan #" ~ ($input.workspace_id|to_text) ~ ": " ~ $input.title
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_add_job", kind: "write", act_type: "plan_draft", act_payload: {workspace_id: $input.workspace_id, journey_map_id: $input.journey_map_id, title: $input.title, items: $input.items}, act_summary: $act_summary, act_approval_id: $input.approval_id}
    } as $cop1_gate

    var $act_action_id {
      value = $cop1_gate.action_id ?? 0
    }

    var $act_account_id {
      value = $cop1_gate.account_id ?? 0
    }

    // Everything from here runs inside a try, so a refusal or a failed write is reported to the
    // approval list (copilot/action_close) before it is passed on unchanged.
    var $act_error {
      value = null
    }

    try_catch {
      try {
        group {
          stack {

    // COP-14 story 03: the chat's business, or (outside door, signed in by token) the one the person
    // named - checked by the gate to be in their account. The ONE rule: copilot/work_business.
    var $gate_pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $gate_via {
      value = $cop1_gate.via ?? ""
    }

    var $gate_context {
      value = $cop1_gate.context ?? ""
    }

    var $gate_account {
      value = $cop1_gate.account_id ?? 0
    }

    function.run "copilot/work_business" {
      input = {pin: $gate_pin, via: $gate_via, context: $gate_context, named: $input.journey_architecture_id, account_id: $gate_account}
    } as $work_biz

    var $pin {
      value = $work_biz.business ?? 0
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This needs one business: use it in a copilot chat about a business or, from an outside assistant, pass journey_architecture_id. (E-COP-045)"
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

    // SCALE-1 story 01: the job's items, checked before anything is written (one rule:
    // estimate/resolve_item_lines). A bad quantity refuses the whole call.
    function.run "estimate/resolve_item_lines" {
      input = {account_id: $caller_account, journey_map_id: $input.journey_map_id, items: $input.items}
    } as $item_lines

    precondition ($item_lines.ok == true) {
      error_type = "inputerror"
      error = $item_lines.message
    }

    var $unmatched {
      value = []
    }

    foreach ($item_lines.unknown_items) {
      each as $ui {
        array.push $unmatched {
          value = {source_system: "", external_id: "", label: $ui.item_key, quantity: $ui.quantity, reason: "unknown_item"}
        }
      }
    }

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
        order_lines        : $item_lines.lines
        unmatched_lines    : $unmatched
      }
    } as $created

    var $job_row {
      value = $created.work_item
    }

    function.run "estimate/estimate_job" {
      input = {work_item_id: $job_row.id}
    } as $est
          }
        }
      }

      catch {
        var.update $act_error {
          value = $error
        }
      }
    }

    // How it ended goes to the approval list; any error is then passed on with its own kind.
    function.run "copilot/action_close" {
      input = {action_id: $act_action_id, account_id: $act_account_id, error: $act_error}
    } as $_act_closed
  }

  response = {
    work_item_id  : $job_row.id
    title         : $job_row.title
    task_count    : $created.task_count
    skipped_stages: $created.skipped_stages
    lines            : $item_lines.lines
    unknown_items    : $item_lines.unknown_items
    not_on_map       : $item_lines.not_on_map
    estimated_minutes: $est.total_minutes
    estimate_complete: $est.complete
  }
}
