// Get one journey_cell record, if the signed-in caller owns its map.
//
// US-SEC-1-04 (2026-10-18) — needed no login, and the id came from the
// caller, so anyone could walk the id space and read every cell in the
// workspace one at a time. Cell content is the actual work: the
// durations, the costs, the prompts.
//
// The cell is read first and the guard runs on its map — a cell row
// carries `journey_map`, so this costs one extra db.get and keeps the
// ownership rule in `journey/assert_map_owner` rather than inline here.
// Refusals are logged as `rejected` with E-GOV-001 by the guard, so
// someone probing ids shows up on the Health page.
query "journey_cell/{journey_cell_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_cell_id? filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    } as $model

    precondition ($model != null) {
      error_type = "notfound"
      error = "Not Found"
    }

    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $model.journey_map
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "get_cell"
      }
    } as $guard
  }

  response = $model
}
