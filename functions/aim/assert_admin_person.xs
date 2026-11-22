// AIM-1 story 08 — only a PERSON who is an account admin may manage AI members, their tokens and the pause switches. usr/assert_team_admin decides "admin" (one rule); this adds "and not an AI": a login with an ai_member_profile or an ai_identity row is refused (E-AIM-062), so an AI can never widen its own access even if its role were ever changed.
function "aim/assert_admin_person" {
  input {
    int actor_user_id
    text step filters=trim
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $input.actor_user_id, step: $input.step, entity_id: 0, correlation_id: ""}
    } as $admin

    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.actor_user_id
      return = {type: "count"}
    } as $as_member

    db.query ai_identity {
      where = $db.ai_identity.user_id == $input.actor_user_id
      return = {type: "count"}
    } as $as_copilot

    var $is_ai {
      value = ($as_member + $as_copilot) > 0
    }

    conditional {
      if ($is_ai) {
        function.run "ops/log_event" {
          input = {feature: "AIM-1", step: $input.step, outcome: "rejected", severity: "error", error_code: "E-AIM-062", message: "An AI login tried to manage AI members. It was refused.", user_id: $input.actor_user_id, account_id: $admin.account_id, entity_type: "user", entity_id: $input.actor_user_id, correlation_id: "", duration_ms: 0, metadata: {}}
        } as $_ev
      }
    }

    precondition ($is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can manage AI members. (E-AIM-062)"
    }
  }

  response = {id: $admin.id, account_id: $admin.account_id}
}
