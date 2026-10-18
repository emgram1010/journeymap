// Delete a Journey Architecture and all child records (authenticated, owner-scoped).
// Cascade order:
//   agent_message → agent_conversation → journey_cell → journey_lens → journey_stage → journey_map → journey_architecture
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
// US-DEL-1-02 — `journey_map_version` is NOT deleted here, by design.
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

    // Delete all journey_link records for this architecture first (avoids orphans)
    db.query journey_link {
      where = $db.journey_link.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $links

    foreach ($links) {
      each as $link {
        db.del journey_link {
          field_name = "id"
          field_value = $link.id
        }
      }
    }

    // Cascade delete each map and its children
    foreach ($maps) {
      each as $map {
        // Links pointing at this map from ANYWHERE, not only from this
        // architecture — a cell on another architecture's map can link
        // here, and that link would otherwise dangle.
        db.query journey_link {
          where = $db.journey_link.source_map == $map.id || $db.journey_link.target_map == $map.id
          return = {type: "list"}
        } as $map_links

        foreach ($map_links) {
          each as $ml {
            db.del journey_link {
              field_name = "id"
              field_value = $ml.id
            }
          }
        }

        // Delete agent messages via conversations for this map
        db.query agent_conversation {
          where = $db.agent_conversation.journey_map == $map.id
          return = {type: "list"}
        } as $conversations

        foreach ($conversations) {
          each as $conv {
            db.query agent_message {
              where = $db.agent_message.conversation == $conv.id
              return = {type: "list"}
            } as $messages

            foreach ($messages) {
              each as $msg {
                db.del agent_message {
                  field_name = "id"
                  field_value = $msg.id
                }
              }
            }

            db.del agent_conversation {
              field_name = "id"
              field_value = $conv.id
            }
          }
        }

        // Delete cells
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $map.id
          return = {type: "list"}
        } as $cells

        foreach ($cells) {
          each as $cell {
            db.del journey_cell {
              field_name = "id"
              field_value = $cell.id
            }
          }
        }

        // Delete lenses
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $map.id
          return = {type: "list"}
        } as $lenses

        foreach ($lenses) {
          each as $lens {
            db.del journey_lens {
              field_name = "id"
              field_value = $lens.id
            }
          }
        }

        // Delete stages
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $map.id
          return = {type: "list"}
        } as $stages

        foreach ($stages) {
          each as $stage {
            db.del journey_stage {
              field_name = "id"
              field_value = $stage.id
            }
          }
        }

        // Delete the journey map itself
        db.del journey_map {
          field_name = "id"
          field_value = $map.id
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
        metadata      : {map_count: ($maps|count), link_count: ($links|count)}
      }
    }
  }

  response = {deleted: true, id: $input.journey_architecture_id}
}
