// Remove a journey lens and all of its cells while preserving minimum matrix structure.
//
// ORD-2 (US-ORD-2-04): the work moved to journey/remove_lens, which the AI
// tools call too. Three things changed in behaviour, all deliberate and all
// recorded in the epic: the survivors are renumbered so no gap is left, any
// stage that named this row as its accountable actor has that reference
// cleared instead of left dangling, and a row whose key is pinned by a task in
// a published plan is refused with E-ORD-005.
//
// This endpoint still has NO ownership check of its own — it never did.
// Tightening it is ISSUES-BACKLOG #7.
query "journey_lens/remove/{journey_lens_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_lens_id? filters=min:1
  }

  stack {
    function.run "journey/remove_lens" {
      input = {
        journey_lens_id: $input.journey_lens_id
        user_id        : $auth.id
        step           : "remove_lens"
      }
    } as $removed
  }

  response = {
    lens                  : $removed.lens
    deleted_cell_count    : $removed.deleted_cell_count
    journey_map_updated_at: $removed.journey_map_updated_at
  }
}
