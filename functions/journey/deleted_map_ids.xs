// US-DEL-1-07 (2026-10-18) — Which of these maps are soft-deleted?
//
// THE ONE PLACE THE MARKER IS READ. Every list of maps has to exclude
// soft-deleted ones, and a side table is invisible to the plain map
// queries unless each is told about it — exactly the trap AUTH-1 hit,
// where `owner_lens_id` came back undefined forever because the list
// endpoint never joined `journey_stage_owner`. Putting the lookup in
// one function means a new map list can't forget.
//
// Returns a SET keyed by map id as text, pre-seeded, so callers test
// membership with `|get:$key:null` rather than `|contains:`, which is
// false for every array (CLAUDE.md).
function "journey/deleted_map_ids" {
  input {
  }

  stack {
    db.query journey_map_deleted {
      return = {type: "list"}
    } as $rows

    var $set {
      value = {}
    }

    var $ids {
      value = []
    }

    var $k {
      value = ""
    }

    foreach ($rows) {
      each as $r {
        var.update $k {
          value = $r.journey_map_id|to_text
        }

        var.update $set {
          value = $set|set:$k:1
        }

        array.push $ids {
          value = $r.journey_map_id
        }
      }
    }
  }

  response = {set: $set, ids: $ids, count: ($rows|count)}
}
