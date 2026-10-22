// THE ONE PLACE A COLUMN IS REMOVED FROM A MAP. Deletes the column and every
// cell in it, refuses if live work depends on its key, and renumbers what is
// left so no gap is left behind.
//
// ORD-2 US-ORD-2-03. Lifted out of endpoint 48 (journey_stage/remove) so the
// matrix and the AI tools run the same code. Before this, the AI's
// remove_stage called `api.call ""` — an empty path in an empty API group — so
// it reported success and deleted nothing.
//
// AUTHORISATION IS THE CALLER'S JOB. Note that endpoint 48 never had an
// ownership check of its own — it proves the stage exists and nothing else —
// so this function does not invent one either, because doing it here would
// change the endpoint's behaviour inside a refactor. Tightening that endpoint
// is ISSUES-BACKLOG #7 and belongs in its own change.
//
// THE CASCADE DELETES EACH CELL BY ITS OWN id, INSIDE A TRANSACTION. db.del
// with field_name/field_value removes only the FIRST match (CLAUDE.md), so a
// "delete where stage = X" cascade would orphan every cell after the first and
// report success.
function "journey/remove_stage" {
  input {
    int journey_stage_id filters=min:1

    // Logging only.
    int user_id?
    int account_id?
    text step? filters=trim
  }

  stack {
    var $log_step {
      value = "remove_stage"
    }

    conditional {
      if ($input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $journey_stage

    precondition ($journey_stage != null) {
      error_type = "notfound"
      error = "Journey stage not found"
    }

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $journey_stage.journey_map
      return = {type: "count"}
    } as $stage_count

    precondition ($stage_count > 1) {
      error_type = "inputerror"
      error = "Journey map must keep at least one stage"
    }

    // Is live work pinned to this column's key? work_task identity is
    // (work_item_id, stage_key, lens_key), and a work_item points at a
    // published version of this map. Walked in three steps rather than one
    // join so each step is a plain query. Every id array is seeded with -1 so
    // it is never empty: `in [-1]` correctly matches nothing (CLAUDE.md).
    var $version_ids {
      value = [-1]
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $journey_stage.journey_map
      return = {type: "list"}
    } as $versions

    foreach ($versions) {
      each as $v {
        array.push $version_ids {
          value = $v.id
        }
      }
    }

    var $work_item_ids {
      value = [-1]
    }

    db.query work_item {
      where = $db.work_item.journey_map_version_id in $version_ids
      return = {type: "list"}
    } as $work_items

    foreach ($work_items) {
      each as $wi {
        array.push $work_item_ids {
          value = $wi.id
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id in $work_item_ids && $db.work_task.stage_key == $journey_stage.key
      return = {type: "count"}
    } as $dependent_tasks

    conditional {
      if ($dependent_tasks > 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "ORD-2"
            step       : $log_step
            outcome    : "rejected"
            severity   : "info"
            user_id    : $input.user_id
            account_id : $input.account_id
            entity_type: "journey_map"
            entity_id  : $journey_stage.journey_map
            error_code : "E-ORD-005"
            message    : "Remove refused: live work is pinned to this stage key."
          }
        } as $_dep_logged
      }
    }

    var $dep_message {
      value = "This column can't be removed because %d task(s) in a published plan still point at it. Remove or finish that work first. (E-ORD-005)"|sprintf:$dependent_tasks
    }

    precondition ($dependent_tasks == 0) {
      error_type = "inputerror"
      error = $dep_message
    }

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $journey_stage.journey_map && $db.journey_cell.stage == $journey_stage.id
      return = {type: "list"}
    } as $stage_cells

    db.transaction {
      stack {
        foreach ($stage_cells) {
          each as $cell {
            db.del journey_cell {
              field_name = "id"
              field_value = $cell.id
            }
          }
        }

        db.del journey_stage {
          field_name = "id"
          field_value = $input.journey_stage_id
        }
      }
    }

    // Close the gap the removal left. Removing the column at position 2 used
    // to leave 1, 3, 4; the survivors are now renumbered 1..n by the one
    // place order is written.
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $journey_stage.journey_map
      sort = {display_order: "asc", id: "asc"}
      return = {type: "list"}
    } as $survivors

    var $survivor_ids {
      value = []
    }

    foreach ($survivors) {
      each as $s {
        array.push $survivor_ids {
          value = $s.id
        }
      }
    }

    function.run "journey/apply_stage_order" {
      input = {
        journey_map_id: $journey_stage.journey_map
        stage_ids     : $survivor_ids
        user_id       : $input.user_id
        account_id    : $input.account_id
        step          : $log_step
      }
    } as $resequenced

    db.patch journey_map {
      field_name = "id"
      field_value = $journey_stage.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch

    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }

    db.get journey_map {
      field_name = "id"
      field_value = $journey_stage.journey_map
    } as $journey_map_touch
  }

  response = {
    stage                 : $journey_stage
    deleted_cell_count    : $stage_cells|count
    journey_map_updated_at: $journey_map_touch.updated_at
    reordered_count       : $resequenced.count
  }
}
