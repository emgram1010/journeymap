// AIM-1 story 06 — the account-wide "Pause all AI" switch, pressed by an admin (a person). Paused: every AI member in the account is refused on its next call (aim/check, E-AIM-041) and incoming orders are held instead of processed. Turning it back on lets AI members work again with the tokens they have. One row per account (unique index).
function "aim/pause_all" {
  input {
    int actor_user_id
    bool paused?
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "ai_pause_all"}
    } as $admin

    var $want {
      value = $input.paused == true
    }

    db.query account_ai_pause {
      where = $db.account_ai_pause.account_id == $admin.account_id
      return = {type: "single"}
    } as $row

    var $rid {
      value = $row|get:"id":0
    }

    var $step {
      value = "ai_resumed_all"
    }

    conditional {
      if ($want) {
        var.update $step {
          value = "ai_paused_all"
        }
      }
    }

    conditional {
      if ($rid == 0) {
        db.add account_ai_pause {
          data = {created_at: "now", updated_at: "now", account_id: $admin.account_id, is_paused: $want, updated_by_user_id: $input.actor_user_id}
        } as $made
      }

      else {
        db.patch account_ai_pause {
          field_name = "id"
          field_value = $rid
          data = {is_paused: $want, updated_at: "now", updated_by_user_id: $input.actor_user_id}
        } as $saved
      }
    }

    function.run "ops/log_event" {
      input = {feature: "AIM-1", step: $step, outcome: "success", severity: "warn", error_code: "", message: "Pause all AI was turned on or off for the account.", user_id: $input.actor_user_id, account_id: $admin.account_id, entity_type: "account", entity_id: $admin.account_id, correlation_id: "", duration_ms: 0, metadata: {paused: $want}}
    } as $_ev
  }

  response = {account_id: $admin.account_id, is_paused: $want}
}
