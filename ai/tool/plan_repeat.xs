// REPEAT-1 story 07 - the copilot (or an outside assistant) previews, or drafts, "this plan again for the next period". It does what the planner's screen does and nothing more: the preview is repeat/preview (the SAME function the screen's preview endpoint calls) and the draft is repeat/create_plan (the SAME function the screen's Create button calls), so the checks, the copied rows, the review marks, the error codes and the events are exactly a person's.
// Narrower than a person, on purpose:
//   - it makes ONE plan per call. Planning further ahead is another call, and each call is one write at the gate, so a repeat counts against the AI's hourly and daily write caps as one write per plan made;
//   - it never publishes. The new plan is a draft whose copied slots are all marked "needs review"; it never clears a mark either (clearing is a person's action);
//   - it never edits ai_member_profile.plan_ids: whether an AI may work in the new plan is its manager's call, made on the AI member's own settings;
//   - it only reaches plans the AI member is allowed to work in (copilot/plan_in_business, the one rule: another plan answers exactly like one that does not exist).
// An omitted optional input is read as empty, never as "yes": create is false unless the caller says true, so forgetting it can only ever preview.
tool plan_repeat {
  instructions = "Repeat a plan for the next period, as a DRAFT for a person to review. First PREVIEW (leave create false): it writes nothing and returns what would be copied and, in `message`, what would be LEFT OUT and why. Then, if the owner wants it, call again with create set to true and a start_date (YYYY-MM-DD) to make the new plan. workspace_id is the plan to repeat: find it with plan_list. start_date is the first day of the new plan; the new plan is as long as the old one. Leave start_date empty in a preview to see the day offered (the day after the old plan ends). In a preview you may also set periods (1 to 8) to list several consecutive periods with their dates and names; creating always makes ONE plan per call, so for the next period call again with that period's start_date (copy it from the list). Returns mode (preview, draft or exists), message (read it to the owner: it starts with what was left out when something was), left_out_lines, counts, workspace_id, name, start_date, end_date and periods. What the draft is: the same people, days, jobs (on each map's CURRENT published version) and scheduled slots, moved to the new dates; every copied slot is marked 'needs review'. It is only a DRAFT: you never publish it to live and you never clear a review mark; a person has to review it and press Publish to live. It does not give you access to the new plan."

  input {
    int workspace_id filters=min:1 {
      description = "The plan to repeat (the source). Find it with plan_list."
    }

    text start_date? filters=trim {
      description = "YYYY-MM-DD, the first day of the new plan. Leave empty in a preview to see the day offered. Required to create."
    }

    bool create? {
      description = "Leave false to only PREVIEW (nothing is written). Set true to make the new draft plan."
    }

    int periods? {
      description = "Preview only. How many consecutive periods to list, 1 to 8. Leave 0 to skip. Creating always makes one plan per call."
    }

    json skip_job_ids? {
      description = "Optional. A JSON list of job ids not to repeat, e.g. [12, 15]."
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
    // The gate is told what kind of call this is: a preview is a read (no approval, no cap); only
    // creating is a write with an action type, so the owner's level for "draft a plan" is applied.
    var $creating {
      value = ($input.create == true)
    }

    var $gate_kind {
      value = (($creating == true) ? "write" : "read")
    }

    var $act_type {
      value = (($creating == true) ? "plan_draft" : "")
    }

    var $act_summary {
      value = (($creating == true) ? ("Repeat plan #" ~ ($input.workspace_id|to_text) ~ " as a draft starting " ~ $input.start_date) : ("Preview repeating plan #" ~ ($input.workspace_id|to_text)))
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_repeat", kind: $gate_kind, act_type: $act_type, act_payload: {workspace_id: $input.workspace_id, start_date: $input.start_date, create: $input.create, periods: $input.periods, skip_job_ids: $input.skip_job_ids}, act_summary: $act_summary, act_approval_id: $input.approval_id}
    } as $cop1_gate

    var $act_action_id {
      value = $cop1_gate.action_id ?? 0
    }

    var $act_account_id {
      value = $cop1_gate.account_id ?? 0
    }

    var $out_mode {
      value = "preview"
    }

    var $out_message {
      value = ""
    }

    var $out_lines {
      value = []
    }

    var $out_counts {
      value = {}
    }

    var $out_ws {
      value = 0
    }

    var $out_name {
      value = ""
    }

    var $out_start {
      value = ""
    }

    var $out_end {
      value = ""
    }

    var $out_periods {
      value = []
    }

    // An omitted list is empty, never null (an omitted optional input must never change the request).
    var $skip_ids {
      value = ($input.skip_job_ids ?? [])
    }

    var $act_error {
      value = null
    }

    try_catch {
      try {
        group {
          stack {

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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_repeat"}
    } as $_plan_ok

    // May this conversation (and, for an AI member, this member) touch this plan? The one rule.
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

    // What would a repeat do? The same function the screen's preview calls.
    function.run "repeat/preview" {
      input = {account_id: $caller_account, workspace_id: $input.workspace_id, start_date: $input.start_date, skip_job_ids: $skip_ids}
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
            user_id    : $caller_user
            account_id : $caller_account
            entity_type: "planner_workspace"
            entity_id  : $input.workspace_id
            metadata   : {start_date: $input.start_date, via: "plan_repeat"}
          }
        } as $_logged_reject
      }
    }

    precondition ($preview.reject_code == "") {
      error_type = "inputerror"
      error = $preview.reject_msg
    }

    // Everything that would be (or was) left out, in one list, then in plain words.
    var $left_all {
      value = []
    }

    foreach ($preview.jobs) {
      each as $pj {
        conditional {
          if ($pj.verdict != "repeat") {
            array.push $left_all {
              value = {kind: "job", name: $pj.title, reason: $pj.reason}
            }
          }
        }
      }
    }

    var $made {
      value = {}
    }

    var $made_ok {
      value = false
    }

    conditional {
      if ($creating == true) {
        precondition ($input.start_date != "") {
          error_type = "inputerror"
          error = "Say which start date to use (YYYY-MM-DD). Preview first: it shows the day offered. (E-REPEAT-002)"
        }

        // THE write: the same function the screen's Create button runs. One plan, all or nothing.
        function.run "repeat/create_plan" {
          input = {account_id: $caller_account, user_id: $caller_user, workspace_id: $input.workspace_id, start_date: $input.start_date, name: $preview.offer.name, skip_job_ids: $skip_ids, correlation_id: "", test_fail_at: 0}
        } as $made_row

        var.update $made {
          value = $made_row
        }

        var.update $made_ok {
          value = ($made_row.outcome == "created")
        }

        foreach ($made_row.left_out) {
          each as $mo {
            array.push $left_all {
              value = $mo
            }
          }
        }
      }

      else {
        foreach ($preview.left_out) {
          each as $po {
            array.push $left_all {
              value = $po
            }
          }
        }

        foreach ($preview.people) {
          each as $pp {
            conditional {
              if ($pp.left_off == true) {
                array.push $left_all {
                  value = {kind: "person", name: $pp.name, reason: "switched_off"}
                }
              }
            }
          }
        }
      }
    }

    function.run "repeat/describe_left_out" {
      input = {left_out: $left_all}
    } as $described

    var.update $out_lines {
      value = $described.lines
    }

    var $lead {
      value = (($described.count > 0) ? ("Left out (" ~ ($described.count|to_text) ~ "): " ~ ($described.lines|join:" ") ~ " ") : "")
    }

    // Preview with several periods: the list the owner can pick from.
    conditional {
      if ($creating == false && $input.periods != 0) {
        function.run "repeat/list_periods" {
          input = {account_id: $caller_account, workspace_id: $input.workspace_id, start_date: $input.start_date, periods: $input.periods}
        } as $plist

        precondition ($plist.reject_code == "") {
          error_type = "inputerror"
          error = $plist.reject_msg
        }

        var.update $out_periods {
          value = $plist.periods
        }
      }
    }

    conditional {
      if ($creating == true && $made_ok == true) {
        var.update $out_mode {
          value = "draft"
        }

        var.update $out_ws {
          value = $made.workspace_id
        }

        var.update $out_name {
          value = $made.name
        }

        var.update $out_start {
          value = $made.start_date
        }

        var.update $out_end {
          value = $made.end_date
        }

        var.update $out_counts {
          value = $made.counts
        }

        var.update $out_message {
          value = $lead ~ "Draft plan made: " ~ $made.name ~ " (" ~ $made.start_date ~ " to " ~ $made.end_date ~ "). It is only a DRAFT: nothing was published, and every copied slot is marked 'needs review'. A person must review it and press Publish to live. You cannot publish it or clear the review marks."

        // The manager of an AI member is on the record for what it made.
        db.query ai_member_profile {
          where = $db.ai_member_profile.user_id == $caller_user
          return = {type: "single"}
        } as $ai_profile

        var $mgr_id {
          value = $ai_profile|get:"manager_user_id":0
        }

        var $ai_pid {
          value = $ai_profile|get:"id":0
        }

        conditional {
          if ($ai_pid != 0) {
            function.run "ops/log_event" {
              input = {
                feature       : "REPEAT-1"
                step          : "plan.repeat_by_ai"
                outcome       : "success"
                severity      : "info"
                error_code    : ""
                message       : "An AI member drafted a repeat of a plan."
                user_id       : $caller_user
                account_id    : $caller_account
                entity_type   : "planner_workspace"
                entity_id     : $made.workspace_id
                correlation_id: ""
                metadata      : {source_workspace_id: $input.workspace_id, new_workspace_id: $made.workspace_id, manager_user_id: $mgr_id, ai_member_profile_id: $ai_pid}
              }
            } as $_logged_ai
          }
        }
      }

      elseif ($creating == true) {
        var.update $out_mode {
          value = "exists"
        }

        var.update $out_ws {
          value = $made.existing_workspace_id
        }

        var.update $out_start {
          value = $input.start_date
        }

        var.update $out_message {
          value = "This plan was already repeated to that start date, so nothing new was made. The earlier copy is plan #" ~ ($made.existing_workspace_id|to_text) ~ "."
        }
      }

      else {
        var.update $out_counts {
          value = $preview.counts
        }

        var.update $out_name {
          value = $preview.offer.name
        }

        var.update $out_start {
          value = $preview.offer.start_date
        }

        var.update $out_end {
          value = $preview.offer.end_date
        }

        var.update $out_message {
          value = $lead ~ "Preview only: nothing was made. Repeating this plan would make " ~ $preview.offer.name ~ " (" ~ $preview.offer.start_date ~ " to " ~ $preview.offer.end_date ~ ") as a DRAFT for a person to review. To make it, call again with create set to true and start_date " ~ $preview.offer.start_date ~ "."
        }
      }
    }
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
    mode            : $out_mode
    message         : $out_message
    left_out_lines  : $out_lines
    counts          : $out_counts
    workspace_id    : $out_ws
    name            : $out_name
    start_date      : $out_start
    end_date        : $out_end
    periods         : $out_periods
    is_draft        : ($out_mode == "draft")
    published       : false
  }
}
