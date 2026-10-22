// Query the journey_stage records the signed-in caller owns.
//
// US-SEC-1-04 (2026-10-18) — THIS WAS OPEN TO THE INTERNET. It needed
// no login and returned every stage of every map in the workspace; one
// unauthenticated GET printed other accounts' stage goals verbatim.
//
// A login requirement alone would NOT have fixed it. The frontend
// pulls this whole table and filters client-side
// (xano.ts: listJourneyStagesForMap), so without server-side scoping a
// signed-in account A still received account B's rows. 116 of the 200
// live stages belong to the founder's account; the other 84 were being
// handed over with them.
//
// `journey/visible_map_ids` owns the "which maps may this caller see"
// rule for all five global lists in this group. Orphan stages — ones
// whose journey_map was deleted — match no visible map, so they now
// come back for nobody, which is what US-SEC-1-04 asks for.
//
// `planner/resolve_actor` turns $auth.id into an account id. The
// `planner/` prefix is historical: the function is generic (user →
// account + role) and reusing it beats a fourth copy of the same
// db.get + precondition block (CLAUDE.md: reuse, do not duplicate).
query journey_stage verb=GET {
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

    db.query journey_stage {
      where = $db.journey_stage.journey_map in $map_ids
      return = {type: "list"}
    } as $model
  }

  response = $model
}
