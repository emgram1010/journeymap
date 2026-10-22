// Query journey_cell records for one journey map, scoped to the
// signed-in caller.
//
// US-RES-4-05 made the `journey_map` filter effectively required, to
// stop an unbounded full-table read. That is unchanged.
//
// WHAT A CALL WITH NO FILTER ACTUALLY DOES, measured rather than
// assumed: it returns 400, not an empty list. The input is declared
// optional but carries `min:1` and defaults to 0, so Xano's own
// validation rejects it before the stack runs. That matters because
// the frontend's CRUD-fallback `listJourneyCells()` sends no filter
// (xano.ts) — it has therefore been throwing, not returning [], since
// RES-4. Pre-existing, recorded in EPIC-SEC-1 rather than changed
// here: SEC-1 is not the place to alter what this endpoint returns.
//
// US-SEC-1-04 (2026-10-18) — WHAT CHANGED. The endpoint needed no
// login, and the map id came from the caller, so anyone on the
// internet could read any map's cells by guessing an id. Cell content
// is the actual work: the prompts, the costs, the durations.
//
// It is now signed-in only, AND the requested map must be one the
// caller owns. Both conditions sit in the one where clause, so a
// foreign map id returns an empty list rather than a refusal — that
// matches the other four global lists in this group and it does not
// confirm whether the map exists.
//
// `journey/visible_map_ids` owns the "which maps may this caller see"
// rule for all five.
query journey_cell verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map? filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/visible_map_ids" {
      input = {caller_account_id: $actor.account_id}
    } as $scope

    var $map_ids {
      value = $scope.map_ids
      description = "Hoisted — a where clause takes a plain variable, not a dotted path (CLAUDE.md)."
    }

    db.query journey_cell {
      where = ($db.journey_cell.journey_map == $input.journey_map) && ($db.journey_cell.journey_map in $map_ids)
      return = {type: "list"}
    } as $model
  }

  response = $model
}
