// For admin to update the role of a user on the same account
//
// USR-1 (2026-10-22) — EXTENDED, not replaced. The endpoint already did the
// admin check, the same-account check and the event log correctly, so writing
// a second one would have been the duplication CLAUDE.md warns about. Three
// things were missing:
//
//   1. `new_role` was a free `text` written straight into an enum column. Any
//      string at all would have been stored. Now checked against the only two
//      roles there are, before anything is written (`E-USR-009`).
//   2. Nothing stopped the only admin demoting themselves, which locks the
//      account out of its own administration with no one to call — the
//      founder is the only support person. Now guarded by
//      `usr/assert_not_last_admin`, shared with `admin/user_status` so the
//      rule exists in exactly one place.
//   3. Nothing stopped a user changing their own role (`E-USR-004`).
//
// Rule ordering is deliberate and matches the frontend's `teamModel.ts`: the
// last-admin check runs BEFORE the self-change check, so the sole admin
// demoting themselves is told "that would leave nobody in charge" rather than
// the blunter "you can't change your own role".
query "admin/user_role" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The ID of the user whose role is to be updated
    int user_id

    // The new role to assign to the user: "admin" or "member".
    text new_role filters=trim|lower
  }

  stack {
    // Retrieve the authenticated user's details
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id", "role"]
    } as $admin_user

    // Verify the authenticated user has the 'admin' role.
    //
    // 🔴 This replaced `function.run "Getting Started Template/role-based
    // access control"`, which was here since the endpoint was created and
    // refused a member by THROWING in a way that came back as **HTTP 200**
    // with a `{"statement":"Throw Error"}` body. Found live 2026-10-22 by
    // calling it as a real member. The frontend only treats a non-2xx as a
    // failure, so a member's role change would have looked like it
    // succeeded, silently. Same inline gate as `admin/user_status` now, so
    // both refuse identically and both log.
    conditional {
      if ($admin_user.role != "admin") {
        function.run "ops/log_event" {
          input = {
            feature    : "USR-1"
            step       : "admin/user_role"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-USR-001"
            message    : "Refused: only an account admin can change a user's role."
            user_id    : $auth.id
            account_id : $admin_user.account_id
            entity_type: "user"
            entity_id  : $input.user_id
          }
        } as $_denied
      }
    }

    precondition ($admin_user.role == "admin") {
      error_type = "accessdenied"
      error = "Only an account admin can do that. (E-USR-001)"
    }

    // USR-1: an unknown role never reaches the database. `filters=trim|lower`
    // above means "Admin" and " admin " both arrive as "admin"; anything else
    // is refused here.
    var $role_is_known {
      value = ($input.new_role == "admin" || $input.new_role == "member")
    }

    precondition ($role_is_known) {
      error_type = "inputerror"
      error = "That isn't a role we recognise. Choose admin or member. (E-USR-009)"
    }

    // Retrieve the target user's details to be updated
    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "created_at", "name", "email", "account_id", "role"]
    } as $target_user

    // Verify that the target user exists
    precondition ($target_user != null) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // Ensure the admin user and target user belong to the same account
    precondition ($admin_user.account_id == $target_user.account_id) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // USR-1: only a DEMOTION of a current admin can reduce the count. A
    // promotion cannot, so it passes 0 ("exclude nobody") and the guard just
    // confirms the account still has one.
    var $losing_admin_id {
      value = 0
    }

    conditional {
      if ($target_user.role == "admin" && $input.new_role == "member") {
        var.update $losing_admin_id {
          value = $target_user.id
        }
      }
    }

    function.run "usr/assert_not_last_admin" {
      input = {
        account_id      : $admin_user.account_id
        excluded_user_id: $losing_admin_id
        actor_user_id   : $auth.id
      }
    } as $_lockout_check

    precondition ($admin_user.id != $target_user.id) {
      error_type = "accessdenied"
      error = "You can't change your own role or switch yourself off. (E-USR-004)"
    }

    // Update the target user's role
    db.edit user {
      field_name = "id"
      field_value = $input.user_id
      enforce_hidden_fields = false
      data = {role: $input.new_role}
    } as $updated_user

    // Log the role update event
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $admin_user.id
        account_id: $admin_user.account_id
        action    : "updated_user_role"
        metadata  : {
          target_user_id: $target_user.id
          previous_role : $target_user.role
          new_role      : $input.new_role
        }
      }
    } as $event_log
  }

  // Shaped, not the raw record. `db.edit` returns EVERY column, so this
  // endpoint was handing back `password` and the whole `password_reset`
  // object (token and expiry) to any admin who changed a role. Found live
  // 2026-10-22 by reading the real response. Same family as the `auth/me`
  // and `auth/login` logging fixes: return the ids and the fields the caller
  // asked about, nothing else.
  response = {
    id        : $updated_user.id
    name      : $updated_user.name
    email     : $updated_user.email
    account_id: $updated_user.account_id
    role      : $updated_user.role
  }
  tags = ["xano:quick-start"]
}
