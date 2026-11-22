// AIM-1 — every change an admin makes to AI members, through one door: action is save (make a login an AI member or change its job), switch (off or back on), token_create, token_revoke or pause_all. Each action is one function in functions/aim, and each of them refuses anyone who is not a person and an account admin (aim/assert_admin_person), so an AI login can never reach any of this. A new token is returned once, here, and never again.
query "admin/ai_member_action" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    text action filters=trim
    int user_id?
    int manager_user_id?
    text purpose? filters=trim
    json allowed_actions?
    json plan_ids?
    int writes_per_hour?
    int writes_per_day?
    bool turn_on?
    text label? filters=trim
    json scope_actions?
    int token_id?
    bool paused?
  }

  stack {
    precondition ($input.action == "save" || $input.action == "switch" || $input.action == "token_create" || $input.action == "token_revoke" || $input.action == "pause_all") {
      error_type = "inputerror"
      error = "action is save, switch, token_create, token_revoke or pause_all."
    }

    var $result {
      value = {}
    }

    conditional {
      if ($input.action == "save") {
        function.run "aim/save_profile" {
          input = {actor_user_id: $auth.id, target_user_id: $input.user_id, manager_user_id: $input.manager_user_id, purpose: $input.purpose, allowed_actions: $input.allowed_actions, plan_ids: $input.plan_ids, writes_per_hour: $input.writes_per_hour, writes_per_day: $input.writes_per_day}
        } as $r_save

        var.update $result {
          value = $r_save
        }
      }

      elseif ($input.action == "switch") {
        function.run "aim/switch_member" {
          input = {actor_user_id: $auth.id, target_user_id: $input.user_id, turn_on: $input.turn_on}
        } as $r_switch

        var.update $result {
          value = $r_switch
        }
      }

      elseif ($input.action == "token_create") {
        function.run "aim/create_token" {
          input = {actor_user_id: $auth.id, target_user_id: $input.user_id, label: $input.label, scope_actions: $input.scope_actions}
        } as $r_token

        var.update $result {
          value = $r_token
        }
      }

      elseif ($input.action == "token_revoke") {
        function.run "aim/revoke_token" {
          input = {actor_user_id: $auth.id, token_id: $input.token_id}
        } as $r_revoke

        var.update $result {
          value = $r_revoke
        }
      }

      else {
        function.run "aim/pause_all" {
          input = {actor_user_id: $auth.id, paused: $input.paused}
        } as $r_pause

        var.update $result {
          value = $r_pause
        }
      }
    }
  }

  response = $result
}
