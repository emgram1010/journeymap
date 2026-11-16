// COP-2 story 04 - Undo where undo is real. The owner reverses something the copilot did at "Runs, then tells you" (or did after approval). Today ONE kind is truly reversible from here: a note the copilot saved (note_internal) - Undo removes exactly that note. A work update is recorded in the append-only activity log, so it is changed on the task instead, never "undone" here (no false Undo). Admin person of the same account only; never an AI identity.
// Refusals: E-COP-025 (AI), E-COP-029 (not found / another account), E-COP-071 (this kind can't be undone here), E-COP-072 (already undone, or the note was already removed).
// Recorded on the action without a table change: status "seen" + reason "Undone by the owner." - and a COP-2 action_undone event.
query "copilot/action_undo" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int action_id
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "copilot/action_undo", entity_id: $input.action_id}
    } as $admin_user

    function.run "copilot/identity_for_user" {
      input = {user_id: $auth.id}
    } as $me_ai

    precondition ($me_ai.is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can do this. It is ready for the owner to do themselves. (E-COP-025)"
    }

    db.query copilot_action {
      where = $db.copilot_action.id == $input.action_id
      return = {type: "single"}
    } as $act

    var $act_id {
      value = ($act|get:"id":0) ?? 0
    }

    var $status {
      value = ($act|get:"status":"") ?? ""
    }

    var $done {
      value = ($status == "told") || ($status == "seen") || ($status == "executed")
    }

    precondition ($act_id != 0 && ($act|get:"account_id":0) == $admin_user.account_id && $done == true) {
      error_type = "notfound"
      error = "We couldn't find that item. (E-COP-029)"
    }

    var $act_type {
      value = ($act|get:"action_type":"") ?? ""
    }

    precondition ($act_type == "note_internal") {
      error_type = "inputerror"
      error = "This can't be undone here. Change it where it lives (for work, on the task itself). (E-COP-071)"
    }

    var $reason {
      value = ($act|get:"reason":"") ?? ""
    }

    var $already {
      value = $reason|istarts_with:"Undone"
    }

    // The note it saved: same account, business and author, the exact text, made after the action.
    var $approved {
      value = ($act|get:"approved_payload":null) ?? {}
    }

    var $asked {
      value = ($act|get:"payload":null) ?? {}
    }

    var $approved_note {
      value = ($approved|get:"note":"") ?? ""
    }

    var $note_text {
      value = (($approved_note != "") ? $approved_note : (($asked|get:"note":"") ?? ""))
    }

    var $arch_id {
      value = ($act|get:"journey_architecture_id":0) ?? 0
    }

    var $author_id {
      value = ($act|get:"requested_by_user_id":0) ?? 0
    }

    var $since {
      value = (($act|get:"created_at":0) ?? 0) - 60000
    }

    db.query copilot_note {
      where = $db.copilot_note.account_id == $admin_user.account_id && $db.copilot_note.journey_architecture_id == $arch_id && $db.copilot_note.created_by_user_id == $author_id && $db.copilot_note.note == $note_text && $db.copilot_note.created_at >= $since
      sort = {copilot_note.created_at: "desc"}
      return = {type: "list"}
      output = ["id"]
    } as $notes

    var $note_id {
      value = 0
    }

    // The newest match wins (the list is sorted newest first): take the first and stop.
    foreach ($notes) {
      each as $n {
        conditional {
          if ($n.id != 0) {
            var.update $note_id {
              value = (($note_id == 0) ? $n.id : $note_id)
            }
          }
        }
      }
    }

    precondition ($already == false && $note_id != 0 && $note_text != "") {
      error_type = "inputerror"
      error = "That was already undone, or the note was already removed. (E-COP-072)"
    }

    db.transaction {
      stack {
        db.del copilot_note {
          field_name = "id"
          field_value = $note_id
        }

        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: "seen", reason: "Undone by the owner.", updated_at: "now"}
        } as $_undone
      }
    }

    function.run "ops/log_event" {
      input = {feature: "COP-2", step: "action_undone", outcome: "success", severity: "info", error_code: "", message: "The owner undid something the copilot did (a saved note was removed).", user_id: $auth.id, account_id: $admin_user.account_id, entity_type: "copilot_action", entity_id: $act_id, metadata: {action_type: $act_type, note_id: $note_id, journey_architecture_id: $arch_id}}
    } as $_logged
  }

  response = {action_id: $act_id, undone: true}
  tags = ["cop-2"]
}
