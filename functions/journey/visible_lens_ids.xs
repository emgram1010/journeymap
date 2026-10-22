// US-SEC-1-04 (2026-10-18) — "Which lens rows may this caller see?"
//
// The lens twin of `journey/visible_stage_ids`, and it exists for the
// same reason: `journey_lens_planned_work` is a SIDE TABLE keyed on
// `journey_lens`, not on `journey_map` (STAGE-1 built it that way
// because adding a column to journey_lens drops every other field's
// validators — CLAUDE.md). Its list endpoint therefore cannot be
// scoped by map id directly and needs the caller's lens ids.
//
// Two queries, not a join: `journey/visible_map_ids` already owns the
// "which maps" rule, and repeating it inside a join condition here
// would be the duplication that rule exists to prevent.
//
// Same -1 sentinel as visible_map_ids, for the same reason: the list
// is never empty, so a caller who owns nothing matches nothing.
function "journey/visible_lens_ids" {
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

    db.query journey_lens {
      where = $db.journey_lens.journey_map in $map_ids
      return = {type: "list"}
    } as $rows

    var $lens_ids {
      value = [-1]
    }

    foreach ($rows) {
      each as $r {
        array.push $lens_ids {
          value = $r.id
        }
      }
    }
  }

  response = {lens_ids: $lens_ids, count: ($rows|count)}
}
