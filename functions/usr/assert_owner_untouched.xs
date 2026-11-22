// SAFE-1 / D-10 (2026-11-21) — the owner guard, in ONE place. Nobody but the owner themself may
// change the account owner's role, status, name, email or remove them. Called by admin/user_role,
// admin/user_status, admin/user_update and admin/user_delete right after their same-account check.
// The owner is read from account_owner (usr/account_rank). A refusal is logged, then raised (E-SAFE-008).
// An account with no owner row never refuses here.
function "usr/assert_owner_untouched" {
  input {
    int actor_user_id
    int target_user_id
    text step filters=trim
  }

  stack {
    function.run "usr/account_rank" {
      input = {user_id: $input.target_user_id}
    } as $rank

    var $blocked {
      value = ($rank.is_owner == true && $input.actor_user_id != $input.target_user_id)
    }

    conditional {
      if ($blocked) {
        function.run "ops/log_event" {
          input = {
            feature       : "SAFE-1"
            step          : $input.step
            outcome       : "rejected"
            severity      : "warn"
            error_code    : "E-SAFE-008"
            message       : "Refused: only the account owner can change the owner's own login."
            user_id       : $input.actor_user_id
            account_id    : $rank.account_id
            entity_type   : "user"
            entity_id     : $input.target_user_id
            correlation_id: ""
          }
        } as $_denied
      }
    }

    precondition ($blocked == false) {
      error_type = "accessdenied"
      error = "This person owns the account, so only they can change their own login. (E-SAFE-008)"
    }
  }

  response = {ok: true, target_is_owner: $rank.is_owner}
}
