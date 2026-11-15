// COP-4 story 06 — an account admin adds a note (note_id 0) or corrects one, for one business.
// Notes are short facts and preferences; never secrets.
query "copilot/note_save" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id?
    int note_id?
    text note? filters=trim
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/note_save"
        entity_id    : 0
      }
    } as $admin_user

    var $account_id {
      value = $admin_user.account_id
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    precondition ($input.journey_architecture_id != 0 && ($arch|get:"account_id":0) == $account_id && $account_id != 0) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    var $note_len {
      value = $input.note|strlen
    }

    precondition ($input.note != "" && $note_len <= 500) {
      error_type = "inputerror"
      error = "A note is one short line (up to 500 characters). (E-COP-049)"
    }

    var $saved_id {
      value = 0
    }

    conditional {
      if ($input.note_id != 0) {
        db.query copilot_note {
          where = $db.copilot_note.id == $input.note_id
          return = {type: "single"}
        } as $existing

        precondition (($existing|get:"account_id":0) == $account_id && ($existing|get:"journey_architecture_id":0) == $input.journey_architecture_id) {
          error_type = "notfound"
          error = "We couldn't find that item. (E-COP-029)"
        }

        db.patch copilot_note {
          field_name = "id"
          field_value = $input.note_id
          data = {note: $input.note, updated_at: "now"}
        } as $_patched

        var.update $saved_id {
          value = $input.note_id
        }
      }

      else {
        db.add copilot_note {
          data = {account_id: $account_id, journey_architecture_id: $input.journey_architecture_id, note: $input.note, created_by_user_id: $auth.id, updated_at: "now"}
        } as $added

        var.update $saved_id {
          value = $added.id
        }
      }
    }
  }

  response = {note_id: $saved_id, note: $input.note}
  tags = ["cop-4"]
}
