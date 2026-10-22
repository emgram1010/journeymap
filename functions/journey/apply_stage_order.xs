// ORD-1 (US-ORD-1-02) — Put a map's stages in the order given, as 1..n.
//
// THE ONE PLACE stage display_order IS REWRITTEN. The reorder endpoint,
// insert-at-position on journey_stage/add, and (story 06) the AI tool all
// call this, so there is exactly one definition of "the columns are in
// order" and exactly one check that the order is legitimate. Modelled on
// functions/planner/resequence.xs + endpoint 544 (PLN-7).
//
// THE ORDER MUST BE AN EXACT PERMUTATION of the map's current stages —
// every one, each once, nothing else — or NOTHING is written and the call
// is refused with E-ORD-001. A partial reorder is worse than a refused
// one: the caller would believe it worked while a column silently lost
// its place or two columns shared one.
//
// The check is two counts, no loops, no array filters (|contains: is
// false for every array — CLAUDE.md):
//   a) submitted count == the map's stage count, and
//   b) WHERE journey_map = X AND id IN (submitted) == that same count.
// A missing or extra id fails (a). A duplicate fails (b): [A,A,B] counts
// 3 but matches 2 rows. An id from another map fails (b), which is also
// what stops a stage being reordered into this map from elsewhere.
//
// Only display_order changes. `key` is identity and is never touched
// (story 01). Gapped input is fine — whatever the old values were, the
// result is 1..n. Each row is patched by its own id inside one
// transaction (db.patch by a non-unique field touches only the first
// match — CLAUDE.md). The unique index on (journey_map, key,
// display_order) cannot trip mid-swap, because every key in a map is
// different.
//
// Ownership is the CALLER's job (journey/assert_map_owner) — this
// function trusts the map id it is given.
function "journey/apply_stage_order" {
  input {
    int journey_map_id filters=min:1
    json stage_ids
    int user_id?
    int account_id?
    text step? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "count"}
    } as $current_count

    var $submitted_count {
      value = $input.stage_ids|count
    }

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.id in $input.stage_ids
      return = {type: "count"}
    } as $matched_count

    var $log_step {
      value = "apply_stage_order"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    var $is_exact {
      value = ($submitted_count == $current_count) && ($matched_count == $current_count)
    }

    conditional {
      if ($is_exact == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "ORD-1"
            step          : $log_step
            outcome       : "rejected"
            severity      : "info"
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "journey_map"
            entity_id     : $input.journey_map_id
            correlation_id: $input.correlation_id
            error_code    : "E-ORD-001"
            message       : "Column order refused: it was not every current column exactly once."
          }
        } as $_logged
      }
    }

    precondition ($is_exact) {
      error_type = "inputerror"
      error = "That column order doesn't match this map's columns, so nothing was changed. Refresh and try again. (E-ORD-001)"
    }

    var $n {
      value = 0
    }

    var $order {
      value = []
    }

    db.transaction {
      stack {
        foreach ($input.stage_ids) {
          each as $sid {
            var.update $n {
              value = $n + 1
            }

            db.patch journey_stage {
              field_name = "id"
              field_value = $sid
              data = {display_order: $n, updated_at: "now"}
            } as $patched

            array.push $order {
              value = {id: $sid, key: $patched.key, display_order: $n}
            }
          }
        }
      }
    }
  }

  response = {count: $n, order: $order}
}
