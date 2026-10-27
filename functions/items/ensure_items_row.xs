// ITEM-1 (US-ITEM-1-01) — Creates the one Items row a map may have: a
// journey_lens (key="items", actor_type="", template_key="items-v1"),
// its journey_lens_planned_work(false) row, and one empty Items cell
// per existing stage, all in a single db.transaction. Rejects
// E-ITM-001 when the map already has one.
//
// Named "ensure" to match the epic's own file list, even though its
// behaviour is "create once, reject the second attempt" rather than an
// idempotent no-op -- `second create -> E-ITM-001` is this epic's own
// acceptance criterion (US-ITEM-1-01), not a bug in the name.
//
// display_order comes from journey/next_lens_key, the one place that
// number is minted -- same helper insert_lens uses, so the Items row
// can never collide with another row's order. D-1 ("always last") is
// enforced again, defensively, at render time on the frontend (the
// Items row is always sorted to the end of the matrix regardless of
// its raw display_order), since a later insert elsewhere in the map
// could in principle still land a higher number.
//
// No function.run inside the transaction (CLAUDE.md) -- journey/next_lens_key
// and the stage list are resolved BEFORE it opens.
function "items/ensure_items_row" {
  input {
    int journey_map_id filters=min:1
    int user_id?
    int account_id?
    text correlation_id? filters=trim
  }

  stack {
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "items-v1"
      return = {type: "count"}
    } as $existing_count

    conditional {
      if ($existing_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "ITEM-1"
            step       : "items_row_create"
            outcome    : "rejected"
            severity   : "info"
            user_id    : $input.user_id
            account_id : $input.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            correlation_id: $input.correlation_id
            error_code : "E-ITM-001"
            message    : "Items row create refused: this map already has one."
          }
        } as $_rejected_logged
      }
    }

    precondition ($existing_count == 0) {
      error_type = "inputerror"
      error = "This map already has an Items row. (E-ITM-001)"
    }

    function.run "journey/next_lens_key" {
      input = {journey_map_id: $input.journey_map_id}
    } as $mint

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages

    var $cells {
      value = []
    }

    db.transaction {
      stack {
        db.add journey_lens {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $input.journey_map_id
            key          : "items"
            label        : "Items"
            actor_type   : ""
            template_key : "items-v1"
            display_order: $mint.display_order
          }
        } as $items_lens

        db.add journey_lens_planned_work {
          data = {
            journey_lens     : $items_lens.id
            does_planned_work: false
          }
        } as $planned_work_row

        foreach ($stages) {
          each as $stage {
            db.add journey_cell {
              data = {
                created_at  : "now"
                updated_at  : "now"
                journey_map : $input.journey_map_id
                stage       : $stage.id
                lens        : $items_lens.id
                content     : ""
                status      : "open"
                is_locked   : false
                actor_fields: {scales_with: "per_order", lines: []}
              }
            } as $cell

            array.push $cells {
              value = $cell
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "ITEM-1"
        step       : "items_row_create"
        outcome    : "success"
        severity   : "info"
        user_id    : $input.user_id
        account_id : $input.account_id
        entity_type: "journey_lens"
        entity_id  : $items_lens.id
        correlation_id: $input.correlation_id
        message    : "Items row created."
        metadata   : {cell_count: ($cells|count)}
      }
    } as $_success_logged
  }

  response = {
    lens        : $items_lens
    cells       : $cells
    planned_work: $planned_work_row
  }
}
