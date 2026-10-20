// Edit a journey_lens record the signed-in caller owns.
//
// US-SEC-1-04 (2026-10-18) — THIS WAS AN OPEN WRITE. No login, no
// ownership check: anyone on the internet could rename any actor row
// in any account, rewrite its role prompt, or change its cost rate.
// The app uses it for the cost rate (xano.ts:1162).
//
// TWO OWNERSHIP CHECKS, NOT ONE, AND BOTH MATTER. This is a generic
// CRUD patch: its data block is built from whatever keys the body
// sent, which includes `journey_map`. So authenticating the caller and
// checking only the lens's CURRENT map would still let them move their
// own lens INTO someone else's map — vandalising a stranger's matrix
// through an endpoint that had just proved they owned the row. The
// caller must own where the lens is AND where it is going.
//
// When the body does not mention `journey_map` the target resolves to
// the lens's own map and the second check is the same check twice —
// one extra db.get, and no `conditional`, whose writes are not
// reliably visible outside the branch (CLAUDE.md). `|get` keeps its
// default here because the key is a literal; with a variable key the
// default is silently thrown away.
query "journey_lens/{journey_lens_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_lens_id? filters=min:1
    dblink {
      table = "journey_lens"
    }
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $existing

    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $existing.journey_map
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "patch_lens"
      }
    } as $guard_current

    var $target_map_id {
      value = $raw_input|get:"journey_map":$existing.journey_map
      description = "Where the body wants this lens to end up; its own map when the body is silent."
    }

    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $target_map_id
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "patch_lens_target_map"
      }
    } as $guard_target

    db.patch journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  }

  response = $model
}
