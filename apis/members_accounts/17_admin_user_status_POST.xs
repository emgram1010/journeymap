// USR-1 (US-USR-1-04) — An admin switches a person off, or back on.
//
// Deactivation, never deletion. A user is referenced by `event_log`,
// `activity_log`, `planner_task`, `work_task` and every job ever performed;
// removing the row orphans history that variance and the Health page read.
// Reactivating restores exactly what was there — role included — because
// nothing was ever taken away.
//
// KNOWN GAP, deliberately left visible rather than quietly scoped out: this
// blocks SIGN-IN (see `auth/login`, which consults the same table) but does
// not yet stop a session that was already open. Anyone holding a token issued
// before they were switched off keeps working until it expires. Closing that
// needs a check on every request, which is exactly what USR-2's middleware is
// for — US-USR-1-04's last scenario is a named failing test until then.
query "admin/user_status" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The user being switched off or back on.
    int user_id

    // true = active, false = deactivated.
    bool is_active
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id", "role"]
    } as $actor

    // Role gate. `accessdenied`, not `notfound`: the caller may see the team,
    // they just may not change it, so hiding the endpoint's existence would
    // only confuse them. Same reasoning as `planner/assert_admin`.
    conditional {
      if ($actor.role != "admin") {
        function.run "ops/log_event" {
          input = {
            feature    : "USR-1"
            step       : "admin/user_status"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-USR-001"
            message    : "Refused: only an account admin can change a user's status."
            user_id    : $auth.id
            account_id : $actor.account_id
            entity_type: "user"
            entity_id  : $input.user_id
          }
        } as $_denied
      }
    }

    precondition ($actor.role == "admin") {
      error_type = "accessdenied"
      error = "Only an account admin can do that. (E-USR-001)"
    }

    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "name", "account_id", "role"]
    } as $target

    // `notfound` for both "does not exist" and "belongs to another account",
    // so a refusal never confirms that an id exists elsewhere — the same
    // shape the tenancy guards use.
    precondition ($target != null) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    precondition ($actor.account_id == $target.account_id) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // Would switching this admin off leave nobody in charge? Checked BEFORE
    // the self-change rule, so the sole admin switching themselves off is
    // told the useful reason rather than the generic one.
    //
    // Only a deactivation of an admin can reduce the count; a reactivation
    // and any change to a member cannot, so those pass 0 ("exclude nobody").
    var $losing_admin_id {
      value = 0
    }

    conditional {
      if ($input.is_active == false && $target.role == "admin") {
        var.update $losing_admin_id {
          value = $target.id
        }
      }
    }

    function.run "usr/assert_not_last_admin" {
      input = {
        account_id      : $actor.account_id
        excluded_user_id: $losing_admin_id
        actor_user_id   : $auth.id
      }
    } as $_lockout_check

    precondition ($actor.id != $target.id) {
      error_type = "accessdenied"
      error = "You can't change your own role or switch yourself off. (E-USR-004)"
    }

    // One row per user at most — enforced by the unique index on `user_id`.
    // `db.patch` with field_name/field_value touches only the FIRST matching
    // row (CLAUDE.md), which is harmless here precisely because the index
    // guarantees there is at most one. Written by `id` anyway, below, so the
    // code does not quietly depend on that.
    db.get user_status {
      field_name = "user_id"
      field_value = $target.id
      output = ["id", "user_id", "is_active"]
    } as $existing

    var $deactivated_at {
      value = null
    }

    conditional {
      if ($input.is_active == false) {
        var.update $deactivated_at {
          value = now
        }
      }
    }

    var $deactivated_by {
      value = 0
    }

    conditional {
      if ($input.is_active == false) {
        var.update $deactivated_by {
          value = $auth.id
        }
      }
    }

    conditional {
      if ($existing == null) {
        db.add user_status {
          data = {
            created_at            : "now"
            updated_at            : "now"
            user_id               : $target.id
            account_id            : $actor.account_id
            is_active             : $input.is_active
            deactivated_at        : $deactivated_at
            deactivated_by_user_id: $deactivated_by
          }
        } as $written
      }

      else {
        db.patch user_status {
          field_name = "id"
          field_value = $existing.id
          data = {
            updated_at            : "now"
            is_active             : $input.is_active
            deactivated_at        : $deactivated_at
            deactivated_by_user_id: $deactivated_by
          }
        } as $written
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "USR-1"
        step       : "admin/user_status"
        outcome    : "success"
        severity   : "info"
        message    : "User status changed."
        user_id    : $auth.id
        account_id : $actor.account_id
        entity_type: "user"
        entity_id  : $target.id
      }
    } as $_logged
  }

  response = {
    user_id  : $target.id
    is_active: $input.is_active
  }

  tags = ["phase-5", "usr-1"]
}
