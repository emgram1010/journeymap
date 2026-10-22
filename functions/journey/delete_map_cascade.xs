// US-DEL-1-03 (2026-10-18) — Delete a map and everything that is
// only meaningful because that map exists.
//
// THE ONE IMPLEMENTATION. Both `DELETE journey_map` (api 22) and the
// architecture cascade (api 69) call this, so a map removed on its
// own and a map removed with its architecture leave the database in
// the same state. Before this, api 22 deleted the map row and nothing
// else: 583 orphaned cells, 78 lenses and 55 stages had built up that
// way, invisible to every query and waiting to confuse the first
// audit or migration that looked.
//
// 🔴 `journey_map_version` IS NOT IN THIS CASCADE AND MUST NEVER BE.
// A job reads its steps, done-whens and durations out of a version's
// frozen `snapshot`, never from the live map — which is the entire
// reason deleting a map cannot break work in flight. Removing a
// version here would silently strip the instructions from live and
// historical work. `historyTables.ts` fails the build on any
// `db.del journey_map_version` anywhere, including this file.
//
// WHY A CASCADE AND NOT A SOFT DELETE (founder's decision,
// 2026-10-18): US-DEL-1-01 ships first and refuses to delete a map
// any plan, template or job depends on. So the only maps that can
// ever reach this function are ones nothing references — exactly the
// case where destroying content is safe. The codebase's instinct to
// hold deletes is honoured by the REFUSAL, not by keeping debris.
//
// EVERY CHILD IS DELETED BY ITS OWN id, inside one transaction.
// `db.del` with a non-unique field only removes the FIRST match
// (CLAUDE.md), so a `where`-style delete would silently half-clear
// each table; and a cascade that fails partway through would leave a
// map with some of its content gone.
//
// Verified live: a scaffolded map with 8 stages, 1 lens and 8 cells
// deleted cleanly and the orphan count did not move.
function "journey/delete_map_cascade" {
  input {
    int journey_map_id filters=min:1
  }

  stack {
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $cells

    var $stage_ids {
      value = []
    }

    foreach ($stages) {
      each as $s {
        array.push $stage_ids {
          value = $s.id
        }
      }
    }

    var $lens_ids {
      value = []
    }

    foreach ($lenses) {
      each as $l {
        array.push $lens_ids {
          value = $l.id
        }
      }
    }

    // STAGE-1's side tables. They hang off a stage or a lens rather
    // than the map, so a map-shaped cleanup misses them entirely —
    // which is how they were missed before.
    var $owner_rows {
      value = []
    }

    conditional {
      if (($stage_ids|count) > 0) {
        db.query journey_stage_owner {
          where = $db.journey_stage_owner.journey_stage in $stage_ids
          return = {type: "list"}
        } as $owners

        var.update $owner_rows {
          value = $owners
        }
      }
    }

    var $planned_rows {
      value = []
    }

    conditional {
      if (($lens_ids|count) > 0) {
        db.query journey_lens_planned_work {
          where = $db.journey_lens_planned_work.journey_lens in $lens_ids
          return = {type: "list"}
        } as $planned

        var.update $planned_rows {
          value = $planned
        }
      }
    }

    // Links where this map is either end, wherever they came from.
    db.query journey_link {
      where = $db.journey_link.source_map == $input.journey_map_id || $db.journey_link.target_map == $input.journey_map_id
      return = {type: "list"}
    } as $links

    db.query agent_conversation {
      where = $db.agent_conversation.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $conversations

    var $conversation_ids {
      value = []
    }

    foreach ($conversations) {
      each as $c {
        array.push $conversation_ids {
          value = $c.id
        }
      }
    }

    var $message_rows {
      value = []
    }

    conditional {
      if (($conversation_ids|count) > 0) {
        db.query agent_message {
          where = $db.agent_message.conversation in $conversation_ids
          return = {type: "list"}
        } as $messages

        var.update $message_rows {
          value = $messages
        }
      }
    }

    db.query stage_automation_config {
      where = $db.stage_automation_config.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $automation_configs

    db.query automation_snapshot {
      where = $db.automation_snapshot.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $automation_snapshots

    // Other maps pointing AT this one. Left alone they become
    // dangling parent/clone pointers — a breadcrumb to nowhere.
    db.query journey_map {
      where = $db.journey_map.parent_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $children

    db.query journey_map {
      where = $db.journey_map.cloned_from_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $clones

    db.transaction {
      stack {
        foreach ($message_rows) {
          each as $m {
            db.del agent_message {
              field_name = "id"
              field_value = $m.id
            }
          }
        }

        foreach ($conversations) {
          each as $c2 {
            db.del agent_conversation {
              field_name = "id"
              field_value = $c2.id
            }
          }
        }

        foreach ($owner_rows) {
          each as $o {
            db.del journey_stage_owner {
              field_name = "id"
              field_value = $o.id
            }
          }
        }

        foreach ($planned_rows) {
          each as $pw {
            db.del journey_lens_planned_work {
              field_name = "id"
              field_value = $pw.id
            }
          }
        }

        foreach ($cells) {
          each as $cell {
            db.del journey_cell {
              field_name = "id"
              field_value = $cell.id
            }
          }
        }

        foreach ($lenses) {
          each as $lens {
            db.del journey_lens {
              field_name = "id"
              field_value = $lens.id
            }
          }
        }

        foreach ($stages) {
          each as $stage {
            db.del journey_stage {
              field_name = "id"
              field_value = $stage.id
            }
          }
        }

        foreach ($links) {
          each as $link {
            db.del journey_link {
              field_name = "id"
              field_value = $link.id
            }
          }
        }

        foreach ($automation_configs) {
          each as $ac {
            db.del stage_automation_config {
              field_name = "id"
              field_value = $ac.id
            }
          }
        }

        foreach ($automation_snapshots) {
          each as $as_row {
            db.del automation_snapshot {
              field_name = "id"
              field_value = $as_row.id
            }
          }
        }

        // Cleared, not deleted: these are other people's maps.
        foreach ($children) {
          each as $ch {
            db.patch journey_map {
              field_name = "id"
              field_value = $ch.id
              data = {parent_map_id: 0}
            } as $ch_patched
          }
        }

        foreach ($clones) {
          each as $cl {
            db.patch journey_map {
              field_name = "id"
              field_value = $cl.id
              data = {cloned_from_map_id: 0}
            } as $cl_patched
          }
        }

        db.del journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
        }
      }
    }
  }

  response = {
    journey_map_id        : $input.journey_map_id
    stages_deleted        : ($stages|count)
    lenses_deleted        : ($lenses|count)
    cells_deleted         : ($cells|count)
    stage_owners_deleted  : ($owner_rows|count)
    planned_work_deleted  : ($planned_rows|count)
    links_deleted         : ($links|count)
    conversations_deleted : ($conversations|count)
    messages_deleted      : ($message_rows|count)
    automation_deleted    : (($automation_configs|count) + ($automation_snapshots|count))
    pointers_cleared      : (($children|count) + ($clones|count))
  }
}
