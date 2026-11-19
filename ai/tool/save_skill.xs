// COP-9 story 02 — the copilot writes down HOW it works: a new skill, exception, lesson or link in
// its own business (the Playbook), or new text for an existing one. Passes the gate like every tool
// (ticket, switched on, daily cap, audit row) with action type skill_write, so the owner's ONE
// level for "write its own skills" applies (default: runs, then tells you). The write itself is
// copilot/skill_write, where the hard limits sit (E-COP-081..084); this tool adds no rule of its own.
// New items start on trial. Every change is a version the owner can undo.
tool save_skill {
  instructions = "Save something you learned about HOW to work, in your own business, the Playbook. kind: skill (a repeatable way to do a task: steps, inputs, what done looks like), exception (WHEN something happens, do this instead - needs condition_text and parent_skill_id), lesson (something a real result taught you), or link (skill parent_skill_id feeds or triggers skill link_to_skill_id). To change an existing item, pass its skill_id with the full new text; leave a field empty to keep it. Never put logins, customer details, permissions or approval rules in a skill - the server refuses them. Tag it with work_kind (map_building, planning, doing_work, research or general). If an item (or the skill an exception changes) is locked by the owner, send the change anyway with a clear reason: it does not change the item, it goes to the owner as an approval request showing before and after (it waits, code E-COP-020). If the owner approves, send exactly the same input again with approval_id. If the item changed after they approved, that re-send waits again as a new request: tell the owner it needs a fresh look. You can never retire a locked item. Facts about one business go in save_note instead."

  input {
    int skill_id? {
      description = "0 for a new item. The item number from the Playbook to change one."
    }

    text kind? filters=trim {
      description = "New items only: skill, exception, lesson or link."
    }

    text title? filters=trim {
      description = "A short name, up to 120 characters."
    }

    text body? filters=trim {
      description = "What to do: steps, inputs, what done looks like (up to 4000 characters)."
    }

    text condition_text? filters=trim {
      description = "Exceptions only: WHEN it applies."
    }

    int parent_skill_id? {
      description = "Exception: the skill it changes. Link: the skill it starts from."
    }

    int link_to_skill_id? {
      description = "Link only: the skill it points to."
    }

    text scope_type? filters=trim {
      description = "Where it applies: all (default), business, map or work_kind."
    }

    int scope_ref_id? {
      description = "business: the journey_architecture_id; map: the journey_map_id."
    }

    text scope_text? filters=trim {
      description = "work_kind only: the kind of work, in plain words."
    }

    text work_kind? filters=trim {
      description = "The job it is for: map_building, planning, doing_work, research or general (default)."
    }

    text reason? filters=trim {
      description = "Why, in one line: what happened that taught you this."
    }

    int conversation_id? {
      description = "The conversation_id from Tool Logging in your context, or 0 in a scheduled run."
    }

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    var $act_title_head {
      value = $input.title|substr:0:120
    }

    // COP-11 "suggest instead": is the item (or the skill it hangs under) locked? Looked up in the
    // caller's own account only. If so, the change always waits for the owner, with before and after.
    function.run "usr/tool_caller" {
      input = {ticket: $input.ticket}
    } as $pre_caller

    var $pre_account {
      value = $pre_caller.account_id ?? 0
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $input.skill_id != 0 && $db.copilot_skill.account_id == $pre_account && $pre_account != 0
      return = {type: "single"}
      output = ["id", "parent_skill_id", "version_no"]
    } as $stored_row

    var $stored_parent {
      value = ($stored_row|get:"parent_skill_id":0) ?? 0
    }

    // The version this change is based on goes into the request, so the owner approves THAT version.
    // Founder decision 2026-11-19: if the item changed after the owner approved (they edited it
    // themselves, say), the approval is not used: the change waits again with a fresh before/after.
    var $stored_version {
      value = ($stored_row|get:"version_no":0) ?? 0
    }

    db.query copilot_action {
      where = $db.copilot_action.id == $input.approval_id && $input.approval_id != 0 && $db.copilot_action.account_id == $pre_account && $pre_account != 0
      return = {type: "single"}
      output = ["id", "payload"]
    } as $prior_appr

    var $prior_payload {
      value = ($prior_appr|get:"payload":null) ?? {}
    }

    var $prior_version {
      value = ($prior_payload|get:"based_on_version":-1) ?? -1
    }

    var $approval_stale {
      value = ($input.approval_id != 0) && ($input.skill_id != 0) && ($prior_version != $stored_version)
    }

    var $gate_approval_id {
      value = (($approval_stale == true) ? 0 : $input.approval_id)
    }

    // The item, the parent the copilot named, and the parent it really has (review 2026-11-19: an
    // edit that left parent_skill_id out missed a locked parent).
    var $lock_ids {
      value = [$input.skill_id, $input.parent_skill_id, $stored_parent]
    }

    db.query copilot_skill_meta {
      where = $db.copilot_skill_meta.account_id == $pre_account && $pre_account != 0 && $db.copilot_skill_meta.skill_id in $lock_ids && $db.copilot_skill_meta.skill_id != 0 && $db.copilot_skill_meta.is_locked == true
      return = {type: "count"}
    } as $locked_count

    var $force_wait {
      value = ($locked_count > 0) || ($approval_stale == true)
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $input.skill_id != 0 && $db.copilot_skill.account_id == $pre_account && $pre_account != 0
      return = {type: "single"}
      output = ["id", "title", "body"]
    } as $before_row

    var $before_title {
      value = ($before_row|get:"title":"") ?? ""
    }

    var $before_body {
      value = (($before_row|get:"body":"") ?? "")|substr:0:300
    }

    var $after_body {
      value = ($input.body ?? "")|substr:0:300
    }

    var $locked_summary {
      value = "Change LOCKED skill #" ~ ($input.skill_id|to_text) ~ " (you locked it; it changes only if you approve). Before: " ~ $before_title ~ ": " ~ $before_body ~ " After: " ~ $act_title_head ~ ": " ~ $after_body
    }

    var $act_summary {
      value = (($input.skill_id == 0) ? ("Save a new " ~ $input.kind ~ " in the Playbook: " ~ $act_title_head) : ("Change skill #" ~ ($input.skill_id|to_text) ~ " in the Playbook: " ~ $act_title_head))
    }

    var $base_summary {
      value = (($force_wait == true && $input.skill_id != 0) ? $locked_summary : $act_summary)
    }

    var $gate_summary {
      value = (($approval_stale == true) ? ("Asking again: this item changed after you approved. " ~ $base_summary) : $base_summary)
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "save_skill", kind: "write", act_type: "skill_write", act_force_wait: $force_wait, act_payload: {skill_id: $input.skill_id, kind: $input.kind, title: $input.title, body: $input.body, condition_text: $input.condition_text, parent_skill_id: $input.parent_skill_id, link_to_skill_id: $input.link_to_skill_id, scope_type: $input.scope_type, scope_ref_id: $input.scope_ref_id, scope_text: $input.scope_text, work_kind: $input.work_kind, reason: $input.reason, based_on_version: $stored_version}, act_summary: $gate_summary, act_approval_id: $gate_approval_id}
    } as $cop1_gate

    var $act_action_id {
      value = $cop1_gate.action_id ?? 0
    }

    var $approved_action_id {
      value = (($gate_approval_id != 0) ? $act_action_id : 0)
    }

    var $act_account_id {
      value = $cop1_gate.account_id ?? 0
    }

    var $act_error {
      value = null
    }

    var $saved {
      value = null
    }

    try_catch {
      try {
        group {
          stack {
            function.run "copilot/skill_trace" {
              input = {ticket: $input.ticket, account_id: $act_account_id, conversation_id: $input.conversation_id}
            } as $trace

            function.run "copilot/skill_write" {
              input = {
                account_id      : $act_account_id
                actor_user_id   : $cop1_gate.user_id
                changed_by      : "copilot"
                op              : (($input.skill_id == 0) ? "create" : "edit")
                skill_id        : $input.skill_id
                kind            : $input.kind
                title           : $input.title
                body            : $input.body
                condition_text  : $input.condition_text
                parent_skill_id : $input.parent_skill_id
                link_to_skill_id: $input.link_to_skill_id
                scope_type      : $input.scope_type
                scope_ref_id    : $input.scope_ref_id
                scope_text      : $input.scope_text
                work_kind       : $input.work_kind
                let_ai_change   : false
                owner_approved_action_id: $approved_action_id
                reason          : $input.reason
                copilot_run_id  : $trace.copilot_run_id
                conversation_id : $trace.conversation_id
              }
            } as $written

            var.update $saved {
              value = $written
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

    function.run "copilot/action_close" {
      input = {action_id: $act_action_id, account_id: $act_account_id, error: $act_error}
    } as $_act_closed
  }

  response = {skill_id: $saved.skill_id, version_no: $saved.version_no, status: $saved.status, kind: $saved.kind}
}
