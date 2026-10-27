// USR-2 (US-USR-2-03) — the Intelligent Layer gate, run before every endpoint
// in the `journey_map` API group.
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
middleware "usr_require_module_intelligence" {
  exception_policy = "critical"

  input {
  }

  stack {
    // An unauthenticated request must fall through untouched, so the
    // endpoint's own `auth` setting stays the thing that decides. Refusing
    // here would break any public endpoint that ever joins this group, and it
    // would answer "you don't have access" to somebody who is simply not
    // signed in — a worse sentence and a worse clue.
    //
    // `$auth|get:"id":0` rather than `$auth.id`, because a literal key honours
    // its default (CLAUDE.md) and there may be no `$auth` object at all.
    var $caller_id {
      value = $auth|get:"id":0
    }

    conditional {
      if ($caller_id != 0) {
        function.run "usr/assert_module_access" {
          input = {
            actor_user_id: $caller_id
            module       : "intelligence"
            step         : "middleware/intelligence"
          }
        } as $_allowed
      }
    }
  }
}
