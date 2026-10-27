// USR-1 (US-USR-1-07) — An admin corrects a person's name or email.
//
// `PATCH user/edit_profile` already exists and has since the template: it
// edits the CALLER'S OWN record and takes no user id. That is the right
// endpoint for "change my own details" and is left completely alone. This
// one is the admin's version — fixing a colleague's misspelled name, or
// moving them to a new work address — and it is the half that was missing.
//
// SELF-EDITING IS ALLOWED HERE, unlike role and status. An admin correcting
// their own surname cannot lock anybody out, so `E-USR-004` (which exists to
// stop the sole admin stepping down or switching themselves off) does not
// apply. Role is not editable through this endpoint at all; that is
// `admin/user_role`, and it keeps its own guards.
//
// AN OMITTED FIELD MEANS "LEAVE IT". An omitted optional text input arrives
// as `""`, never null (CLAUDE.md), so `""` is the only signal available for
// "not supplied" — which means this endpoint cannot be used to blank a name
// or an email, and should not be: both are required columns and a person
// with neither cannot sign in or be recognised.
query "admin/user_update" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The person being corrected.
    int user_id

    // Leave either out to keep what is already there.
    text name? filters=trim
    text email? filters=trim|lower
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/user_update"
        entity_id    : $input.user_id
      }
    } as $admin_user

    // At least one of the two has to be a real change, or this is a write
    // with nothing in it.
    var $has_something {
      value = ($input.name != "" || $input.email != "")
    }

    precondition ($has_something) {
      error_type = "inputerror"
      error = "A name and an email address are both needed. (E-USR-011)"
    }

    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "name", "email", "account_id", "role"]
    } as $target_user

    precondition ($target_user != null) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // Same code, same wording, whether the person is missing or simply
    // belongs to another account: a refusal must not confirm that a user id
    // exists somewhere else.
    precondition ($admin_user.account_id == $target_user.account_id) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // ── Resolve the final values before writing ──────────────────────────
    //
    // Each conditional's condition reads an INPUT, which is one of the three
    // safe shapes. A condition that read a var updated earlier in the same
    // iteration would silently discard the branch's writes (CLAUDE.md).
    var $next_name {
      value = $target_user.name
    }

    conditional {
      if ($input.name != "") {
        var.update $next_name {
          value = $input.name
        }
      }
    }

    var $next_email {
      value = $target_user.email
    }

    conditional {
      if ($input.email != "") {
        var.update $next_email {
          value = $input.email
        }
      }
    }

    var $email_looks_right {
      value = ("/^[^@ ]+@[^@ ]+[.][^@ ]+$/"|regex_matches:$next_email)
    }

    precondition ($email_looks_right) {
      error_type = "inputerror"
      error = "That doesn't look like an email address. (E-USR-014)"
    }

    // ── The new address must not belong to somebody else ─────────────────
    //
    // `db.get` by email returns at most one row, since sign-in depends on
    // the address being unique product-wide. Finding THIS person is fine —
    // an admin resaving the same address unchanged must not be refused.
    db.get user {
      field_name = "email"
      field_value = $next_email
      output = ["id"]
    } as $email_owner

    // `$email_owner.id` on a null row would be a missing-var error, so the
    // id is resolved into a plain int first: 0 when nobody holds the
    // address. `|get` with a LITERAL key does honour its default — only a
    // variable key throws the default away (CLAUDE.md).
    var $email_owner_id {
      value = $email_owner|get:"id":0
    }

    var $email_is_free {
      value = ($email_owner_id == 0 || $email_owner_id == $target_user.id)
    }

    precondition ($email_is_free) {
      error_type = "inputerror"
      error = "That email address is already in use. (E-USR-008)"
    }

    db.edit user {
      field_name = "id"
      field_value = $target_user.id
      enforce_hidden_fields = false
      data = {
        name : $next_name
        email: $next_email
      }
    } as $updated_user

    // WHICH fields changed, not what they changed to. The log is read by
    // whoever is supporting the account, and it does not need a second copy
    // of everybody's email address to be useful.
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $admin_user.id
        account_id: $admin_user.account_id
        action    : "updated_user_profile"
        metadata  : {
          target_user_id: $target_user.id
          name_changed  : ($next_name != $target_user.name)
          email_changed : ($next_email != $target_user.email)
        }
      }
    } as $event_log
  }

  // Shaped. `db.edit` returns EVERY column, including the hashed password
  // and the whole `password_reset` object — the bug found live in
  // `admin/user_role` on 2026-10-22.
  response = {
    id        : $updated_user.id
    name      : $updated_user.name
    email     : $updated_user.email
    account_id: $updated_user.account_id
    role      : $updated_user.role
  }
  tags = ["phase-5", "usr-1"]
}
