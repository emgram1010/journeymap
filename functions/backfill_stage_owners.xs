// STAGE-1 (US-STAGE-1-02) — Resolves primary_actor_lens to owner_lens_id
// for every stage (optionally limited to one map) and reports what
// would change. Writes only when dry_run is explicitly false.
// Idempotent: a second real run just re-resolves the same rows (upsert,
// not insert), so running it twice is safe.
//
// dry_run has no default and must always be passed explicitly — an
// omitted optional bool is not reliably distinguishable from false in
// this XanoScript version, so "dry-run by default" is a calling
// convention for whoever invokes this, not a schema default.
function "backfill_stage_owners" {
  description = "Resolves and (optionally) writes stage ownership from primary_actor_lens. Dry-run unless dry_run is passed as false."

  input {
    bool dry_run
    int journey_map_id? {
      description = "Limit to one map. Omitted or 0 = every map."
    }
  }

  stack {
    var $has_map_filter {
      value = ($input.journey_map_id != null && $input.journey_map_id != 0)
    }

    db.query journey_stage {
      where = ($has_map_filter == false) || ($db.journey_stage.journey_map == $input.journey_map_id)
      return = {type: "list"}
    } as $stages

    var $resolved_list {
      value = []
    }

    var $unresolved_list {
      value = []
    }

    foreach ($stages) {
      each as $stage {
        function.run "resolve_stage_owner" {
          input = {
            journey_map_id: $stage.journey_map
            primary_actor_lens: $stage.primary_actor_lens
          }
        } as $resolution

        conditional {
          if ($resolution.resolved == true && $resolution.owner_lens_id != null) {
            array.push $resolved_list {
              value = {stage_id: $stage.id, key: $stage.primary_actor_lens, owner_lens_id: $resolution.owner_lens_id}
            }

            conditional {
              if ($input.dry_run == false) {
                function.run "set_stage_owner" {
                  input = {
                    journey_stage_id: $stage.id
                    owner_lens_id: $resolution.owner_lens_id
                  }
                } as $write_result
              }
            }
          }

          elseif ($resolution.resolved == false) {
            array.push $unresolved_list {
              value = {stage_id: $stage.id, key: $stage.primary_actor_lens, reason: $resolution.reason}
            }
          }
        }
      }
    }
  }

  response = {
    dry_run         : $input.dry_run
    resolved_count  : $resolved_list|count
    unresolved_count: $unresolved_list|count
    resolved        : $resolved_list
    unresolved      : $unresolved_list
  }
}
