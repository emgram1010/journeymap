// USR-1 (US-USR-1-05) — Lockout guard.
//
// Refuses any change that would leave an account with no admin who could
// actually sign in. Called by BOTH the role endpoint and the status
// endpoint, which is the whole point: the LOG-1 lesson is that a rule
// copied into two callers eventually disagrees with itself and sounds
// equally confident either way. The admin count is computed here, once.
//
// `excluded_user_id` is the admin who would stop counting — the one being
// demoted, or the one being switched off. Pass 0 for a change that cannot
// reduce the count (a promotion, a reactivation); the guard then simply
// confirms the account already has an admin.
//
// A DEACTIVATED ADMIN DOES NOT COUNT. That is the version of this bug that
// ships: the obvious implementation counts rows in `user` with role
// 'admin', which happily leaves an account administered by somebody who
// cannot sign in.
function "usr/assert_not_last_admin" {
  input {
    int account_id
    int excluded_user_id?
    int actor_user_id?
    text correlation_id? filters=trim
  }

  stack {
    // An omitted optional int arrives as 0, never null (CLAUDE.md), and 0 is
    // never a real user id, so it doubles as "exclude nobody" with no extra
    // flag needed.
    db.query user {
      where = $db.user.account_id == $input.account_id && $db.user.role == "admin" && $db.user.id != $input.excluded_user_id
      return = {type: "list"}
      output = ["id"]
    } as $other_admins

    var $admin_ids {
      // Seeded with a sentinel so the `in` below is never given an empty
      // array — the SEC-1 lesson from `journey/visible_map_ids`. -1 is not a
      // real id, so it matches nothing and changes no count.
      value = [-1]
    }

    foreach ($other_admins) {
      each as $a {
        array.push $admin_ids {
          value = $a.id
        }
      }
    }

    // Side table: a row exists only for someone whose status was touched, so
    // this counts the explicitly switched-off admins among the candidates.
    // Everyone else is active by absence.
    db.query user_status {
      where = $db.user_status.user_id in $admin_ids && $db.user_status.is_active == false
      return = {type: "count"}
    } as $switched_off

    var $remaining {
      value = ($other_admins|count) - $switched_off
    }

    conditional {
      if ($remaining < 1) {
        function.run "ops/log_event" {
          input = {
            feature       : "USR-1"
            step          : "assert_not_last_admin"
            outcome       : "rejected"
            severity      : "warn"
            error_code    : "E-USR-003"
            message       : "Refused: the change would leave the account with no active admin."
            user_id       : $input.actor_user_id
            account_id    : $input.account_id
            entity_type   : "user"
            entity_id     : $input.excluded_user_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($remaining > 0) {
      error_type = "accessdenied"
      error = "That would leave your account with no admin. Make someone else an admin first. (E-USR-003)"
    }
  }

  response = {ok: true, remaining_admins: $remaining}
}
