// OBS-1 (US-OBS-1-10) — Guard: only platform admins (the founder) may read
// the Health page or call ops/* endpoints. This is separate from the
// per-account `user.role` ("admin"/"member"), which only controls access
// within one account — a platform admin can see events across ALL
// accounts, so this check must be stricter and account-independent.
//
// Mirrors the style of "Getting Started Template/role-based access
// control" but checks is_platform_admin instead of the account role
// hierarchy.
//
// NOTE: inline `mock`/`test` blocks were attempted here (matching the
// documented function-test pattern) and were REJECTED by this Xano
// workspace's XanoScript parser twice, with two different db action
// types (db.get and db.query) — "Syntax error: unexpected 'mock'".
// Dropped rather than guessed at further against a live system. Real
// correctness is checked by workflow_tests/25_observability.xs and by
// calling ops/health as both an admin and a non-admin user for real.
function "ops/require_platform_admin" {
  description = "Throws accessdenied unless the given user is a platform admin."

  input {
    int user_id {
      description = "The authenticated user's id ($auth.id in the caller)."
    }
  }

  stack {
    db.query user {
      where = $db.user.id == $input.user_id
      return = {type: "single"}
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
}
