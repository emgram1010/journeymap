// Remove a journey stage and all of its cells while preserving minimum matrix structure.
//
// ORD-2 (US-ORD-2-04): the work lives in journey/remove_stage, which the AI
// tools call too. The survivors are renumbered so no gap is left, and a column
// whose key is pinned by a task in a published plan is refused with E-ORD-005.
//
// ISSUES-BACKLOG #16 (2026-10-21): THIS ENDPOINT HAD NO OWNERSHIP CHECK AT
// ALL. It proved the stage existed and nothing else, so any authenticated user
// of any account could delete a column -- and its cells -- from any map in the
// workspace. Found by reading the live source during ORD-2 and deliberately
// left alone then, because changing behaviour inside a refactor is how a
// regression hides. Fixed here on its own.
//
// ACCOUNT-SCOPED, NOT OWNER-SCOPED, matching the reorder endpoints (581/582)
// and SEC-1's rule: a teammate in the same account may remove a column. That
// also closes the inconsistency in ISSUES-BACKLOG #7, where a teammate could
// already reorder a map they could not add to.
query "journey_stage/remove/{journey_stage_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_stage_id? filters=min:1
  }

  stack {
    // The row is read first because the guard takes a MAP id, and every
    // structure row belongs to exactly one map.
    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $target

    precondition ($target != null) {
      error_type = "notfound"
      error = "Journey stage not found"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $target.journey_map
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "remove_stage"
      }
    } as $guard

    function.run "journey/remove_stage" {
      input = {
        journey_stage_id: $input.journey_stage_id
        user_id         : $auth.id
        account_id      : $actor.account_id
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
