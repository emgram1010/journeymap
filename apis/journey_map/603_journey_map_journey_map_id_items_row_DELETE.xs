// ITEM-1 (US-ITEM-1-01) — Delete the map's Items row: its cells, its
// journey_lens_item rows, any journey_link anchored on one of its
// cells, its journey_lens_planned_work row, and the lens itself, all
// in one db.transaction. Published versions are untouched (EC-9) --
// this only ever touches the live draft tables; a published version's
// snapshot is a frozen copy elsewhere.
//
// Every row set is QUERIED FIRST, then deleted by id inside the
// transaction (CLAUDE.md: db.del by field_name/field_value only
// removes the first match, so "delete every row for this lens" needs
// a query-then-loop, never a bare db.del).
query "journey_map/{journey_map_id}/items-row" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "items-v1"
      return = {type: "single"}
    } as $items_lens

    precondition ($items_lens != null) {
      error_type = "notfound"
      error = "This map has no Items row"
    }

    // RATE-1 (US-RATE-1-06) — once any version of this map published
    // rates, the row can't be removed: emptying it (every stage per
    // order) and publishing again is the honest history instead.
    // Counted by arithmetic, not a conditional, inside the loop.
    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $map_versions

    var $rated_version_count {
      value = 0
    }

    foreach ($map_versions) {
      each as $map_version_row {
        var.update $rated_version_count {
          value = $rated_version_count + (((($map_version_row.snapshot.rates ?? [])|count) > 0)|to_int)
        }
      }
    }

    conditional {
      if ($rated_version_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "RATE-1"
            step          : "items_row_delete_blocked"
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-RATE-002"
            message       : "Items row delete refused: a published version of this map has rates."
            user_id       : $auth.id
            account_id    : $journey_map.account_id
            entity_type   : "journey_lens"
            entity_id     : $items_lens.id
            correlation_id: $input.correlation_id
            metadata      : {rated_version_count: $rated_version_count}
          }
        } as $_rated_logged
      }
    }

    precondition ($rated_version_count == 0) {
      error_type = "inputerror"
      error = "This map has published rates. Set every stage to per order and publish again instead of removing the row. (E-RATE-002)"
    }

    db.query journey_cell {
      where = $db.journey_cell.lens == $items_lens.id
      return = {type: "list"}
    } as $cells_to_remove

    var $cell_ids {
      value = [-1]
    }

    foreach ($cells_to_remove) {
      each as $c {
        array.push $cell_ids {
          value = $c.id
        }
      }
    }

    db.query journey_link {
      where = $db.journey_link.source_cell in $cell_ids
      return = {type: "list"}
    } as $links_to_remove

    db.query journey_lens_item {
      where = $db.journey_lens_item.journey_lens == $items_lens.id
      return = {type: "list"}
    } as $lens_items_to_remove

    db.query journey_lens_planned_work {
      where = $db.journey_lens_planned_work.journey_lens == $items_lens.id
      return = {type: "list"}
    } as $planned_work_rows

    db.transaction {
      stack {
        foreach ($links_to_remove) {
          each as $link {
            db.del journey_link {
              field_name = "id"
              field_value = $link.id
            }
          }
        }

        foreach ($lens_items_to_remove) {
          each as $li {
            db.del journey_lens_item {
              field_name = "id"
              field_value = $li.id
            }
          }
        }

        foreach ($planned_work_rows) {
          each as $pw {
            db.del journey_lens_planned_work {
              field_name = "id"
              field_value = $pw.id
            }
          }
        }

        foreach ($cells_to_remove) {
          each as $c {
            db.del journey_cell {
              field_name = "id"
              field_value = $c.id
            }
          }
        }

        db.del journey_lens {
          field_name = "id"
          field_value = $items_lens.id
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "ITEM-1"
        step          : "items_row_delete"
        outcome       : "success"
        severity      : "info"
        user_id       : $auth.id
        account_id    : $journey_map.account_id
        entity_type   : "journey_lens"
        entity_id     : $items_lens.id
        correlation_id: $input.correlation_id
        message       : "Items row deleted."
        metadata      : {cell_count: ($cells_to_remove|count), link_count: ($links_to_remove|count)}
      }
    } as $_logged

    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch
  }

  response = {
    deleted               : true
    removed_cells         : ($cells_to_remove|count)
    removed_links         : ($links_to_remove|count)
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}
