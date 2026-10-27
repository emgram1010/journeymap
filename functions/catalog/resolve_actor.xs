// CAT-1 — The first call in every catalog endpoint. Turns the signed-in
// user into the three facts every guard needs: who they are, which
// account they belong to, and what they may do.
//
// DELIBERATELY NOT a call to planner/resolve_actor: that function lives
// in functions/planner/, which this epic's build brief says not to open
// or depend on. The logic is a handful of lines (a lookup plus two
// defaults) -- small enough that duplicating it here keeps CAT-1's
// lifecycle independent of the planner epics, which is worth more than
// the few lines saved by sharing it. If a THIRD epic needs this same
// shape, that is the point to extract a cross-epic shared function, not
// before.
//
// A login with no account is notfound, not accessdenied -- it is a
// broken signup, not an attack, and the message says so in plain words.
function "catalog/resolve_actor" {
  input {
    // The caller. Endpoints pass $auth.id -- functions have no $auth of their own.
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
