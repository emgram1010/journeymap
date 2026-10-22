// US-SEC-1-04 (2026-10-18) — "Which journey maps may this caller see?"
//
// THE ONE PLACE THIS IS DECIDED. Five endpoints in this group are
// global lists with no map filter (journey_stage, journey_lens,
// journey_cell, journey_stage_owner, journey_lens_planned_work): the
// frontend pulls the whole table and filters client-side. Before
// SEC-1 that handed account A every row belonging to account B, and
// adding a login requirement alone would not have changed that. Each
// of those five now narrows its own query with this list, so the
// rule is written once instead of five times.
//
// THE LIST ALWAYS CONTAINS -1, AND THAT IS DELIBERATE. No row can
// reference map -1, so a caller who owns nothing gets a list that
// matches nothing — without a `conditional`, whose writes are not
// reliably visible outside the branch (CLAUDE.md). It also means an
// ORPHAN row, one whose journey_map was deleted outright, belongs to
// no account and comes back for nobody. That is what US-SEC-1-04 asks
// for, and it is why the guard is a sentinel rather than an empty
// array: `where ... in []` is untested on this instance.
//
// SOFT-DELETED MAPS ARE EXCLUDED, matching `GET /journey_map`
// (endpoint 18, US-DEL-1-07), which reads the same
// `journey/deleted_map_ids` lookup. Without this the founder's own
// app would keep receiving the stages, lenses and cells of the four
// maps soft-deleted in the Epic-6 purge: hidden from the map list,
// still arriving in every structure list. Measured — 16 visible maps
// became 12, and the four removed are exactly 179, 194, 196, 204.
//
// THE EXCLUSION MUST BE WRITTEN `not in`, NOT `!(... in ...)`.
// Confirmed live on a scratch function, twice: `!($db.t.id in $arr)`
// pushes cleanly and then fails at RUNTIME with no usable error, which
// took down all three map-keyed list endpoints until it was reverted.
// `$db.t.id not in $arr` works and compiles to SQL. A new entry for
// CLAUDE.md's filter list.
//
// The deleted list is seeded with -1 so it is never empty; an account
// with no soft-deleted maps is then unaffected (proved: a list of just
// [-1] excludes nothing, 16 of 16 kept).
//
// account_id 0 means "no account", which can never own anything —
// the same rule guards/assert_owns states. It is kept in the where
// clause rather than assumed, because an account-less login reaching
// here must see nothing, not everything with account_id 0.
//
// KNOWN, MEASURED DIVERGENCE FROM ENDPOINT 18: that endpoint's filter
// is a UNION — this account's maps PLUS anything this user owns — so a
// map with `account_id` 0 stays visible to its owner there and would
// not be here. Live count of such maps today: ZERO (all 24 have a
// non-zero account_id). Recorded in EPIC-SEC-1 rather than coded
// around, because matching it means threading a user id through five
// endpoints to change nothing.
function "journey/visible_map_ids" {
  input {
    int caller_account_id {
      description = "account_id of the authenticated caller. Endpoints pass $actor.account_id."
    }
  }

  stack {
    function.run "journey/deleted_map_ids" as $deleted

    var $deleted_ids {
      value = $deleted.ids
    }

    array.push $deleted_ids {
      value = -1
      description = "Never empty, so `not in` always has something to compare against."
    }

    db.query journey_map {
      where = ($input.caller_account_id != 0) && ($db.journey_map.account_id == $input.caller_account_id) && ($db.journey_map.id not in $deleted_ids)
      return = {type: "list"}
    } as $maps

    var $map_ids {
      value = [-1]
      description = "Sentinel first: no row references map -1, so the list is never empty."
    }

    foreach ($maps) {
      each as $m {
        array.push $map_ids {
          value = $m.id
        }
      }
    }
  }

  response = {map_ids: $map_ids, count: ($maps|count), soft_deleted_excluded: $deleted.count}
}
