// AUTH-1 — list the stage ownership rows the signed-in caller owns,
// so the frontend can hydrate Stage.ownerLensId. journey_stage itself
// has no owner_lens_id column (see journey_stage_owner's table header,
// STAGE-1), so the plain GET /journey_stage list never had this field
// to return.
//
// US-SEC-1-04 (2026-10-18) — was open to the internet with no login
// and no filter at all: every stage-to-owner assignment in every
// account, free to read.
//
// SCOPED THROUGH THE STAGE, NOT THE MAP. This is a side table keyed on
// `journey_stage` with no journey_map column of its own (STAGE-1 built
// it that way because adding a column to journey_stage silently drops
// every other field's validators — CLAUDE.md). So the scope takes the
// extra hop: `journey/visible_stage_ids` resolves the caller's maps,
// then their stages, and the query narrows to those.
//
// The frontend still matches rows to its own stages by journey_stage
// id, so narrowing the list changes nothing it relies on.
query journey_stage_owner verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/visible_stage_ids" {
      input = {caller_account_id: $actor.account_id}
    } as $scope

    var $stage_ids {
      value = $scope.stage_ids
      description = "Hoisted — a where clause takes a plain variable, not a dotted path (CLAUDE.md)."
    }

    db.query journey_stage_owner {
      where = $db.journey_stage_owner.journey_stage in $stage_ids
      return = {type: "list"}
    } as $model
  }

  response = $model
}
