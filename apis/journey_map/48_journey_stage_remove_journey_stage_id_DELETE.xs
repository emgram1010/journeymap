// Remove a journey stage and all of its cells while preserving minimum matrix structure.
//
// ORD-2 (US-ORD-2-04): the work moved to journey/remove_stage, which the AI
// tools call too. Two things changed in behaviour, both deliberate and both
// recorded in the epic: the survivors are now renumbered so no gap is left,
// and a column whose key is pinned by a task in a published plan is refused
// with E-ORD-005 instead of silently stranding that task.
//
// This endpoint still has NO ownership check of its own — it never did.
// Tightening it is ISSUES-BACKLOG #7 and is a behaviour change, not part of
// this refactor.
query "journey_stage/remove/{journey_stage_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_stage_id? filters=min:1
  }

  stack {
    function.run "journey/remove_stage" {
      input = {
        journey_stage_id: $input.journey_stage_id
        user_id         : $auth.id
        step            : "remove_stage"
      }
    } as $removed
  }

  response = {
    stage                 : $removed.stage
    deleted_cell_count    : $removed.deleted_cell_count
    journey_map_updated_at: $removed.journey_map_updated_at
  }
}
