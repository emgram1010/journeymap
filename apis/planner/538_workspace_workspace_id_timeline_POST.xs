// PLN-6 (US-PLN-6-01) — Start a day's plan for one agent.
//
// 4-C: the rule now lives in ONE place, `planner_ops/create_timeline`,
// which the copilot's `plan_start_day` tool also calls. This endpoint only
// signs the caller in, works out who they are, reads which optional fields
// were actually sent, and hands everything to that function. Every input
// is passed explicitly (an input left out silently inherits this
// endpoint's value of the same name).
//
// What the function keeps exactly as this endpoint always did:
// - CREATING A TIMELINE THAT ALREADY EXISTS IS NOT AN ERROR: the existing
//   row comes back with `created: false`. The unique index on
//   (agent_id, planned_date) is what makes a duplicate impossible.
// - IT HOLDS UNDER A RACE: two simultaneous clicks both get `200` with the
//   same day, one `created: true` and one `created: false`, and exactly
//   one row exists (the losing insert is caught and the row re-read).
// - OUT-OF-WINDOW DATES ARE ALLOWED, flagged `out_of_window: true`.
// - `status` IS READ-ONLY: sending one (any value except null) is refused
//   with E-PLN-011.
// One change (4-C): an insert that failed for a reason OTHER than a
// duplicate used to answer success with `timeline: null`. It is now a
// logged failure and a refusal.
query "workspace/{workspace_id}/timeline" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int agent_id filters=min:1
    date planned_date
    text start_time? filters=trim
    text status? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    // "Was this field sent?" — only the raw body can tell. A field sent
    // as null counts as not sent (unchanged from before).
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = true
    } as $raw_input

    var $has_start_time {
      value = ($raw_input|has:"start_time")
    }

    var $has_status {
      value = ($raw_input|has:"status")
    }

    function.run "planner_ops/create_timeline" {
      input = {
        actor         : $actor
        workspace_id  : $input.workspace_id
        agent_id      : $input.agent_id
        planned_date  : $input.planned_date
        start_time    : $input.start_time
        has_start_time: $has_start_time
        has_status    : $has_status
        correlation_id: $input.correlation_id
      }
    } as $made
  }

  response = {
    timeline     : $made.timeline
    created      : $made.created
    out_of_window: $made.out_of_window
  }
}
