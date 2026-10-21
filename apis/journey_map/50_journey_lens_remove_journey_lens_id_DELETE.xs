// Remove a journey lens and all of its cells while preserving minimum matrix structure.
//
// ORD-2 (US-ORD-2-04): the work lives in journey/remove_lens, which the AI
// tools call too. The survivors are renumbered, any stage that named this row
// as its accountable actor has that reference cleared, and a row whose key is
// pinned by a task in a published plan is refused with E-ORD-005.
//
// ISSUES-BACKLOG #16 (2026-10-21): THIS ENDPOINT HAD NO OWNERSHIP CHECK AT
// ALL -- see journey_stage/remove for the full note. Any authenticated user of
// any account could delete a row, and its cells, from any map in the
// workspace. Fixed here, account-scoped, matching the reorder endpoints.
query "journey_lens/remove/{journey_lens_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_lens_id? filters=min:1
  }

  stack {
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $target

    precondition ($target != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $target.journey_map
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "remove_lens"
      }
    } as $guard

    function.run "journey/remove_lens" {
      input = {
        journey_lens_id: $input.journey_lens_id
        user_id        : $auth.id
        account_id     : $actor.account_id
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
