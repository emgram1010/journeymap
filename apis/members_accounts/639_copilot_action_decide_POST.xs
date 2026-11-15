// COP-2 story 02 — the owner decides one waiting copilot action: approve (exactly what was
// shown), edit (their version), or reject (nothing happens). Only an account admin who is a
// person decides; an AI identity is refused (E-COP-028) even though it cannot sign in today.
//
// Refusals, in order: not found / another account (E-COP-029, same answer); not waiting any more
// (E-COP-021 already decided, or E-COP-024 expired); older than 72 hours (marked expired,
// E-COP-024); out of date — the target map was written to since the draft (marked rejected with
// that reason, E-COP-022, the copilot redrafts); a bad decision (E-COP-032) or an edit with no
// content (E-COP-033); a double click (the second insert into copilot_action_claim fails its
// unique index, E-COP-021). A transaction would not stop the race (CLAUDE.md, endpoint 610).
//
// Approving does NOT run the action here. It records what may run; the copilot carries it out by
// calling the same tool again with approval_id, and the gate lets that through once, only for
// the approved content. approved_payload is written once, onto an empty column, so the json
// merge rule (CLAUDE.md, CRITICAL) cannot mix two versions.
query "copilot/action_decide" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int action_id

    // approve | edit | reject. Optional so this endpoint's own refusal (E-COP-032) can fire.
    text decision? filters=trim|lower

    // For edit: the owner's version of the tool input.
    json edited_payload?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/action_decide"
        entity_id    : $input.action_id
      }
    } as $admin_user

    function.run "copilot/identity_for_user" {
      input = {user_id: $auth.id}
    } as $me_ai

    precondition ($me_ai.is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can approve or reject the copilot's actions. (E-COP-028)"
    }

    var $decision_ok {
      value = ($input.decision == "approve" || $input.decision == "edit" || $input.decision == "reject")
    }

    precondition ($decision_ok) {
      error_type = "inputerror"
      error = "Choose approve, edit or reject. (E-COP-032)"
    }

    db.query copilot_action {
      where = $db.copilot_action.id == $input.action_id
      return = {type: "single"}
    } as $act

    var $act_id {
      value = $act|get:"id":0
    }

    var $act_account {
      value = $act|get:"account_id":0
    }

    precondition ($act_id != 0 && $act_account == $admin_user.account_id) {
      error_type = "notfound"
      error = "We couldn't find that item. (E-COP-029)"
    }

    var $status {
      value = $act|get:"status":""
    }

    precondition ($status != "expired") {
      error_type = "inputerror"
      error = "This item expired without an answer, so it was never carried out. The copilot can draft it again. (E-COP-024)"
    }

    precondition ($status == "waiting") {
      error_type = "inputerror"
      error = "This item has already been decided. (E-COP-021)"
    }

    // ── Expired by age (the hourly task may not have run yet) ──
    var $now_ms {
      value = now|to_int
    }

    var $expire_cutoff {
      value = $now_ms - 259200000
    }

    var $created_ms {
      value = $act|get:"created_at":0
    }

    var $too_old {
      value = ($created_ms < $expire_cutoff)
    }

    conditional {
      if ($too_old == true) {
        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: "expired", updated_at: "now"}
        } as $_aged
      }
    }

    precondition ($too_old == false) {
      error_type = "inputerror"
      error = "This item expired without an answer, so it was never carried out. The copilot can draft it again. (E-COP-024)"
    }

    // ── Edit needs content ──
    var $edit_obj {
      value = $input.edited_payload ?? null
    }

    // An omitted json input does not arrive as null (found live: an edit with nothing in it went
    // through). Treat null, "" (loose == null), {} and [] all as "no content".
    var $edit_text {
      value = $edit_obj|json_encode
    }

    var $edit_missing {
      value = ($input.decision == "edit" && ($edit_obj == null || $edit_text == "{}" || $edit_text == "[]" || $edit_text == "null"))
    }

    precondition ($edit_missing == false) {
      error_type = "inputerror"
      error = "Add your edited version before sending it. (E-COP-033)"
    }

    // ── Out of date: the target map was written to after the draft ──
    var $map_id {
      value = $act|get:"journey_map_id":0
    }

    var $stale_marker {
      value = $act|get:"stale_marker":0
    }

    db.query tool_call_log {
      where = $db.tool_call_log.journey_map_id == $map_id && $map_id != 0 && $db.tool_call_log.kind == "write" && $db.tool_call_log.verdict == "allowed" && $db.tool_call_log.id > $stale_marker
      return = {type: "count"}
    } as $newer_writes

    var $stale {
      value = ($input.decision != "reject" && $newer_writes > 0)
    }

    // ── Claim the decision: a second click fails the unique index ──
    var $claimed {
      value = false
    }

    try_catch {
      try {
        db.add copilot_action_claim {
          data = {copilot_action_id: $act_id, kind: "decide", user_id: $auth.id}
        } as $_claim

        var.update $claimed {
          value = true
        }
      }

      catch {
        var.update $claimed {
          value = false
        }
      }
    }

    precondition ($claimed == true) {
      error_type = "inputerror"
      error = "This item has already been decided. (E-COP-021)"
    }

    conditional {
      if ($stale == true) {
        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: "rejected", reason: "Out of date: the map changed after this was drafted.", decided_by_user_id: $auth.id, decided_at: "now", updated_at: "now"}
        } as $_stale_done

        function.run "ops/log_event" {
          input = {
            feature    : "COP-2"
            step       : "action_decided"
            outcome    : "rejected"
            severity   : "info"
            error_code : "E-COP-022"
            message    : "A copilot action was out of date when the owner tried to approve it."
            user_id    : $auth.id
            account_id : $admin_user.account_id
            entity_type: "copilot_action"
            entity_id  : $act_id
            metadata   : {decision: $input.decision, newer_writes: $newer_writes}
          }
        } as $_stale_logged
      }
    }

    precondition ($stale == false) {
      error_type = "inputerror"
      error = "This is out of date: the map changed after the copilot drafted it. Nothing was done; ask the copilot to draft it again. (E-COP-022)"
    }

    var $new_status {
      value = "rejected"
    }

    var $approved {
      value = null
    }

    conditional {
      if ($input.decision == "approve") {
        var.update $new_status {
          value = "approved"
        }

        var.update $approved {
          value = $act|get:"payload":null
        }
      }

      elseif ($input.decision == "edit") {
        var.update $new_status {
          value = "edited"
        }

        var.update $approved {
          value = $edit_obj
        }
      }
    }

    conditional {
      if ($input.decision == "reject") {
        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: "rejected", decided_by_user_id: $auth.id, decided_at: "now", updated_at: "now"}
        } as $_rejected
      }

      else {
        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: $new_status, approved_payload: $approved, decided_by_user_id: $auth.id, decided_at: "now", updated_at: "now"}
        } as $_approved
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-2"
        step       : "action_decided"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The owner decided a copilot action."
        user_id    : $auth.id
        account_id : $admin_user.account_id
        entity_type: "copilot_action"
        entity_id  : $act_id
        metadata   : {decision: $input.decision, action_type: ($act|get:"action_type":"")}
      }
    } as $_decided_logged
  }

  response = {
    action_id: $act_id
    status   : $new_status
    note     : (($new_status == "rejected") ? "Nothing will be done." : "Approved. The copilot can now carry it out: it reads the approval and runs the tool once, with exactly this content. Approvals not used within 72 hours expire.")
  }
  tags = ["cop-2"]
}
