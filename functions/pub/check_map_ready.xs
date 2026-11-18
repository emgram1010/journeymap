// COP-10 — "is this map ready to publish?", for the AI tool check_publish_ready. The same answer
// endpoint 520 (GET journey_map/{id}/readiness) gives a person: it builds the snapshot a publish
// would freeze, resolves the Items-row and exception-link facts the way 520 does, and runs
// pub/evaluate_gate. It holds NO checklist rule of its own: every blocker and warning is whatever the
// gate returns, so a rule added there reaches the AI with no change here.
//
// Read-only. It never publishes, never patches, never logs (the tool logs). A map that does not exist
// raises notfound; who may see the map is the caller's job (the tool runs journey/tool_gate first).
function "pub/check_map_ready" {
  input {
    int journey_map_id filters=min:1
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

    function.run "pub/build_map_snapshot" {
      input = {journey_map_id: $input.journey_map_id}
    } as $snapshot_result

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "items-v1"
      return = {type: "single"}
    } as $items_lens

    var $items_cells_for_readiness {
      value = []
    }

    conditional {
      if ($items_lens != null) {
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id
          return = {type: "list"}
        } as $stages_for_readiness

        var $stage_key_map {
          value = {}
        }

        foreach ($stages_for_readiness) {
          each as $st {
            var $st_id_key {
              value = $st.id|to_text
            }

            var.update $stage_key_map {
              value = $stage_key_map|set:$st_id_key:$st.key
            }
          }
        }

        db.query journey_cell {
          where = $db.journey_cell.lens == $items_lens.id
          return = {type: "list"}
        } as $items_cells_raw

        foreach ($items_cells_raw) {
          each as $ic {
            var $ic_fields {
              value = ($ic.actor_fields ?? {scales_with: "per_order", lines: []})
            }

            var $ic_scales_with {
              value = ($ic_fields.scales_with ?? "per_order")
            }

            conditional {
              if ($ic_scales_with == "per_unit" || $ic_scales_with == "per_flagged_unit") {
                var $ic_lines {
                  value = ($ic_fields.lines ?? [])
                }

                var $missing_keys {
                  value = []
                }

                foreach ($ic_lines) {
                  each as $icl {
                    conditional {
                      if ((($icl.minutes_per_unit ?? "")|to_text) == "") {
                        array.push $missing_keys {
                          value = $icl.item_key
                        }
                      }
                    }
                  }
                }

                conditional {
                  if (($ic_lines|count) == 0 || ($missing_keys|count) > 0) {
                    var $ic_stage_key_lookup {
                      value = $ic.stage|to_text
                    }

                    array.push $items_cells_for_readiness {
                      value = {
                        stage_key: ($stage_key_map|get:$ic_stage_key_lookup)
                        item_keys: $missing_keys
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    function.run "exceptions/exception_targets" {
      input = {journey_map_id: $input.journey_map_id, snapshot: $snapshot_result.snapshot}
    } as $exception_targets

    function.run "pub/evaluate_gate" {
      input = {snapshot: $snapshot_result.snapshot, items_cells: $items_cells_for_readiness, account_id: $journey_map.account_id, exception_targets: $exception_targets}
    } as $gate
  }

  response = {
    ready      : $gate.ready
    blockers   : $gate.gate_failures
    warnings   : $gate.warnings
    ready_count: $gate.ready_count
    total      : $gate.total
    status     : $journey_map.status
    title      : $journey_map.title
  }
}
