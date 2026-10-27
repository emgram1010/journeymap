// ITEM-1 (US-ITEM-1-03) — Write the FULL body of an Items cell:
// {scales_with, lines: [{item_key, method_key, minutes_per_unit}]}.
// The server always replaces, never merges the lines array itself --
// but the underlying column is json, so the replace still needs the
// two-step null-then-value patch (CLAUDE.md) or a stale line would
// survive a merge.
//
// Link reconciliation (one journey_link per distinct method in the
// new lines whose sub_journey_map_id != 0, others removed) happens in
// the SAME transaction as the cell write (US-ITEM-1-03's own rule) --
// a crash between the two must never leave a rate change recorded but
// its sub-journey link stale, or vice versa.
query "journey_map/{journey_map_id}/items-cell/{journey_cell_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int journey_cell_id? filters=min:1
    text scales_with? filters=trim|lower
    json lines?
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

    db.get journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    } as $cell

    precondition ($cell != null && $cell.journey_map == $input.journey_map_id) {
      error_type = "notfound"
      error = "Items cell not found"
    }

    db.get journey_lens {
      field_name = "id"
      field_value = $cell.lens
    } as $cell_lens

    precondition ($cell_lens != null && $cell_lens.template_key == "items-v1") {
      error_type = "notfound"
      error = "Items cell not found"
    }

    function.run "items/validate_items_cell" {
      input = {
        account_id      : $journey_map.account_id
        journey_lens_id : $cell_lens.id
        scales_with     : $input.scales_with
        lines           : $input.lines
      }
    } as $validated

    conditional {
      if ($validated.ok == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "ITEM-1"
            step          : "items_cell_save"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $auth.id
            account_id     : $journey_map.account_id
            entity_type   : "journey_cell"
            entity_id     : $input.journey_cell_id
            correlation_id: $input.correlation_id
            error_code    : $validated.code
            message       : "Items cell save refused."
          }
        } as $_rejected_logged
      }
    }

    precondition ($validated.ok == true) {
      error_type = "inputerror"
      error = $validated.message
    }

    conditional {
      if ($validated.dropped_lines_warn == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "ITEM-1"
            step          : "items_cell_lines_dropped"
            outcome       : "rejected"
            severity      : "warn"
            user_id       : $auth.id
            account_id     : $journey_map.account_id
            entity_type   : "journey_cell"
            entity_id     : $input.journey_cell_id
            correlation_id: $input.correlation_id
            message       : "per_order was sent with lines; the server emptied it."
          }
        } as $_dropped_logged
      }
    }

    // ── Resolve the distinct methods in the NEW lines, before the
    // transaction (no function.run inside one). $distinct_method_keys is
    // built directly with array.push (never |keys, unconfirmed in this
    // workspace) and de-duplicated via the proven get+null-check pattern.
    var $method_keys_map {
      value = {}
    }

    var $distinct_method_keys {
      value = []
    }

    foreach ($validated.normalized_lines) {
      each as $nl {
        var $nl_seen {
          value = $method_keys_map|get:$nl.method_key
        }

        conditional {
          if ($nl_seen == null) {
            var.update $method_keys_map {
              value = $method_keys_map|set:$nl.method_key:true
            }

            array.push $distinct_method_keys {
              value = $nl.method_key
            }
          }
        }
      }
    }

    var $used_methods {
      value = []
    }

    conditional {
      if (($distinct_method_keys|count) > 0) {
        db.query method {
          where = $db.method.account_id == $journey_map.account_id && $db.method.key in $distinct_method_keys
          return = {type: "list"}
        } as $used_methods_query

        var.update $used_methods {
          value = $used_methods_query
        }
      }
    }

    var $desired_link_method_ids {
      value = [-1]
    }

    foreach ($used_methods) {
      each as $um {
        conditional {
          if ($um.sub_journey_map_id != 0) {
            array.push $desired_link_method_ids {
              value = $um.sub_journey_map_id
            }
          }
        }
      }
    }

    db.query journey_link {
      where = $db.journey_link.source_cell == $input.journey_cell_id && $db.journey_link.link_type == "sub_journey"
      return = {type: "list"}
    } as $existing_links

    var $desired_map_ids_map {
      value = {}
    }

    foreach ($desired_link_method_ids) {
      each as $dmid {
        var $dmid_key {
          value = $dmid|to_text
        }

        var.update $desired_map_ids_map {
          value = $desired_map_ids_map|set:$dmid_key:true
        }
      }
    }

    var $links_to_remove {
      value = []
    }

    var $existing_target_map_ids_map {
      value = {}
    }

    foreach ($existing_links) {
      each as $el {
        var $el_key {
          value = $el.target_map|to_text
        }

        var.update $existing_target_map_ids_map {
          value = $existing_target_map_ids_map|set:$el_key:true
        }

        var $still_desired {
          value = $desired_map_ids_map|get:$el_key
        }

        conditional {
          if ($still_desired == null) {
            array.push $links_to_remove {
              value = $el
            }
          }
        }
      }
    }

    var $links_to_add {
      value = []
    }

    foreach ($used_methods) {
      each as $um2 {
        conditional {
          if ($um2.sub_journey_map_id != 0) {
            var $um2_key {
              value = $um2.sub_journey_map_id|to_text
            }

            var $already_linked {
              value = $existing_target_map_ids_map|get:$um2_key
            }

            conditional {
              if ($already_linked == null) {
                array.push $links_to_add {
                  value = $um2
                }
              }
            }
          }
        }
      }
    }

    db.transaction {
      stack {
        db.patch journey_cell {
          field_name = "id"
          field_value = $input.journey_cell_id
          data = {actor_fields: null}
        }

        db.patch journey_cell {
          field_name = "id"
          field_value = $input.journey_cell_id
          data = {
            actor_fields: {
              scales_with: $input.scales_with
              lines      : $validated.normalized_lines
            }
            updated_at: "now"
          }
        } as $updated_cell

        foreach ($links_to_remove) {
          each as $ltr {
            db.del journey_link {
              field_name = "id"
              field_value = $ltr.id
            }
          }
        }

        foreach ($links_to_add) {
          each as $lta {
            db.add journey_link {
              data = {
                journey_architecture: $journey_map.journey_architecture
                source_map          : $input.journey_map_id
                source_cell         : $input.journey_cell_id
                target_map          : $lta.sub_journey_map_id
                link_type           : "sub_journey"
                label               : $lta.key
                owner_user          : $journey_map.owner_user
              }
            } as $added_link
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "ITEM-1"
        step          : "items_cell_save"
        outcome       : "success"
        severity      : "info"
        user_id       : $auth.id
        account_id     : $journey_map.account_id
        entity_type   : "journey_cell"
        entity_id     : $input.journey_cell_id
        correlation_id: $input.correlation_id
        message       : "Items cell saved."
        metadata      : {scales_with: $input.scales_with, line_count: ($validated.normalized_lines|count)}
      }
    } as $_success_logged

    db.get journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    } as $final_cell
  }

  response = {
    cell          : $final_cell
    links_added   : ($links_to_add|count)
    links_removed : ($links_to_remove|count)
  }
}
