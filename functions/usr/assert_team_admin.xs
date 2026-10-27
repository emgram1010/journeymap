// USR-1 — the admin gate for every team endpoint, in ONE place.
//
// Five endpoints now answer "may this caller administer the account's
// people": `admin/user_role`, `admin/user_status`, `admin/user_create`,
// `admin/user_update` and `admin/user_delete`. The gate was written inline
// in the first two, and copying it three more times is precisely the
// duplication LOG-1 earned its lesson on: a rule living in five places
// eventually disagrees with itself and sounds equally certain in every copy.
//
// 🔴 WHY THIS IS NOT A ONE-LINE CHECK. The gate it replaces was
// `function.run "Getting Started Template/role-based access control"`, which
// refused a member by THROWING in a way that reached the client as **HTTP
// 200** with a `{"statement":"Throw Error"}` body. The frontend only treats
// a non-2xx as a failure, so a member's change looked like it had worked.
// Found live 2026-10-22 by calling it as a real member. A refusal here is an
// `accessdenied` precondition, which is a real 403, and it is logged before
// it is raised — never a silent refusal (OBS-1).
//
// Returns the ACTOR'S OWN record, because that is where `account_id` comes
// from. No team endpoint may ever take an account id from a request body:
// an account id in a body is a cross-tenant write waiting to happen.
function "usr/assert_team_admin" {
  input {
    int actor_user_id

    // Which endpoint is asking. Only ever used in the log line, so a
    // refusal in the Health page says which door was tried.
    text step filters=trim

    // The person being acted on, when there is one. An omitted optional int
    // arrives as 0, never null (CLAUDE.md), and 0 is not a real user id, so
    // it reads correctly as "no particular target" in the log.
    int entity_id?

    text correlation_id? filters=trim
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $input.actor_user_id
      output = ["id", "account_id", "role"]
    } as $actor

    // A real id starts at 1 and a found row is an object, so `== null` is
    // safe here — unlike against a field that could legitimately be 0, ""
    // or false, where PHP-loose equality makes it useless (CLAUDE.md,
    // VAR-1).
    precondition ($actor != null) {
      error_type = "accessdenied"
      error = "We couldn't find your user record. (E-USR-010)"
    }

    conditional {
      if ($actor.role != "admin") {
        function.run "ops/log_event" {
          input = {
            feature       : "USR-1"
            step          : $input.step
            outcome       : "rejected"
            severity      : "warn"
            error_code    : "E-USR-001"
            message       : "Refused: only an account admin can manage the account's people."
            user_id       : $input.actor_user_id
            account_id    : $actor.account_id
            entity_type   : "user"
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
          }
        } as $_denied
      }
    }

    precondition ($actor.role == "admin") {
      error_type = "accessdenied"
      error = "Only an account admin can do that. (E-USR-001)"
    }
  }

  response = {id: $actor.id, account_id: $actor.account_id, role: $actor.role}
}
