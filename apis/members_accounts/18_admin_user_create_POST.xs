// USR-1 (US-USR-1-02) — An admin adds a person to the account.
//
// THE FOUNDER'S DECISION, 2026-10-22: the admin sets the person's first
// password and passes it on out of band. Of the three options the story
// offered (admin-set password / reuse the existing magic link / a real
// invitation email) this is option 1, chosen deliberately on the grounds
// that the current users are test users and that hardening this flow is
// go-live work. Two consequences are therefore KNOWN and ACCEPTED, not
// oversights, and both are written down in the epic:
//
//   1. The admin knows the person's password until they change it. There is
//      no "must change at next sign-in" flag yet.
//   2. The password crosses the wire in this request body, like every
//      password in this product's existing auth endpoints.
//
// What is NOT accepted, and is handled here:
//   - The password is never stored in plaintext. `user.password` is a
//     `password`-typed column, which Xano hashes on write — the same path
//     `auth/signup` has always used. Proven live: a person created here
//     signed in with the password the admin typed.
//   - The password never reaches `event_log`. That bug has been fixed four
//     times in this workspace already (`auth/login`, `auth/me`,
//     `reset/magic-link-login`, `reset/update_password`, all 2026-10-15),
//     so the metadata here is ids and the role, nothing else.
//   - The response is SHAPED. `db.add` returns every column, so returning
//     the record raw would hand the hashed password and the whole
//     `password_reset` object back to the caller — exactly the bug found in
//     `admin/user_role` on 2026-10-22.
//
// 🔴 `account_id` IS NEVER AN INPUT. It is read from the acting admin's own
// record, via `usr/assert_team_admin`. An account id in a request body is a
// cross-tenant write waiting to happen.
//
// 🔴 EVERY INPUT IS OPTIONAL, AND THAT IS NOT LAXITY. Declared as required,
// Xano rejects a blank one ITSELF, before the stack runs and before auth is
// even checked, with `Missing param: name` and no error code — found live on
// the first probe of this endpoint. The catalogued refusal (`E-USR-011`,
// `E-USR-012`) could never fire, so the Health page could not explain a
// refusal the user had just seen. Optional inputs arrive as "" and the
// preconditions below do the refusing, in this endpoint's own words.
//
// A new person starts with NO module access. Granting Intelligent Layer,
// Planner or Execution is USR-2; until that epic lands, every signed-in user
// can still reach all three, which is why the epic says the UI half must
// never ship without the server half.
query "admin/user_create" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The person's name, as it appears in the team list.
    text name? filters=trim

    // Declared as `text`, not `email`, on purpose: the `email` type refuses
    // a malformed address with Xano's own wording, and this endpoint owes
    // the admin a catalogued code and a sentence they can act on. The shape
    // is checked below, and the column itself is still `email`-typed.
    text email? filters=trim|lower

    // The initial password the admin chooses for them.
    text password?

    // "admin" or "member". Omitted means member — an omitted optional text
    // input arrives as "", never null (CLAUDE.md), so "" is a real case
    // here and is treated as "they did not say".
    text new_role? filters=trim|lower
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/user_create"
      }
    } as $admin_user

    // ── Validation, before anything is written ───────────────────────────
    //
    // Tested with `!= ""` and never with `!= null`: `"" == null` is TRUE in
    // this engine (CLAUDE.md, VAR-1), so a null check cannot tell "left
    // blank" from "sent empty", and both are the same refusal anyway.
    precondition ($input.name != "") {
      error_type = "inputerror"
      error = "A name and an email address are both needed. (E-USR-011)"
    }

    precondition ($input.email != "") {
      error_type = "inputerror"
      error = "A name and an email address are both needed. (E-USR-011)"
    }

    // Deliberately loose: something@something.tld. The point is to catch a
    // typo before it becomes a person who can never sign in, not to
    // adjudicate RFC 5322.
    var $email_looks_right {
      // No backslash escape and no POSIX class in the pattern, on purpose:
      // `[.]` means a literal dot without relying on how this parser treats
      // `\.` inside a string literal, and a `|` inside a string literal is
      // read as a filter separator and breaks outright (CLAUDE.md, LOG-1).
      value = ("/^[^@ ]+@[^@ ]+[.][^@ ]+$/"|regex_matches:$input.email)
    }

    precondition ($email_looks_right) {
      error_type = "inputerror"
      error = "That doesn't look like an email address. (E-USR-014)"
    }

    // The same three rules the `user.password` column's own validators
    // enforce (min:8|minAlpha:1|minDigit:1), checked here so the admin gets
    // a sentence instead of a raw database error. Three simple patterns
    // rather than one with lookaheads, and on ONE line — a multi-line
    // boolean expression fails to parse (CLAUDE.md).
    var $password_ok {
      value = ("/.{8,}/"|regex_matches:$input.password) && ("/[A-Za-z]/"|regex_matches:$input.password) && ("/[0-9]/"|regex_matches:$input.password)
    }

    precondition ($password_ok) {
      error_type = "inputerror"
      error = "A password needs at least 8 characters, including a letter and a number. (E-USR-012)"
    }

    // An unknown role never reaches the enum column. `filters=trim|lower`
    // means "Admin" and " admin " both arrive as "admin"; "" means the
    // caller did not choose and gets the safer of the two.
    var $role_is_known {
      value = ($input.new_role == "" || $input.new_role == "admin" || $input.new_role == "member")
    }

    precondition ($role_is_known) {
      error_type = "inputerror"
      error = "That isn't a role we recognise. Choose admin or member. (E-USR-009)"
    }

    var $role {
      value = "member"
    }

    // The condition reads an INPUT, which is one of the three safe shapes —
    // a conditional whose condition reads a var updated earlier in the same
    // iteration silently discards its writes (CLAUDE.md).
    conditional {
      if ($input.new_role == "admin") {
        var.update $role {
          value = "admin"
        }
      }
    }

    // ── The email must be free, product-wide ─────────────────────────────
    //
    // Not account-wide: `user.email` is how sign-in identifies a person, so
    // one address can belong to exactly one user anywhere in the product.
    // The refusal says the same thing whether the address belongs to this
    // account or another one — it must not confirm who is registered
    // elsewhere.
    db.get user {
      field_name = "email"
      field_value = $input.email
      output = ["id"]
    } as $existing_user

    precondition ($existing_user == null) {
      error_type = "inputerror"
      error = "That email address is already in use. (E-USR-008)"
    }

    db.add user {
      enforce_hidden_fields = false
      data = {
        created_at: "now"
        name      : $input.name
        email     : $input.email
        password  : $input.password
        role      : $role
        account_id: $admin_user.account_id
      }
    } as $new_user

    // No `user_status` row is written. ABSENCE OF A ROW MEANS ACTIVE — that
    // is the whole reason the side table needed no backfill for the users
    // who already existed, and a new person is no different.

    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $admin_user.id
        account_id: $admin_user.account_id
        action    : "created_user"
        metadata  : {
          target_user_id: $new_user.id
          role          : $role
        }
      }
    } as $event_log
  }

  // Shaped, never the raw record — see the header.
  response = {
    id        : $new_user.id
    name      : $new_user.name
    email     : $new_user.email
    account_id: $new_user.account_id
    role      : $new_user.role
  }
  tags = ["phase-5", "usr-1"]
}
