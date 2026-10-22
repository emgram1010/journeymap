// THE ONE PLACE A COLUMN IS ADDED TO A MAP. Appends or inserts at a position,
// scaffolds one cell per existing row, and hands the final order to
// journey/apply_stage_order.
//
// ORD-2 US-ORD-2-02. Lifted out of endpoint 47 (journey_stage/add) so the
// matrix buttons and the AI tools run the same code. Before this, the AI's
// add_stage called `api.call ""` — an empty path in an empty API group — so it
// reported success and changed nothing.
//
// AUTHORISATION IS THE CALLER'S JOB. This function verifies the map exists and
// that the anchor belongs to it; it does NOT check who is asking. Endpoint 47
// keeps its ownership precondition and runs it before calling this. Do not
// expose this function through a new endpoint without a guard in front of it.
//
// after_stage_id IS REQUIRED, and -1 means append. It is required on purpose:
// an omitted optional int arrives as 0, and 0 is the legitimate "insert at the
// very front" value, so an optional input could not tell the two apart
// (CLAUDE.md). Detecting "was it sent" needs the raw request body, which only
// an endpoint has — so the endpoint decides and passes -1, 0, or an id.
function "journey/insert_stage" {
  input {
    int journey_map_id filters=min:1

    // -1 = append to the end. 0 = insert first. An id = insert after that row.
    int after_stage_id

    text label? filters=trim
    text stage_goal? filters=trim
    text primary_actor_lens? filters=trim

    // Logging only — who to attribute the event to.
    int user_id?
    int account_id?
    text step? filters=trim
  }

  stack {
    var $cells {
      value = []
    }

    var $log_step {
      value = "insert_stage"
    }

    conditional {
      if ($input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_lenses

    precondition (($existing_lenses|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one lens before adding a stage"
    }

    // The anchor must be a row of THIS map, or an insert becomes a cross-map
    // read. Checked before anything is written.
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.id == $input.after_stage_id
      return = {type: "count"}
    } as $anchor_found

    var $anchor_bad {
      value = ($input.after_stage_id > 0) && ($anchor_found == 0)
    }

    conditional {
      if ($anchor_bad) {
        function.run "ops/log_event" {
          input = {
            feature    : "ORD-2"
            step       : $log_step
            outcome    : "rejected"
            severity   : "info"
            user_id    : $input.user_id
            account_id : $journey_map.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            error_code : "E-ORD-002"
            message    : "Insert refused: the stage to insert after is not in this map."
          }
        } as $_anchor_logged
      }
    }

    precondition ($anchor_bad == false) {
      error_type = "inputerror"
      error = "The column you tried to insert next to isn't in this map any more, so nothing was added. Refresh and try again. (E-ORD-002)"
    }

    function.run "journey/next_stage_key" {
      input = {journey_map_id: $input.journey_map_id}
    } as $mint

    var $next_stage_order {
      value = $mint.display_order
    }

    var $stage_label {
      value = "Stage %d"|sprintf:$next_stage_order
    }

    // An inserted column would otherwise be called "Stage <append position>",
    // which is a lie the moment it is placed somewhere else.
    conditional {
      if ($input.after_stage_id >= 0) {
        var.update $stage_label {
          value = "New stage"
        }
      }
    }

    conditional {
      if ($input.label != "") {
        var.update $stage_label {
          value = $input.label
        }
      }
    }

    db.add journey_stage {
      enforce_hidden_fields = false
      data = {
        created_at        : "now"
        updated_at        : "now"
        journey_map       : $input.journey_map_id
        key               : $mint.key
        label             : $stage_label
        display_order     : $next_stage_order
        stage_goal        : $input.stage_goal
        primary_actor_lens: $input.primary_actor_lens
      }
    } as $journey_stage

    // One cell per existing row, each scaffolded with that row's own field
    // shape. The shape comes from journey/actor_template, so it can no longer
    // differ from what journey_lens/add would have produced — and
    // financial-v1, which this scaffold used to have no case for, now gets its
    // fields instead of nothing.
    foreach ($existing_lenses) {
      each as $lens {
        function.run "journey/actor_template" {
          input = {
            template_key: $lens.template_key
          }
        } as $tpl

        db.add journey_cell {
          enforce_hidden_fields = false
          data = {
            created_at  : "now"
            updated_at  : "now"
            journey_map : $input.journey_map_id
            stage       : $journey_stage.id
            lens        : $lens.id
            content     : ""
            status      : "open"
            is_locked   : false
            actor_fields: $tpl.actor_fields
          }
        } as $cell

        array.push $cells {
          value = $cell
        }
      }
    }

    // Place it. It was appended above (key and order from the shared mint);
    // now splice it in after the anchor and let journey/apply_stage_order —
    // the one place stage order is written — renumber the map 1..n. Every
    // condition in the loop reads only the loop item or a value set before the
    // loop started (CLAUDE.md).
    var $placed_count {
      value = 0
    }

    conditional {
      if ($input.after_stage_id >= 0) {
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id
          sort = {display_order: "asc", id: "asc"}
          return = {type: "list"}
        } as $ordered_rows

        var $placed_ids {
          value = []
        }

        conditional {
          if ($input.after_stage_id == 0) {
            array.push $placed_ids {
              value = $journey_stage.id
            }
          }
        }

        foreach ($ordered_rows) {
          each as $or {
            conditional {
              if ($or.id != $journey_stage.id) {
                array.push $placed_ids {
                  value = $or.id
                }

                conditional {
                  if ($or.id == $input.after_stage_id) {
                    array.push $placed_ids {
                      value = $journey_stage.id
                    }
                  }
                }
              }
            }
          }
        }

        function.run "journey/apply_stage_order" {
          input = {
            journey_map_id: $input.journey_map_id
            stage_ids     : $placed_ids
            user_id       : $input.user_id
            account_id    : $journey_map.account_id
            step          : $log_step
          }
        } as $placed

        var.update $placed_count {
          value = $placed.count
        }
      }
    }

    db.get journey_stage {
      field_name = "id"
      field_value = $journey_stage.id
    } as $placed_row

    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch

    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map_touch
  }

  response = {
    stage                 : $placed_row
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
    reordered_count       : $placed_count
  }
}
