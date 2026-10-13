// STAGE-1 (US-STAGE-1-02/03/04) — Resolves a stage's primary_actor_lens
// text key to a lens in the SAME map. Pure lookup; never writes.
// Shared by the PATCH endpoint, the update_stage_contract tool, and the
// backfill function, so all three agree on what "resolved" means.
function "resolve_stage_owner" {
  description = "Resolves primary_actor_lens to a journey_lens id within one map. Empty/null key resolves to no owner (not an error). A key that matches no lens in the map is reported unresolved, never thrown."

  input {
    int journey_map_id filters=min:1
    text primary_actor_lens? filters=trim
  }

  stack {
    var $resolved {
      value = false
    }

    var $owner_lens_id {
      value = null
    }

    var $reason {
      value = null
    }

    conditional {
      if ($input.primary_actor_lens == null || $input.primary_actor_lens == "") {
        var.update $resolved {
          value = true
        }
      }

      else {
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.primary_actor_lens
          return = {type: "list"}
        } as $matches

        var $match_id {
          value = null
        }

        foreach ($matches) {
          each as $lens {
            var.update $match_id {
              value = $lens.id
            }
          }
        }

        conditional {
          if ($match_id != null) {
            var.update $resolved {
              value = true
            }

            var.update $owner_lens_id {
              value = $match_id
            }
          }

          else {
            var.update $reason {
              value = "no lens in this map matches key '" ~ $input.primary_actor_lens ~ "'"
            }
          }
        }
      }
    }
  }

  response = {resolved: $resolved, owner_lens_id: $owner_lens_id, reason: $reason}
}
