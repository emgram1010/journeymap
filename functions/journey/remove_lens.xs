// THE ONE PLACE A ROW IS REMOVED FROM A MAP. Deletes the row and every cell in
// it, refuses if live work depends on its key, clears any stage that named it
// as the accountable actor, and renumbers what is left.
//
// ORD-2 US-ORD-2-03. Lifted out of endpoint 50 (journey_lens/remove) so the
// matrix and the AI tools run the same code. Before this, the AI's remove_lens
// called `api.call ""` — an empty path in an empty API group — so it reported
// success and deleted nothing.
//
// AUTHORISATION IS THE CALLER'S JOB — see journey/remove_stage, including the
// note that endpoint 50 never had an ownership check of its own.
//
// THE CASCADE DELETES EACH CELL BY ITS OWN id, INSIDE A TRANSACTION, because
// db.del with field_name/field_value removes only the FIRST match (CLAUDE.md).
function "journey/remove_lens" {
  input {
    int journey_lens_id filters=min:1

    // Logging only.
    int user_id?
    int account_id?
    text step? filters=trim
  }

  stack {
    var $log_step {
      value = "remove_lens"
    }

    conditional {
      if ($input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $journey_lens

    precondition ($journey_lens != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }

    // RATE-1 review #4 (D-R2) — the Items row has its own delete (endpoint
    // 603), which also removes its journey_lens_item rows, its planned-work
    // row and its links, and refuses once rates are published (E-RATE-002).
    // This generic path would orphan all of that and skip the guard.
    precondition ($journey_lens.template_key != "items-v1") {
      error_type = "inputerror"
      error = "The Items row is removed with its own Remove row button. (E-ITM-009)"
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $journey_lens.journey_map
      return = {type: "count"}
    } as $lens_count

    precondition ($lens_count > 1) {
      error_type = "inputerror"
      error = "Journey map must keep at least one lens"
    }

    // Is live work pinned to this row's key? Same three-step walk as
    // remove_stage, matching on lens_key instead. Arrays seeded with -1 so
    // `in` never receives an empty list (CLAUDE.md).
    var $version_ids {
      value = [-1]
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $journey_lens.journey_map
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
      where = $db.work_task.work_item_id in $work_item_ids && $db.work_task.lens_key == $journey_lens.key
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
            entity_id  : $journey_lens.journey_map
            error_code : "E-ORD-005"
            message    : "Remove refused: live work is pinned to this lens key."
          }
        } as $_dep_logged
      }
    }

    var $dep_message {
      value = "This row can't be removed because %d task(s) in a published plan still point at it. Remove or finish that work first. (E-ORD-005)"|sprintf:$dependent_tasks
    }

    precondition ($dependent_tasks == 0) {
      error_type = "inputerror"
      error = $dep_message
    }

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $journey_lens.journey_map && $db.journey_cell.lens == $journey_lens.id
      return = {type: "list"}
    } as $lens_cells

    // A stage can name this row as its accountable actor, by key, in
    // primary_actor_lens. Left alone it would point at a row that no longer
    // exists, which nothing would ever report. Cleared here, each row patched
    // by its own id.
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $journey_lens.journey_map && $db.journey_stage.primary_actor_lens == $journey_lens.key
      return = {type: "list"}
    } as $orphaned_contracts

    db.transaction {
      stack {
        foreach ($lens_cells) {
          each as $cell {
            db.del journey_cell {
              field_name = "id"
              field_value = $cell.id
            }
          }
        }

        foreach ($orphaned_contracts) {
          each as $os {
            db.patch journey_stage {
              field_name = "id"
              field_value = $os.id
              data = {primary_actor_lens: "", updated_at: "now"}
            } as $cleared
          }
        }

        db.del journey_lens {
          field_name = "id"
          field_value = $input.journey_lens_id
        }
      }
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $journey_lens.journey_map
      sort = {display_order: "asc", id: "asc"}
      return = {type: "list"}
    } as $survivors

    var $survivor_ids {
      value = []
    }

    foreach ($survivors) {
      each as $l {
        array.push $survivor_ids {
          value = $l.id
        }
      }
    }

    function.run "journey/apply_lens_order" {
      input = {
        journey_map_id: $journey_lens.journey_map
        lens_ids      : $survivor_ids
        user_id       : $input.user_id
        account_id    : $input.account_id
        step          : $log_step
      }
    } as $resequenced

    db.patch journey_map {
      field_name = "id"
      field_value = $journey_lens.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch
  }

  response = {
    lens                   : $journey_lens
    deleted_cell_count     : $lens_cells|count
    cleared_stage_contracts: $orphaned_contracts|count
    journey_map_updated_at : $journey_map_touch.updated_at
    reordered_count        : $resequenced.count
  }
}
