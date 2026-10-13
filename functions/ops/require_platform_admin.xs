// OBS-1 (US-OBS-1-10) — Guard: only platform admins (the founder) may read
// the Health page or call ops/* endpoints. This is separate from the
// per-account `user.role` ("admin"/"member"), which only controls access
// within one account — a platform admin can see events across ALL
// accounts, so this check must be stricter and account-independent.
//
// Mirrors the style of "Getting Started Template/role-based access
// control" but checks is_platform_admin instead of the account role
// hierarchy.
function "ops/require_platform_admin" {
  description = "Throws accessdenied unless the given user is a platform admin."

  input {
    int user_id {
      description = "The authenticated user's id ($auth.id in the caller)."
    }
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "is_platform_admin"]

      mock "allows a platform admin through" {
        value = {id: 1, is_platform_admin: true}
      }

      mock "denies a non-admin user" {
        value = {id: 2, is_platform_admin: false}
      }

      mock "denies an unknown user id" {
        value = null
      }
    } as $user

    precondition ($user != null) {
      error_type = "accessdenied"
      error = "You don't have access to this page. (E-OBS-001)"
    }

    precondition ($user.is_platform_admin == true) {
      error_type = "accessdenied"
      error = "You don't have access to this page. (E-OBS-001)"
    }
  }

  response = {ok: true}

  test "allows a platform admin through" {
    input = {user_id: 1}
    expect.to_equal ($response.ok) {
      value = true
    }
  }

  test "denies a non-admin user" {
    input = {user_id: 2}
    expect.to_throw {
      value = "You don't have access to this page. (E-OBS-001)"
    }
  }

  test "denies an unknown user id" {
    input = {user_id: 999}
    expect.to_throw {
      value = "You don't have access to this page. (E-OBS-001)"
    }
  }
}
