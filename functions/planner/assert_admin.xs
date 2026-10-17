// PLN-2 (US-PLN-2-03) — Role guard, for the two admin-only areas.
//
// Per PLN-2's access matrix, a member may create and change plans,
// agents, timelines and tasks freely. Only two things need admin:
// account rates (`planner_settings`) and the model catalogue. This is
// the only place that distinction is written down in code.
//
// `accessdenied` here, deliberately, NOT `notfound` — unlike the tenancy
// guards. The caller may see the thing; they just may not change it, so
// hiding its existence would only confuse them.
//
// Takes the role as a value, not a user id: the caller already has it
// from resolve_actor, and re-reading the user would be a second query
// for a fact already in hand.
function "planner/assert_admin" {
  input {
    text role? filters=trim
  }

  stack {
    // An omitted optional text input arrives as "" (CLAUDE.md), which is
    // not "admin" — so omitting the role fails closed. That is correct.
    precondition ($input.role == "admin") {
      error_type = "accessdenied"
      error = "Only account admins can change planner rates and models"
    }
  }

  response = {ok: true}
}
