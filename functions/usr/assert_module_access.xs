// USR-2 (US-USR-2-03) — may this person enter this module?
//
// THE WHOLE RULE, IN ONE PLACE. Three middlewares call it with a different
// module key and nothing else; the Planner and Execution endpoints call it
// too, because they share one API group and a group-level attachment cannot
// tell them apart. Copying this into each of them is how an audit ends up
// disagreeing with the engine it audits (the LOG-1 lesson), and a permission
// rule is the worst possible thing to hold two opinions about.
//
// It answers THREE questions in the order that matters:
//   1. Is `module` a real module?            → E-USR-007
//   2. Is this person switched on?           → E-USR-005
//   3. Have they been granted this module?   → E-USR-006
//
// 🔴 Question 2 is here and not only in `auth/login` on purpose: it closes the
// gap USR-1 left open and documented. Deactivating somebody only blocked a NEW
// sign-in; anyone holding a token issued before they were switched off kept
// working until it expired. Checked on every request, that stops being true.
//
// 🔴 Every read below uses `db.query ... return = {type: "single"}` and then
// `|get` with a LITERAL key, not `db.get` plus a null test. Two reasons, both
// from CLAUDE.md: a single-result query that matches nothing yields a value
// `|get:"x":default` handles safely, and `== null` is PHP-loose here — `0`,
// `""`, `false` and `[]` all equal null — so a null test on a BOOL column
// cannot tell "revoked" from "never set". A literal key honours its default; a
// variable key silently discards it, which is why neither key here is a
// variable.
//
// It takes `actor_user_id` rather than reading `$auth.id` because a function
// has no `$auth` of its own — the same reason `planner/resolve_actor` does.
// That also makes it testable without a token.
//
// 🔴 `error_type = "inputerror"`, NOT `"input"`. The latter pushes without
// complaint and then fails at RUNTIME with "Param: error_type - Input 'input'
// is not one of the allowable values" — so the precondition never refuses the
// thing it was written to refuse; it throws an unrelated error instead. Caught
// on the very first smoke test of this function, 2026-10-23, and it was in two
// files. The valid values in use across this codebase are `notfound`,
// `inputerror`, `accessdenied`, `badrequest` and `unauthorized`.
function "usr/assert_module_access" {
  input {
    // The caller. A middleware passes `$auth.id`.
    int actor_user_id filters=min:1

    // One of `intelligence` | `planning` | `execution`.
    text module filters=trim

    // For the event log, so a refusal says which door was tried.
    text step? filters=trim
  }

  stack {
    function.run "usr/module_keys" {
      input = {
        check: $input.module
      }
    } as $keys

    // `input`, not `accessdenied`: an unknown key is a caller mistake, not a
    // permission problem, and saying so is more useful than a 403.
    precondition ($keys.valid == true) {
      error_type = "inputerror"
      error = "We don't recognise that module. (E-USR-007)"
    }

    db.query user {
      where = $db.user.id == $input.actor_user_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $actor_row

    var $actor_id {
      value = $actor_row|get:"id":0
    }

    precondition ($actor_id != 0) {
      error_type = "accessdenied"
      error = "We couldn't find your user record. (E-USR-010)"
    }

    var $account_id {
      value = $actor_row|get:"account_id":0
    }

    // ABSENCE OF A ROW MEANS ACTIVE, in `user_status` — the opposite default
    // to this epic's own table, and the reason USR-1 needed no backfill.
    db.query user_status {
      where = $db.user_status.user_id == $actor_id
      return = {type: "single"}
      output = ["id", "is_active"]
    } as $status_row

    var $is_active {
      value = $status_row|get:"is_active":true
    }

    precondition ($is_active == true) {
      error_type = "accessdenied"
      error = "This account has been switched off. Ask your admin to turn it back on. (E-USR-005)"
    }

    // ABSENCE OF A ROW MEANS NOT GRANTED. A missing row, a half-run backfill
    // and an explicit revoke all land here, and all three mean no.
    db.query user_module_access {
      where = $db.user_module_access.user_id == $actor_id && $db.user_module_access.module == $input.module
      return = {type: "single"}
      output = ["id", "granted"]
    } as $grant_row

    var $granted {
      value = $grant_row|get:"granted":false
    }

    // Refusals are logged; successful checks deliberately are NOT. This runs
    // on every request in a group, and logging the passes would make
    // `event_log` the largest table in the product inside a week.
    conditional {
      if ($granted != true) {
        function.run "ops/log_event" {
          input = {
            feature    : "USR-2"
            step       : $input.step
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-USR-006"
            message    : "Refused: this user has not been granted this module."
            user_id    : $actor_id
            account_id : $account_id
            entity_type: "module"
            entity_id  : 0
            metadata   : {module: $input.module}
          }
        } as $_denied
      }
    }

    precondition ($granted == true) {
      error_type = "accessdenied"
      error = "You don't have access to this part of the product. Ask your admin to turn it on. (E-USR-006)"
    }
  }

  response = {
    user_id   : $actor_id
    account_id: $account_id
    module    : $input.module
    granted   : true
  }
}
