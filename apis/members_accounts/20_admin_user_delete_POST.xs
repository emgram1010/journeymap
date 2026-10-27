// USR-1 (US-USR-1-08) — An admin removes a person from the account.
//
// THE FOUNDER ASKED FOR THIS EXPLICITLY on 2026-10-22, having read that the
// epic deliberately had no delete story. It is built, and the reason the
// epic said no is built in as a refusal rather than argued about:
//
// > A person who has done anything is not deleted. They are switched off.
//
// A user id is referenced by `journey_architecture.owner_user`,
// `planner_agent.user_id`, `agent_profile.user_id`,
// `activity_log.performer_user_id` and `event_log.user_id`. Destroying the
// row behind a live reference does not raise an error in this engine — it
// leaves an id pointing at nothing, and the things that read it (variance,
// the Health page, every performed job) go quietly wrong months later. So
// this endpoint counts the references FIRST and refuses with `E-USR-013`
// when it finds any, naming deactivation as the thing to do instead.
//
// What that leaves is a real, useful delete: the invitation typed with the
// wrong address, the test account, the person who never signed in. Exactly
// the rows that are safe to destroy, and nothing else.
//
// WHAT IS NOT COUNTED, on purpose: `event_log`. It is the audit trail, it
// holds `user_id` as a plain int, and an id in a historical log entry
// pointing at a person who has since been removed is what an audit trail is
// FOR. Blocking on it would mean nobody could ever be deleted, since
// signing up writes one.
//
// 🔴 `db.del` ON A ROW THAT DOES NOT EXIST IS NOT A NO-OP. It raises
// `ERROR_CODE_NOT_FOUND` with an EMPTY message — no code, no sentence,
// nothing to look up. Found live on the first real delete: most users have
// no `user_status` row at all (absence means active, which is the whole
// point of that side table), so the unconditional `db.del user_status`
// written here first threw a bare 404 and, being inside the transaction,
// rolled the entire delete back. The transaction did its job; the delete
// never worked. Hence the count below and the conditional around it.
//
// 🔴 TWO ROWS ARE DESTROYED AND NO OTHERS: the person's `user_status` row
// IF THEY HAVE ONE, and their `user` row. Both inside one `db.transaction`,
// so a half-delete is not a state this can reach. `db.del` by
// `field_name` touches only the FIRST match (CLAUDE.md) — safe here because
// both deletes are by a unique key: `user.id` is the primary, and
// `user_status.user_id` carries a unique index.
//
// POST, not DELETE, matching its four siblings in this group — and
// deliberately a static path, `admin/user_delete`, with the id in the body.
// A path like `admin/user/{user_id}` would be shadowed by any earlier
// dynamic sibling in the same group and verb, a trap that left endpoint 210
// dead from the day it was created (PLN-9, CLAUDE.md).
query "admin/user_delete" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The person being removed. Permanently.
    int user_id
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/user_delete"
        entity_id    : $input.user_id
      }
    } as $admin_user

    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "name", "email", "account_id", "role"]
    } as $target_user

    precondition ($target_user != null) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    precondition ($admin_user.account_id == $target_user.account_id) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // Checked before the lockout guard would even be asked: deleting
    // yourself is never the answer, and an admin who did it would be
    // holding a token for a user row that no longer exists.
    // ITS OWN CODE, not a second meaning for E-USR-004.
    //
    // E-USR-004 says "you can't change your own role or switch yourself
    // off", and reusing it here would have made one code mean two things,
    // which GUARD-1-01 forbids and `errorCodeRegistry.test.ts` caught on the
    // first run after this endpoint was written. Removal is a different
    // action with a different remedy — nobody can undo it — so it gets
    // E-USR-015.
    precondition ($admin_user.id != $target_user.id) {
      error_type = "accessdenied"
      error = "You can't remove your own account. Ask another admin to do it. (E-USR-015)"
    }

    // The same lockout rule as demotion and deactivation, from the same
    // single place. Deleting an admin reduces the admin count exactly as
    // demoting one does, so it passes the target's id as the admin who
    // would stop counting.
    var $losing_admin_id {
      value = 0
    }

    conditional {
      if ($target_user.role == "admin") {
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

    // ── Is anything pointing at this person? ─────────────────────────────
    //
    // `return = {type: "count"}` gives a plain int without loading rows,
    // which is the confirmed-working way to count (CLAUDE.md). Four separate
    // counts rather than one clever query, because each one names a
    // different thing in the refusal's log line.
    db.query journey_architecture {
      where = $db.journey_architecture.owner_user == $target_user.id
      return = {type: "count"}
    } as $owned_architectures

    db.query planner_agent {
      where = $db.planner_agent.user_id == $target_user.id
      return = {type: "count"}
    } as $agent_links

    db.query agent_profile {
      where = $db.agent_profile.user_id == $target_user.id
      return = {type: "count"}
    } as $agent_profiles

    db.query activity_log {
      where = $db.activity_log.performer_user_id == $target_user.id
      return = {type: "count"}
    } as $performed_steps

    var $references {
      value = $owned_architectures + $agent_links + $agent_profiles + $performed_steps
    }

    conditional {
      if ($references > 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "USR-1"
            step       : "admin/user_delete"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-USR-013"
            message    : "Refused: the person still has work in the system. Deactivation is the right move."
            user_id    : $auth.id
            account_id : $admin_user.account_id
            entity_type: "user"
            entity_id  : $target_user.id
            metadata   : {
              owned_architectures: $owned_architectures
              agent_links        : $agent_links
              agent_profiles     : $agent_profiles
              performed_steps    : $performed_steps
            }
          }
        } as $_blocked
      }
    }

    precondition ($references == 0) {
      error_type = "accessdenied"
      error = "That person has work in the system, so removing them would break its history. Switch them off instead. (E-USR-013)"
    }

    // Does this person have a status row at all? Most do not — absence
    // means active. See the 🔴 note in the header for what happens if you
    // skip this and delete unconditionally.
    db.query user_status {
      where = $db.user_status.user_id == $target_user.id
      return = {type: "count"}
    } as $status_rows

    // ── The delete itself ────────────────────────────────────────────────
    //
    // `db.del` takes no `as` clause and returns nothing (CLAUDE.md), so
    // there is no result to check here; the counts above are what make this
    // safe, and the transaction is what makes it all-or-nothing.
    //
    // The conditional's condition reads a var computed BEFORE this block,
    // which is one of the safe shapes — the trap is a condition reading a
    // var updated earlier in the same loop iteration, and there is no loop
    // here. Confirmed live: a `conditional` DOES work inside a
    // `db.transaction`.
    db.transaction {
      stack {
        conditional {
          if ($status_rows > 0) {
            db.del user_status {
              field_name = "user_id"
              field_value = $target_user.id
            }
          }
        }

        db.del user {
          field_name = "id"
          field_value = $target_user.id
        }
      }
    }

    // Logged AFTER the delete, so the entry is only ever written for a
    // delete that actually happened.
    //
    // IDS AND THE ROLE, NOT THE NAME AND EMAIL. The tempting argument is
    // that the row is gone, so this entry is the last record the person was
    // ever here and should therefore hold their details. That argument is
    // exactly the one behind the four logging bugs fixed in this workspace
    // on 2026-10-15 — `auth/login`, `auth/me`, `reset/magic-link-login` and
    // `reset/update_password` each wrote a whole user record into
    // `event_log` for a plausible-sounding reason. `ops/log_event`'s own
    // contract says ids and field names, never emails. The trail survives
    // without them: this account's earlier entries for the same
    // `target_user_id` are still there, `created_user` among them.
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $admin_user.id
        account_id: $admin_user.account_id
        action    : "deleted_user"
        metadata  : {
          target_user_id      : $target_user.id
          deleted_role        : $target_user.role
          had_status_row      : ($status_rows > 0)
        }
      }
    } as $event_log
  }

  response = {
    deleted_user_id: $target_user.id
    deleted        : true
  }
  tags = ["phase-5", "usr-1"]
}
