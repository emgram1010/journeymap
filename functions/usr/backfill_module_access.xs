// USR-2 (US-USR-2-01) — give everybody who already exists all three modules,
// so that switching enforcement on changes nothing for them.
//
// 🔴 WHY THIS EXISTS AT ALL. `user_module_access` treats ABSENCE OF A ROW as
// "not granted", which is the safe direction for a permission and the reason a
// brand-new user starts with nothing (the founder's decision, 2026-10-22). The
// cost of that default is this function: on the day the middleware is
// attached, every user who has been working happily for weeks has no rows, and
// without a backfill they would all be locked out at once.
//
// IDEMPOTENT, and that is deliberate rather than incidental. It counts the
// rows that already exist for each (user, module) and writes only what is
// missing, so it is safe to run twice, safe to run after adding a user, and
// safe to resume if it is interrupted half way. That is also why it is NOT
// wrapped in one big transaction: a partial run leaves correct rows behind and
// finishing is just running it again.
//
// 🔴 VERIFY IT BY COUNTING ROWS, NEVER BY TRUSTING `written` BELOW. The OBS-1
// heartbeat ran every five minutes for eight hours writing nothing at all and
// reported success each time; it was caught only by comparing the table's row
// count against what should have been there. The story's gate is a count
// query, and that is the whole reason `scanned` and `already_there` are
// returned alongside `written` — three numbers that have to add up.
//
// TWO PASSES, and the shape is not optional (CLAUDE.md, PLN-6): a conditional
// inside a foreach whose CONDITION reads a variable set earlier in the SAME
// iteration silently discards everything the branch writes, with no error and
// a plausible-looking result. So pass 1 records each lookup as a FIELD ON THE
// LOOP ITEM, and pass 2 branches on that field. Nested foreach and a
// db.query-per-iteration are both confirmed working (LOG-1).
//
// Runs for one account at a time. There is no "all accounts" mode on purpose —
// a cross-account write loop is exactly the kind of thing that should be
// driven deliberately, one account at a time, with the counts checked between.
function "usr/backfill_module_access" {
  input {
    int account_id filters=min:1

    // Who to credit the grants to in the audit trail. Pass the admin running
    // the backfill; 0 would read as "the system did it", which is true but
    // less useful six months later.
    int actor_user_id filters=min:1
  }

  stack {
    function.run "usr/module_keys" {
      input = {}
    } as $keys

    // No `paging`: with it the result stops being a plain array and both
    // `foreach` and indexing fail (CLAUDE.md).
    db.query user {
      where = $db.user.account_id == $input.account_id
      return = {type: "list"}
      output = ["id"]
    } as $users

    var $plan {
      value = []
    }

    // ── Pass 1: resolve. No branching on anything computed in here. ─────────
    foreach ($users) {
      each as $u {
        foreach ($keys.keys) {
          each as $k {
            db.query user_module_access {
              where = $db.user_module_access.user_id == $u.id && $db.user_module_access.module == $k
              return = {type: "count"}
            } as $already

            array.push $plan {
              value = {
                user_id : $u.id
                module  : $k
                existing: $already
              }
            }
          }
        }
      }
    }

    var $written {
      value = 0
    }

    var $already_there {
      value = 0
    }

    // ── Pass 2: write. The condition reads a FIELD OF THE LOOP ITEM. ────────
    foreach ($plan) {
      each as $p {
        conditional {
          if ($p.existing == 0) {
            db.add user_module_access {
              data = {
                created_at        : "now"
                updated_at        : "now"
                user_id           : $p.user_id
                account_id        : $input.account_id
                module            : $p.module
                granted           : true
                granted_by_user_id: $input.actor_user_id
                granted_at        : "now"
              }
            } as $_added

            var.update $written {
              value = $written + 1
            }
          }

          else {
            var.update $already_there {
              value = $already_there + 1
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "USR-2"
        step       : "backfill_module_access"
        outcome    : "success"
        severity   : "info"
        message    : "Backfilled module access for an account."
        user_id    : $input.actor_user_id
        account_id : $input.account_id
        entity_type: "account"
        entity_id  : $input.account_id
        metadata   : {written: $written, already_there: $already_there}
      }
    } as $_logged
  }

  // Three numbers that have to add up: `scanned` must equal users × modules,
  // and `written` + `already_there` must equal `scanned`. If they don't, the
  // loop did not do what it says.
  response = {
    account_id   : $input.account_id
    users        : ($users|count)
    scanned      : ($plan|count)
    written      : $written
    already_there: $already_there
  }
}
