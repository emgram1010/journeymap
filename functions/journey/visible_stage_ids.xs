// US-SEC-1-04 (2026-10-18) — "Which stage rows may this caller see?"
//
// `journey_stage_owner` is a SIDE TABLE: it holds one row per owned
// stage and references `journey_stage`, not `journey_map` (STAGE-1
// built it that way because adding a column to journey_stage drops
// every other field's validators — CLAUDE.md). So its list endpoint
// cannot be scoped by map id directly; it needs the caller's stage
// ids, which is the hop this function makes.
//
// Two queries, not a join: `journey/visible_map_ids` already owns the
// "which maps" rule, and repeating it inside a join condition here
// would be the duplication that rule exists to prevent.
//
// Same -1 sentinel as visible_map_ids, for the same reason: the list
// is never empty, so a caller who owns nothing matches nothing.
function "journey/visible_stage_ids" {
  input {
    int caller_account_id {
      description = "account_id of the authenticated caller. Endpoints pass $actor.account_id."
    }
  }

  stack {
    function.run "journey/visible_map_ids" {
      input = {caller_account_id: $input.caller_account_id}
    } as $scope

    var $map_ids {
      value = $scope.map_ids
      description = "Hoisted out of the where clause — a plain variable is the confirmed shape (CLAUDE.md)."
    }

    db.query journey_stage {
      where = $db.journey_stage.journey_map in $map_ids
      return = {type: "list"}
    } as $rows

    var $stage_ids {
      value = [-1]
    }

    foreach ($rows) {
      each as $r {
        array.push $stage_ids {
          value = $r.id
        }
      }
    }
  }

  response = {stage_ids: $stage_ids, count: ($rows|count)}
}
