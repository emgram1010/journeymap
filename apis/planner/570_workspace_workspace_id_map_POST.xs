//  PLN-9 (US-PLN-9-06, epic finding 5) — Add a map to an ALREADY-RUNNING
//  plan. `template/{id}` PATCH only changes what the NEXT instance will
//  accept (PLAN-1's whole point); a planner using the real UI to add a
//  second work type to a plan that's already underway had no endpoint
//  at all until this one — found live during E2E-1.
//
//  APPEND-ONLY AND IDEMPOTENT, same rule as the template's own
//  `add_map_ids`: a map already accepted is skipped, never rejected, so
//  this is safe to call twice with the same list. Removing a map means
//  deleting a `planner_workspace_map` row, and every delete here is
//  still awaiting the founder's approval (CLAUDE.md) — a
//  `remove_map_ids` input belongs here once deletes are allowed.
//
//  4-C (2026-11-16): the rule itself now lives ONCE, in
//  planner_ops/accept_maps (the copilot tool plan_accept_map calls the
//  same function). This endpoint only signs the caller in and hands
//  everything over. The function does the checks (plan, archived,
//  empty list, E-PLAN-004 not published, E-PLAN-015 not this account's
//  map), logs the one success or refusal event, and raises the refusal.
//  Every function input is passed explicitly: one left out would
//  silently inherit this endpoint's $input of the same name.
query "workspace/{workspace_id}/map" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    json map_ids
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner_ops/accept_maps" {
      input = {
        actor         : $actor
        workspace_id  : $input.workspace_id
        map_ids       : $input.map_ids
        correlation_id: $input.correlation_id
      }
    } as $accepted
  }

  response = {
    map_ids     : $accepted.map_ids
    added_count : $accepted.added_count
  }
}
