// USR-2 (US-USR-2-04) — the Execution gate.
//
// 🔴 NOT YET ATTACHED ANYWHERE, AND NOT AT GROUP LEVEL WHEN IT IS.
// Execution shares the `planner` API group with the Planner, so a
// group-level attachment would gate both with one answer — and "a performer
// can be given Execution without being given the Planner" is the whole point
// of story 04. See the Planner middleware's header; the two are decided
// together.
//
// 🔴 `exception_policy = "critical"` IS THE WHOLE FEATURE. The default is
// `"silent"`, and with it a thrown `accessdenied` is SWALLOWED and the request
// proceeds normally — the probe on 2026-10-21 returned HTTP 200 and the
// endpoint's real body from a middleware whose first statement was
// `precondition (false)`. Worse, the field is not validated: `"abort"` and a
// deliberate nonsense string were both stored as `"silent"` with no error.
// Only `"critical"` stuck.
//
// So: after every push, READ THE STORED DEFINITION BACK and confirm the value
// survived. A permission middleware without it permits everything, and nothing
// anywhere tells you.
//
// 🟡 THE ONE UNPROVEN LINE IS THE DECLARATION ITSELF. The probe established
// that middleware works on this plan, that `$auth` resolves inside it, that it
// returns a real 403 with the endpoint never running, and the group-level
// attach shape (`middleware = {pre: [{name: "..."}]}`). Xano's documentation
// tool has no middleware section at all, so the header below follows the
// `function` shape. Confirm it with `getMiddleware` on the first push and
// correct this file to match live before attaching anything.
//
// IT HOLDS NO RULE OF ITS OWN, deliberately. All three middlewares are this
// file with one word changed, and the rule they share lives in
// `usr/assert_module_access`. Three copies of a permission rule is three
// chances for them to disagree while all sounding equally certain (LOG-1).
//
// 🔴 NEVER ATTACH THIS TO THE AUTHENTICATION GROUP. A middleware that needs
// `$auth` on the very endpoints that create `$auth` is a lockout with its key
// inside.
//
// ✅ SHAPE PROVEN LIVE 2026-11-14 on two scratch API groups (group-level AND
// per-endpoint attachment), with real tokens over real HTTP:
//   no grant -> 403 E-USR-006 · granted -> 200 · switched off -> 403 E-USR-005
// Two corrections to the first draft of this file, both found by that test:
//   1. The stored declaration is `middleware name { input { json vars; enum
//      type } stack {...} response = null  response_strategy = "merge"
//      exception_policy = "critical" }` — unquoted name, policy at the END.
//   2. 🔴 `$auth|get:"id":0` is REWRITTEN on save to `$auth[""]|get:"id":0`,
//      which fails every request with a 500 "Unable to locate auth". Attached
//      to a real group that would have taken the whole module down for
//      everyone. `$auth.id ?? 0` is what works.
// Cost measured: about 33 ms added per request (199 -> 232 ms median).
middleware usr_require_module_execution {
  input {
    json vars
    enum type {
      values = ["pre", "post"]
    }
  }

  stack {
    var $caller_id {
      value = $auth.id ?? 0
    }

    conditional {
      if ($caller_id != 0) {
        function.run "usr/assert_module_access" {
          input = {
            actor_user_id: $caller_id
            module       : "execution"
            step         : "middleware/execution"
          }
        } as $_allowed
      }
    }
  }

  response = null
  response_strategy = "merge"
  exception_policy = "critical"
}
