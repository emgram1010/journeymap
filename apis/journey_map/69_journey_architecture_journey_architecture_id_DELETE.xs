// Delete a Journey Architecture and every map inside it.
//
// US-DEL-1-01 (2026-10-18) — CHECKED BEFORE ANYTHING IS DELETED.
// Deleting an architecture deletes every map inside it, so it is a
// bulk version of the same risk: one of those maps could be the one a
// plan is running from. Every map is tested with the SAME function the
// single-map delete uses (`journey/assert_map_unused`) BEFORE the
// cascade starts, and the whole delete is refused if any one of them
// is in use — naming the map and what depends on it. Refusing the
// whole thing rather than skipping that map is deliberate: a
// half-deleted architecture, missing some maps but not others, is a
// worse state than either outcome.
//
// US-DEL-1-03 — EACH MAP GOES THROUGH `journey/delete_map_cascade`,
// the same function the single-map delete calls. This endpoint used
// to carry its own inline cascade, which was nearly right but missed
// the STAGE-1 side tables (`journey_stage_owner`,
// `journey_lens_planned_work`), automation rows, and links owned by
// another architecture. Two implementations of one rule is the
// duplication that eventually disagrees; now a map removed on its own
// and a map removed with its architecture leave the database in the
// same state.
//
// US-DEL-1-02 — `journey_map_version` is NOT deleted, by design.
// Jobs read their instructions from those frozen snapshots, so they
// survive their map being removed. Deleting one would silently strip
// the steps from live work. Guarded by a test (`historyTables.ts`).
query "journey_architecture/{journey_architecture_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $existing

    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }

    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }

    // Load the maps first — they are needed for the check AND the cascade.
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $maps

    // Pass 1: ask about every map, recording each answer as a field.
    // No branching on a var set in the same iteration (CLAUDE.md).
    var $usage_checks {
      value = []
    }

    foreach ($maps) {
      each as $m {
        function.run "journey/assert_map_unused" {
          input = {journey_map_id: $m.id}
        } as $u

        array.push $usage_checks {
          value = {map_id: $m.id, title: $m.title, usage: $u}
        }
      }
    }

    // Pass 2: branch on the loop item's own field.
    var $blocked_map_title {
      value = ""
    }

    var $blocked_by {
      value = ""
    }

    var $blocked_reason {
      value = ""
    }

    foreach ($usage_checks) {
      each as $c {
        conditional {
          if ($c.usage.ok == false && $blocked_reason == "") {
            var.update $blocked_map_title {
              value = ($c.title ?? "a map")
            }

            var.update $blocked_by {
              value = $c.usage.blocker_name
            }

            var.update $blocked_reason {
              value = $c.usage.reason
            }
          }
        }
      }
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($blocked_reason == "in_use_by_plan") {
        var.update $reject_msg {
          value = "The map '" ~ $blocked_map_title ~ "' is used by the plan '" ~ $blocked_by ~ "'. Remove it there first. (E-DEL-001)"
        }
      }
    }

    conditional {
      if ($blocked_reason == "in_use_by_template") {
        var.update $reject_msg {
          value = "The map '" ~ $blocked_map_title ~ "' is used by the template '" ~ $blocked_by ~ "'. Remove it there first. (E-DEL-001)"
        }
      }
    }

    conditional {
      if ($blocked_reason == "has_jobs") {
        var.update $reject_msg {
          value = "Work has been done from the map '" ~ $blocked_map_title ~ "', so this architecture can't be deleted. (E-DEL-001)"
        }
      }
    }

    conditional {
      if ($blocked_reason != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "DEL-1"
            step          : "delete_architecture"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $auth.id
            account_id    : ($existing.account_id ?? 0)
            entity_type   : "journey_architecture"
            entity_id     : $input.journey_architecture_id
            correlation_id: $input.correlation_id
            error_code    : "E-DEL-001"
            message       : "Architecture delete refused — one of its maps is in use."
            metadata      : {blocked_map: $blocked_map_title, blocked_by: $blocked_by, reason: $blocked_reason}
          }
        }
      }
    }

    precondition ($blocked_reason == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Links that belong to the architecture itself (rather than to one
    // of its maps, which the per-map cascade handles).
    db.query journey_link {
      where = $db.journey_link.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $arch_links

    foreach ($arch_links) {
      each as $link {
        db.del journey_link {
          field_name = "id"
          field_value = $link.id
        }
      }
    }

    var $cells_removed {
      value = 0
    }

    foreach ($maps) {
      each as $map {
        function.run "journey/delete_map_cascade" {
          input = {journey_map_id: $map.id}
        } as $r

        var.update $cells_removed {
          value = $cells_removed + $r.cells_deleted
        }
      }
    }

    db.query automation_connection {
      where = $db.automation_connection.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $connections

    foreach ($connections) {
      each as $conn {
        db.del automation_connection {
          field_name = "id"
          field_value = $conn.id
        }
      }
    }

    // Delete the architecture
    db.del journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    }

    function.run "ops/log_event" {
      input = {
        feature       : "DEL-1"
        step          : "delete_architecture"
        outcome       : "success"
        severity      : "info"
        user_id       : $auth.id
        account_id    : ($existing.account_id ?? 0)
        entity_type   : "journey_architecture"
        entity_id     : $input.journey_architecture_id
        correlation_id: $input.correlation_id
        message       : "Architecture deleted with its maps."
        metadata      : {
          map_count       : ($maps|count)
          arch_link_count : ($arch_links|count)
          cells_removed   : $cells_removed
          connections     : ($connections|count)
        }
      }
    }
  }

  response = {
    deleted      : true
    id           : $input.journey_architecture_id
    maps_deleted : ($maps|count)
    cells_deleted: $cells_removed
  }
}
