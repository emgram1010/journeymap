// ITEM-1 (US-ITEM-1-02) — Replace the map's whole chosen-item set
// (journey_lens_item) in one call. D-2: a map's item list is a
// deliberate per-map subset of the account catalog, never "every
// active item shows automatically".
//
// REMOVING an item clears its lines from every Items cell on this map
// in the SAME transaction (US-ITEM-1-02's own acceptance criterion).
// Finding "removed" needs the removed items' KEYS (lines reference
// item_key, not item_type_id), so the old item_type rows are read
// before the diff, not just their lens_item rows.
//
// Query-then-loop for both the delete and the insert half of the
// replace (CLAUDE.md: db.del by field_name/field_value only removes
// the first match) and the two-step JSON patch for every touched
// cell's actor_fields (CLAUDE.md: a single db.patch on a json column
// MERGES, so clearing a dropped line needs null-then-value).
query "journey_map/{journey_map_id}/items-row/items" verb=PUT {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    json item_type_ids?
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

    // ── Validate the requested set: every id active, same account. ──
    var $requested_ids {
      value = $input.item_type_ids
    }

    db.query item_type {
      where = $db.item_type.account_id == $journey_map.account_id && $db.item_type.id in $requested_ids && $db.item_type.is_active == true
      return = {type: "list"}
    } as $valid_items

    var $reject_code {
      value = ""
    }

    conditional {
      if (($valid_items|count) != ($requested_ids|count)) {
        var.update $reject_code {
          value = "E-ITM-002"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "ITEM-1"
            step          : "items_row_items_set"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $auth.id
            account_id    : $journey_map.account_id
            entity_type   : "journey_lens"
            entity_id     : $items_lens.id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Items set refused: one or more items are inactive or belong to a different account."
          }
        } as $_rejected_logged
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = "Add that item to this map's item list first. (E-ITM-002)"
    }

    // ── Diff against the CURRENT set. ──
    db.query journey_lens_item {
      where = $db.journey_lens_item.journey_lens == $items_lens.id
      return = {type: "list"}
    } as $old_rows

    // `in` as a plain boolean expression (outside a db.query where clause)
    // is unconfirmed in this workspace -- CLAUDE.md only confirms it
    // compiling to SQL inside a where. Membership is checked the proven
    // way instead: a pre-built id->true map, |get, then a null test.
    var $requested_ids_map {
      value = {}
    }

    foreach ($requested_ids) {
      each as $rqid {
        var $rqid_key {
          value = $rqid|to_text
        }

        var.update $requested_ids_map {
          value = $requested_ids_map|set:$rqid_key:true
        }
      }
    }

    var $removed_item_type_ids {
      value = [-1]
    }

    foreach ($old_rows) {
      each as $old {
        var $old_key {
          value = $old.item_type_id|to_text
        }

        var $still_present {
          value = $requested_ids_map|get:$old_key
        }

        conditional {
          if ($still_present == null) {
            array.push $removed_item_type_ids {
              value = $old.item_type_id
            }
          }
        }
      }
    }

    db.query item_type {
      where = $db.item_type.id in $removed_item_type_ids
      return = {type: "list"}
    } as $removed_items

    var $removed_keys {
      value = {}
    }

    foreach ($removed_items) {
      each as $ri {
        var.update $removed_keys {
          value = $removed_keys|set:$ri.key:true
        }
      }
    }

    // ── Everything else a removed item touches is read before the
    // transaction, written inside it (US-ITEM-1-02: cell cleanup and the
    // lens_item replace happen in the SAME transaction). ──
    db.query journey_cell {
      where = $db.journey_cell.lens == $items_lens.id
      return = {type: "list"}
    } as $items_cells

    var $touched_cell_count {
      value = 0
    }

    // sort_order follows the CALLER's requested order, not the db.query's
    // arbitrary `in` result order -- built as an id->true map first so the
    // insert loop below can walk $requested_ids directly.
    var $valid_ids_map {
      value = {}
    }

    foreach ($valid_items) {
      each as $vi2 {
        var.update $valid_ids_map {
          value = $valid_ids_map|set:($vi2.id|to_text):true
        }
      }
    }

    var $sort_counter {
      value = 0
    }

    db.transaction {
      stack {
        conditional {
          if (($removed_items|count) > 0) {
            foreach ($items_cells) {
              each as $cell {
                var $existing_fields {
                  value = ($cell.actor_fields ?? {scales_with: "per_order", lines: []})
                }

                var $existing_lines {
                  value = ($existing_fields.lines ?? [])
                }

                var $kept_lines {
                  value = []
                }

                var $any_dropped {
                  value = false
                }

                foreach ($existing_lines) {
                  each as $line {
                    var $line_removed {
                      value = $removed_keys|get:$line.item_key
                    }

                    conditional {
                      if ($line_removed != null) {
                        var.update $any_dropped {
                          value = true
                        }
                      }

                      else {
                        array.push $kept_lines {
                          value = $line
                        }
                      }
                    }
                  }
                }

                conditional {
                  if ($any_dropped == true) {
                    var.update $touched_cell_count {
                      value = $touched_cell_count + 1
                    }

                    db.patch journey_cell {
                      field_name = "id"
                      field_value = $cell.id
                      data = {actor_fields: null}
                    }

                    db.patch journey_cell {
                      field_name = "id"
                      field_value = $cell.id
                      data = {
                        actor_fields: {
                          scales_with: $existing_fields.scales_with
                          lines      : $kept_lines
                        }
                        updated_at: "now"
                      }
                    }
                  }
                }
              }
            }
          }
        }

        foreach ($old_rows) {
          each as $old2 {
            db.del journey_lens_item {
              field_name = "id"
              field_value = $old2.id
            }
          }
        }

        foreach ($requested_ids) {
          each as $rid {
            var $rid_key {
              value = $rid|to_text
            }

            var $rid_valid {
              value = $valid_ids_map|get:$rid_key
            }

            conditional {
              if ($rid_valid != null) {
                db.add journey_lens_item {
                  data = {
                    journey_lens: $items_lens.id
                    item_type_id: $rid
                    sort_order  : $sort_counter
                  }
                } as $added_row

                var.update $sort_counter {
                  value = $sort_counter + 1
                }
              }
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "ITEM-1"
        step          : "items_row_items_set"
        outcome       : "success"
        severity      : "info"
        user_id       : $auth.id
        account_id    : $journey_map.account_id
        entity_type   : "journey_lens"
        entity_id     : $items_lens.id
        correlation_id: $input.correlation_id
        message       : "Items row item list updated."
        metadata      : {item_count: ($valid_items|count), removed_count: ($removed_items|count), touched_cells: $touched_cell_count}
      }
    } as $_success_logged

    db.query journey_lens_item {
      where = $db.journey_lens_item.journey_lens == $items_lens.id
      return = {type: "list"}
    } as $final_set
  }

  response = {
    items        : $final_set
    removed_count: ($removed_items|count)
    touched_cells: $touched_cell_count
  }
}
