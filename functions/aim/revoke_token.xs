// AIM-1 story 03 — an admin (a person) revokes one access token. The very next call with it is refused; the row and everything the AI member did stay as history. Revoking a token twice changes nothing. Another account's token answers "not found".
function "aim/revoke_token" {
  input {
    int actor_user_id
    int token_id
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "ai_token_revoke"}
    } as $admin

    db.query agent_access_token {
      where = $db.agent_access_token.id == $input.token_id && $db.agent_access_token.account_id == $admin.account_id
      return = {type: "single"}
    } as $row

    var $tid {
      value = $row|get:"id":0
    }

    precondition ($tid != 0) {
      error_type = "notfound"
      error = "Access token not found. (E-AIM-011)"
    }

    var $revoked_at {
      value = (($row|get:"revoked_at":0) ?? 0)|to_int
    }

    var $already {
      value = $revoked_at != 0
    }

    var $ai_user {
      value = $row|get:"user_id":0
    }

    conditional {
      if ($already == false) {
        db.patch agent_access_token {
          field_name = "id"
          field_value = $tid
          data = {revoked_at: "now", revoked_by_user_id: $input.actor_user_id}
        } as $done

        function.run "ops/log_event" {
          input = {feature: "AIM-1", step: "agent_token_revoked", outcome: "success", severity: "info", error_code: "", message: "An AI member's access token was revoked.", user_id: $input.actor_user_id, account_id: $admin.account_id, entity_type: "agent_access_token", entity_id: $tid, correlation_id: "", duration_ms: 0, metadata: {ai_user_id: $ai_user}}
        } as $_ev
      }
    }
  }

  response = {token_id: $tid, revoked: true, was_already_revoked: $already}
}
