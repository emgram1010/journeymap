// AUTH-1 / STAGE-1 — list the does_planned_work overrides the
// signed-in caller owns, so the frontend can hydrate
// Lens.plannedWorkOverride and compute the effective value with the
// already-tested stageOwnerModel.doesPlannedWork(actorType, override).
//
// US-SEC-1-04 (2026-10-18) — was open to the internet with no login
// and no filter at all. Less sensitive than the lens table itself, but
// it is a map of which actors do planned work across every account,
// and it was free to read.
//
// SCOPED THROUGH THE LENS, NOT THE MAP. This is a side table keyed on
// `journey_lens` and it has no journey_map column (STAGE-1 built it
// that way because adding a column to journey_lens silently drops
// every other field's validators — CLAUDE.md). So the scope takes the
// extra hop: `journey/visible_lens_ids` resolves the caller's maps,
// then their lenses, and the query narrows to those.
//
// The frontend still matches rows to its own lenses by journey_lens
// id, so narrowing the list changes nothing it relies on.
query journey_lens_planned_work verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/visible_lens_ids" {
      input = {caller_account_id: $actor.account_id}
    } as $scope

    var $lens_ids {
      value = $scope.lens_ids
      description = "Hoisted — a where clause takes a plain variable, not a dotted path (CLAUDE.md)."
    }

    db.query journey_lens_planned_work {
      where = $db.journey_lens_planned_work.journey_lens in $lens_ids
      return = {type: "list"}
    } as $model
  }

  response = $model
}
