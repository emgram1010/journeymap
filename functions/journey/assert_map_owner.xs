// US-SEC-1-04 (2026-10-18) — "Does this caller own the map this row
// belongs to?" The guard every row-touching journey-map endpoint
// calls before it reads or writes.
//
// THE ONE PLACE OWNERSHIP IS PROVED for this group. Eight endpoints
// needed it (a lens PATCH, a cell GET, the actor-fields PATCH and the
// four conversation routes); writing the lookup eight times is how
// the eighth copy ends up subtly different from the first.
//
// It takes the MAP id, not the row id, because every structure row in
// this group — stage, lens, cell, conversation — belongs to exactly
// one journey_map, and `account_id` lives on the map. Callers that
// start from a child row read the child first and pass
// `$row.journey_map` in; that read is theirs to do, so this function
// stays one query no matter which table the caller came from.
//
// It does NOT duplicate guards/assert_owns — it delegates to it, so
// the refusal, its error code (E-GOV-001) and its logged `rejected`
// event stay in the one place GOV-1 put them.
//
// A missing map is `notfound`, not `accessdenied`: refusing to say
// whether a map exists is a privacy property worth having, but the
// four conversation endpoints already answer "Journey map not found"
// for a bad id and changing that is a behaviour change SEC-1 was not
// asked to make.
function "journey/assert_map_owner" {
  input {
    int journey_map_id filters=min:1
    int caller_account_id {
      description = "account_id of the authenticated caller. Endpoints pass $actor.account_id."
    }

    int user_id? {
      description = "The caller, for the logged event. Endpoints pass $auth.id."
    }

    text step? filters=trim {
      description = "What was being attempted, e.g. 'patch_lens'. Shows on the Health page."
    }
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    var $entity_account_id {
      value = ($journey_map.account_id ?? 0)
      description = "A map with no account can be owned by nobody — assert_owns refuses account 0."
    }

    function.run "guards/assert_owns" {
      input = {
        entity_account_id: $entity_account_id
        caller_account_id: $input.caller_account_id
        feature          : "SEC-1"
        step             : $input.step
        entity_type      : "journey_map"
        entity_id        : $input.journey_map_id
        user_id          : $input.user_id
      }
    } as $guard
  }

  response = {ok: true, journey_map: $journey_map, account_id: $entity_account_id}
}
