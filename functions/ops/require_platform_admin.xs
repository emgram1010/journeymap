// OBS-1 (US-OBS-1-10) — Guard: only platform admins (the founder) may read
// the Health page, call ops/* endpoints, or run a cross-account
// maintenance tool. This is separate from the per-account `user.role`
// ("admin"/"member"), which only controls access within one account — a
// platform admin can act across ALL accounts, so this check must be
// stricter and account-independent.
//
// US-SEC-1-05 (2026-10-19) — EXTENDED, NOT COPIED. SEC-1 needed an
// admin gate for three journey-map maintenance endpoints that can read
// and delete across every account. A second function checking
// `is_platform_admin` would have been the duplication CLAUDE.md warns
// about, and a second error code for "admin only" would have broken
// GUARD-1-01 (a code means exactly one thing). So this one grew three
// things instead, all optional, all defaulting to the previous
// behaviour so the six existing ops callers are untouched:
//
//   1. `what` — the noun in the message. Defaults to "page", which is
//      what the Health page has always said. The journey-map tools pass
//      "maintenance tool", because telling the founder they lack access
//      to a "page" when they called an API is a confusing error.
//   2. `feature`/`step`/`correlation_id`/`account_id` — so a refusal
//      LOGS a `rejected` event through ops/log_event before it throws,
//      the same shape guards/assert_owns uses. Until now an admin
//      refusal was silent: the one guard protecting cross-account
//      deletes left no trace when it fired. A denial should show on the
//      Health page exactly like a failure does (OBS-1).
//   3. A missing user is now folded into the same not-admin path rather
//      than its own precondition, so both refusals log identically.
//
// `E-OBS-001` is reused deliberately. It already means exactly
// "you are not a platform admin", which is precisely what this is.
//
// NOTE: inline `mock`/`test` blocks were attempted here (matching the
// documented function-test pattern) and were REJECTED by this Xano
// workspace's XanoScript parser twice, with two different db action
// types (db.get and db.query) — "Syntax error: unexpected 'mock'".
// Dropped rather than guessed at further against a live system. Real
// correctness is checked by workflow_tests/25_observability.xs and by
// calling the guarded endpoints as both an admin and a non-admin for
// real.
function "ops/require_platform_admin" {
  input {
    int user_id {
      description = "The authenticated user's id ($auth.id in the caller)."
    }

    text what? filters=trim {
      description = "Noun for the refusal message. Defaults to \"page\" (the Health page's existing wording)."
    }

    text feature? filters=trim {
      description = "Epic code of the caller, for the logged event (e.g. 'SEC-1')."
    }

    text step? filters=trim {
      description = "Step within that feature (e.g. 'dedupe_apply')."
    }

    int account_id? {
      description = "The caller's account, for the logged event."
    }

    text correlation_id? filters=trim
  }

  stack {
    db.query user {
      where = $db.user.id == $input.user_id
      return = {type: "single"}
    } as $user

    var $is_admin {
      value = ($user != null && $user.is_platform_admin == true)
      description = "A user id that does not exist is not an admin either — same refusal, same log."
    }

    var $what {
      value = "page"
    }

    conditional {
      if ($input.what != null && $input.what != "") {
        var.update $what {
          value = $input.what
        }
      }
    }

    var $msg {
      value = "You don't have access to this " ~ $what ~ ". (E-OBS-001)"
    }

    var $log_feature {
      value = "OBS-1"
    }

    conditional {
      if ($input.feature != null && $input.feature != "") {
        var.update $log_feature {
          value = $input.feature
        }
      }
    }

    var $log_step {
      value = "require_platform_admin"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    conditional {
      if ($is_admin == false) {
        function.run "ops/log_event" {
          input = {
            feature       : $log_feature
            step          : $log_step
            outcome       : "rejected"
            severity      : "warn"
            error_code    : "E-OBS-001"
            message       : "Platform admin check failed: this caller is not a platform admin."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "user"
            entity_id     : $input.user_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($is_admin) {
      error_type = "accessdenied"
      error = $msg
    }
  }

  response = {ok: true}
}
