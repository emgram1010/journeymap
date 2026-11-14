// SEC-2 (US-SEC-2-04, 2026-11-14) — is this person switched on?
//
// THE ONE PLACE THIS IS DECIDED. Until now the rule lived only inside
// `usr/assert_module_access`, and `auth/login` did not ask at all: proven
// live on 2026-11-14, a member switched off on the Team page signed in with
// their password, was issued a token, and used it. USR-1 story 04 had been
// marked done on the strength of a check that was never in the login
// endpoint.
//
// Extracted rather than copied (the LOG-1 lesson): login, magic-link login
// and the module doors now all ask this function, so they cannot come to
// hold different opinions about what "switched off" means.
//
// ABSENCE OF A ROW MEANS ACTIVE (`user_status`'s own rule). Read with a
// `single` query and `|get` on a LITERAL key: a single query that matches
// nothing yields a value `|get:"is_active":true` handles safely, a variable
// key would silently drop the default, and `false == null` is TRUE in this
// engine, so a null test cannot tell "switched off" from "never set"
// (CLAUDE.md).
//
// The refusal is LOGGED before it is thrown. A switched-off person trying
// the door is exactly what the Health page should be able to show.
//
// Every caller must pass ALL inputs explicitly — an input left out of
// `function.run` inherits the caller's `$input` of the same name.
function "usr/assert_user_active" {
  input {
    int user_id filters=min:1

    // The person's own account, for the logged event. 0 = none.
    int account_id?

    // Epic code and step of the caller, for the logged event.
    text feature filters=trim
    text step filters=trim
  }

  stack {
    db.query user_status {
      where = $db.user_status.user_id == $input.user_id
      return = {type: "single"}
      output = ["id", "is_active"]
    } as $status_row

    var $is_active {
      value = $status_row|get:"is_active":true
    }

    conditional {
      if ($is_active != true) {
        function.run "ops/log_event" {
          input = {
            feature       : $input.feature
            step          : $input.step
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-USR-005"
            message       : "Refused: this person has been switched off."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "user"
            entity_id     : $input.user_id
            correlation_id: ""
            duration_ms   : 0
            metadata      : {}
          }
        } as $_denied
      }
    }

    precondition ($is_active == true) {
      error_type = "accessdenied"
      error = "This account has been switched off. Ask your admin to turn it back on. (E-USR-005)"
    }
  }

  response = {ok: true}
}
