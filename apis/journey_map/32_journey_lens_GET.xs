// Query the journey_lens records the signed-in caller owns.
//
// US-SEC-1-04 (2026-10-18) — THIS WAS OPEN TO THE INTERNET, the same
// way GET /journey_stage was: no login, every lens of every map. Worse
// than the stage list, because a lens row carries the actor's persona,
// role prompt and cost rate.
//
// A login requirement alone would NOT have fixed it: the frontend
// pulls the whole table and filters client-side (xano.ts), so account
// A still received account B's rows. 110 of the 198 live lenses belong
// to the founder's account.
//
// `journey/visible_map_ids` owns the "which maps may this caller see"
// rule for all five global lists in this group. Orphan lenses — ones
// whose journey_map was deleted — now come back for nobody.
query journey_lens verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
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

    db.query journey_lens {
      where = $db.journey_lens.journey_map in $map_ids
      return = {type: "list"}
    } as $model
  }

  response = $model
}
