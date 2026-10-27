// USR-2 (US-USR-2-02) — An admin grants or revokes one module for one person.
//
// ONE MODULE PER CALL, and that is a change from this epic's first draft,
// which specified a list of changes applied in one transaction. The reason is
// worth writing down rather than quietly implementing:
//
//   The Team page has three checkboxes per person and each click is one
//   change, so a list was never going to arrive with more than one item in it.
//   Supporting one anyway would have meant a `foreach` inside a
//   `db.transaction` — and while `db.transaction` is confirmed to mix tables
//   and verbs, and a `conditional` is confirmed to nest inside one, a
//   `foreach` inside one is NOT proven in this workspace. Choosing the
//   unproven construct to solve a problem the UI cannot produce is how an
//   endpoint ends up with a failure mode nobody asked for.
//
// So atomicity across modules is not a thing that can be half-done here: there
// is exactly one row to write. The epic's Decided table records this.
//
// `account_id` is NEVER an input. It comes from the acting admin's own record,
// through `usr/assert_team_admin` — the same rule as every other write in
// USR-1. A caller who could name the account could grant access inside
// somebody else's.
//
// REVOKING DOES NOT DELETE THE ROW. It flips `granted` to false and records
// who and when, so "who took this away?" is answerable from the row itself.
// The unique index on (user_id, module) is what guarantees there is only ever
// one row to disagree with.
query "admin/user_module_access" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The person whose access is changing.
    int user_id

    // One of `intelligence` | `planning` | `execution`. Optional so that this
    // endpoint's OWN refusal (E-USR-007) can fire: a `required` input is
    // validated by Xano itself, before the stack and before auth, which makes
    // the endpoint's catalogued precondition unreachable and returns a raw
    // "Missing param" with no error code. Found the hard way on
    // `admin/user_create`, 2026-10-22.
    text module? filters=trim

    // true = grant, false = revoke.
    bool granted
  }

  stack {
    // The admin gate, the account id and the actor's own record, in one call.
    // Endpoints 11 and 17 still carry an inline copy of this, written before
    // this function existed; folding them in is a tidy-up recorded in USR-1.
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/user_module_access"
        entity_id    : $input.user_id
      }
    } as $actor

    function.run "usr/module_keys" {
      input = {
        check: $input.module
      }
    } as $keys

    conditional {
      if ($keys.valid != true) {
        function.run "ops/log_event" {
          input = {
            feature    : "USR-2"
            step       : "admin/user_module_access"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-USR-007"
            message    : "Refused: unknown module key."
            user_id    : $auth.id
            account_id : $actor.account_id
            entity_type: "user"
            entity_id  : $input.user_id
          }
        } as $_bad_key
      }
    }

    precondition ($keys.valid == true) {
      error_type = "inputerror"
      error = "We don't recognise that module. (E-USR-007)"
    }

    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "account_id"]
    } as $target

    // `notfound` for both "does not exist" and "belongs to another account",
    // so a refusal never confirms that an id exists elsewhere.
    precondition ($target != null) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    precondition ($actor.account_id == $target.account_id) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // 🔴 Nobody edits their own access, in either direction.
    //
    // The lockout this prevents is specific: the only admin revoking their own
    // Intelligent Layer access, after which nobody can reach the maps and
    // nobody can grant it back. Refusing the grant direction too costs almost
    // nothing and means the rule reads the same whichever way the switch moved
    // — a rule with a direction is a rule somebody will find the other side
    // of.
    //
    // E-USR-020 and not E-USR-004: that code already says "you can't change
    // your own role or switch yourself off", which is a different sentence
    // about a different action. One code means one thing — the registry test
    // caught exactly this during USR-1 and E-USR-015 had to be minted.
    conditional {
      if ($actor.id == $target.id) {
        function.run "ops/log_event" {
          input = {
            feature    : "USR-2"
            step       : "admin/user_module_access"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-USR-020"
            message    : "Refused: an admin tried to change their own module access."
            user_id    : $auth.id
            account_id : $actor.account_id
            entity_type: "user"
            entity_id  : $input.user_id
          }
        } as $_self
      }
    }

    precondition ($actor.id != $target.id) {
      error_type = "accessdenied"
      error = "You can't change your own access. Ask another admin. (E-USR-020)"
    }

    // At most one row per (user, module) — the unique index guarantees it, so
    // a single-result query cannot be ambiguous. `|get` with a LITERAL key
    // honours its default; a variable key silently discards it (CLAUDE.md),
    // which is why the key here is written out.
    db.query user_module_access {
      where = $db.user_module_access.user_id == $target.id && $db.user_module_access.module == $input.module
      return = {type: "single"}
      // 🔴 The four audit columns MUST be in this list. They are read back
      // below to be carried forward, and a column left out of `output` comes
      // back absent — so `|get:"granted_by_user_id":0` would quietly return
      // its default and re-introduce the very erasure this is here to stop.
      // A narrower output list would have made the fix look right and do
      // nothing.
      output = ["id", "granted", "granted_by_user_id", "granted_at", "revoked_by_user_id", "revoked_at"]
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    // Who did what, kept on the row as well as in the log. Computed BEFORE
    // the branch, so neither conditional reads a variable written in the same
    // block.
    //
    // 🔴 EACH PAIR DEFAULTS TO WHAT THE ROW ALREADY HOLDS, and only the
    // pair that this call is actually about gets overwritten. The first
    // version seeded all four to 0/null and let the branch fill in two, which
    // meant every revoke silently erased `granted_by_user_id` and
    // `granted_at` — destroying precisely the history this table keeps a bool
    // instead of deleting the row FOR. Caught live on the first revoke,
    // 2026-10-23, by reading the row back rather than trusting the 200.
    var $granted_by {
      value = $existing|get:"granted_by_user_id":0
    }

    var $granted_at {
      value = $existing|get:"granted_at":null
    }

    var $revoked_by {
      value = $existing|get:"revoked_by_user_id":0
    }

    var $revoked_at {
      value = $existing|get:"revoked_at":null
    }

    conditional {
      if ($input.granted == true) {
        var.update $granted_by {
          value = $auth.id
        }

        var.update $granted_at {
          value = now
        }
      }

      else {
        var.update $revoked_by {
          value = $auth.id
        }

        var.update $revoked_at {
          value = now
        }
      }
    }

    conditional {
      if ($existing_id == 0) {
        db.add user_module_access {
          data = {
            created_at        : "now"
            updated_at        : "now"
            user_id           : $target.id
            account_id        : $actor.account_id
            module            : $input.module
            granted           : $input.granted
            granted_by_user_id: $granted_by
            granted_at        : $granted_at
            revoked_by_user_id: $revoked_by
            revoked_at        : $revoked_at
          }
        } as $_written
      }

      else {
        db.patch user_module_access {
          field_name = "id"
          field_value = $existing_id
          data = {
            updated_at        : "now"
            granted           : $input.granted
            granted_by_user_id: $granted_by
            granted_at        : $granted_at
            revoked_by_user_id: $revoked_by
            revoked_at        : $revoked_at
          }
        } as $_written
      }
    }

    // Ids and keys only. Not the person's name, not their email — the Team
    // page resolves the id, and `ops/log_event`'s own contract says metadata
    // carries ids and field names and nothing else.
    function.run "ops/log_event" {
      input = {
        feature    : "USR-2"
        step       : "admin/user_module_access"
        outcome    : "success"
        severity   : "info"
        message    : "Module access changed."
        user_id    : $auth.id
        account_id : $actor.account_id
        entity_type: "user"
        entity_id  : $target.id
        metadata   : {module: $input.module, granted: $input.granted}
      }
    } as $_logged
  }

  response = {
    user_id: $target.id
    module : $input.module
    granted: $input.granted
  }

  tags = ["phase-5", "usr-2"]
}
