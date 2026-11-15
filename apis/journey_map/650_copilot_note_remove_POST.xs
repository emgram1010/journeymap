// COP-4 story 06 — an account admin removes a note the copilot should no longer follow. The
// removal is logged (the note's text is not copied into the log).
query "copilot/note_remove" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int note_id?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/note_remove"
        entity_id    : 0
      }
    } as $admin_user

    var $account_id {
      value = $admin_user.account_id
    }

    db.query copilot_note {
      where = $db.copilot_note.id == $input.note_id
      return = {type: "single"}
    } as $existing

    precondition ($input.note_id != 0 && ($existing|get:"account_id":0) == $account_id) {
      error_type = "notfound"
      error = "We couldn't find that item. (E-COP-029)"
    }

    db.del copilot_note {
      field_name = "id"
      field_value = $input.note_id
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-4"
        step       : "note_removed"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The owner removed a copilot note."
        user_id    : $auth.id
        account_id : $account_id
        entity_type: "copilot_note"
        entity_id  : $input.note_id
        metadata   : {journey_architecture_id: ($existing|get:"journey_architecture_id":0)}
      }
    } as $_logged
  }

  response = {note_id: $input.note_id, removed: true}
  tags = ["cop-4"]
}
