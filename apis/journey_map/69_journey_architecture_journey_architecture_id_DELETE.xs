//  Delete a Journey Architecture. SOFT BY DEFAULT.
//
//  US-DEL-1-08 (2026-10-18) — `hard: true` is required to destroy
//  anything. Without it the architecture is marked deleted in
//  `journey_architecture_deleted`, every map inside it is marked in
//  `journey_map_deleted`, and all of it disappears from the lists.
//  `POST journey_architecture/{id}/restore` brings the whole thing
//  back untouched.
//
//  THIS IS THE MORE DESTRUCTIVE OF THE TWO DELETES — it takes every
//  map inside — so it is the one that most needed an undo, and had
//  none until now.
//
//  US-DEL-1-01 — CHECKED BEFORE ANYTHING HAPPENS, soft or hard. Every
//  map is tested with the same `journey/assert_map_unused` the
//  single-map delete uses, and the WHOLE delete is refused if any one
//  of them is in use, naming the map and what depends on it. Refusing
//  everything rather than skipping that map is deliberate: an
//  architecture missing some maps but not others is a worse state
//  than either outcome.
//
//  US-DEL-1-03 — a HARD delete puts each map through
//  `journey/delete_map_cascade`, the same function the single-map
//  delete calls, so a map removed alone and a map removed with its
//  architecture leave identical state.
//
//  US-DEL-1-02 — `journey_map_version` is never touched on either
//  path. Jobs read their instructions from those frozen snapshots.
//
//  COP-3 governance (2026-11-16) — the copilot's own business (the row
//  in `copilot_home`) is never deleted, soft or hard: E-COP-073, logged
//  as rejected. Checked right after the owner check, before any map is
//  looked at.
query "journey_architecture/{journey_architecture_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    bool hard?
    text reason? filters=trim
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

    // COP-3: the copilot's own business stays.
    db.query copilot_home {
      where = $db.copilot_home.journey_architecture_id == $input.journey_architecture_id
      return = {type: "count"}
    } as $home_count

    conditional {
      if ($home_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "COP-3"
            step          : "delete_architecture"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $auth.id
            account_id    : ($existing.account_id ?? 0)
            entity_type   : "journey_architecture"
            entity_id     : $input.journey_architecture_id
            correlation_id: $input.correlation_id
            error_code    : "E-COP-073"
            message       : "Delete refused: this is the copilot's own business."
            metadata      : {hard: ($input.hard == true)}
          }
        }
      }
    }

    precondition ($home_count == 0) {
      error_type = "inputerror"
      error = "This is the copilot's own business, where it keeps how it works. It can't be deleted. (E-COP-073)"
    }

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
            metadata      : {
            blocked_map: $blocked_map_title
            blocked_by : $blocked_by
            reason     : $blocked_reason
          }
          }
        }
      }
    }

    precondition ($blocked_reason == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $was_hard {
      value = ($input.hard == true)
    }

    var $cells_removed {
      value = 0
    }

    conditional {
      if ($was_hard) {
        // Links owned by the architecture itself; the per-map cascade
        // handles links belonging to its maps.
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

        // Clear any soft-delete markers so they don't point at rows
        // that no longer exist.
        db.query journey_architecture_deleted {
          where = $db.journey_architecture_deleted.journey_architecture_id == $input.journey_architecture_id
          return = {type: "list"}
        } as $arch_markers

        foreach ($arch_markers) {
          each as $am {
            db.del journey_architecture_deleted {
              field_name = "id"
              field_value = $am.id
            }
          }
        }

        db.del journey_architecture {
          field_name = "id"
          field_value = $input.journey_architecture_id
        }
      }

      else {
        // Soft: mark the architecture AND every map inside it, so the
        // maps vanish from the map list too rather than becoming
        // visible orphans of a hidden parent.
        db.get journey_architecture_deleted {
          field_name = "journey_architecture_id"
          field_value = $input.journey_architecture_id
        } as $existing_marker

        conditional {
          if ($existing_marker == null) {
            db.add journey_architecture_deleted {
              data = {
                journey_architecture_id: $input.journey_architecture_id
                deleted_by             : $auth.id
                reason                 : $input.reason
              }
            } as $arch_marker
          }
        }

        foreach ($maps) {
          each as $sm {
            db.get journey_map_deleted {
              field_name = "journey_map_id"
              field_value = $sm.id
            } as $map_marker

            conditional {
              if ($map_marker == null) {
                db.add journey_map_deleted {
                  data = {
                    journey_map_id: $sm.id
                    deleted_by    : $auth.id
                    reason        : $input.reason
                  }
                } as $added_marker
              }
            }
          }
        }
      }
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
        message       : "Architecture deleted."
        metadata      : {
        title        : $existing.title
        mode         : ($was_hard ? "hard" : "soft")
        map_count    : $maps|count
        cells_removed: $cells_removed
        reason       : $input.reason
      }
      }
    }
  }

  response = {
    deleted      : true
    id           : $input.journey_architecture_id
    mode         : ($was_hard ? "hard" : "soft")
    recoverable  : ($was_hard == false)
    maps_affected: $maps|count
    cells_deleted: $cells_removed
  }
}
