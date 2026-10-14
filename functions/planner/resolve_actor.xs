// PLN-2 (US-PLN-2-01) — The first call in every planner endpoint. Turns
// the signed-in user into the three facts every later guard needs: who
// they are, which account they belong to, and what they may do.
//
// Takes `user_id` rather than reading `$auth.id` directly: a function has
// no `$auth` of its own, so the endpoint passes `$auth.id` in. That also
// makes the function testable without a token.
//
// A login with no account is `notfound`, not `accessdenied` — it is a
// broken signup, not an attack, and the message says so in plain words.
function "planner/resolve_actor" {
  input {
    // The caller. Endpoints pass $auth.id — functions have no $auth of their own.
    int user_id filters=min:1
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $input.user_id
    } as $actor

    precondition ($actor != null) {
      error_type = "notfound"
      error = "User not found"
    }

    var $account_id {
      value = $actor.account_id ?? 0
    }

    precondition ($account_id != 0) {
      error_type = "notfound"
      error = "This login is not attached to an account yet."
    }

    var $role {
      value = $actor.role ?? "member"
    }
  }

  response = {
    user_id   : $actor.id
    account_id: $account_id
    role      : $role
  }
}
