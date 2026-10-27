// PUB-1 (US-PUB-1-01) — The server's own answer to "is this map ready?".
//
// Read-only and safe to poll: it builds the same snapshot a publish would
// freeze and runs the same gate a publish would run, so what the UI shows
// here and what the publish endpoint decides can never disagree.
//
// `blockers` and `gate_failures` are the same list under two names:
// `blockers` matches the shape US-PUB-1-01 specifies, `gate_failures`
// matches the earlier publishing initiative's contract (D-39). Both are
// the gate's view — readiness plus the real-title rule.
query "journey_map/{journey_map_id}/readiness" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
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
      error = "You don't have access to this map. (E-PUB-004)"
    }

    function.run "pub/build_map_snapshot" {
      input = {journey_map_id: $input.journey_map_id}
    } as $snapshot_result

    // ITEM-1 (US-ITEM-1-05) — Items cells never reach the snapshot
    // (ITEM-0 audit), so the incomplete-rate warning is built here,
    // separately, and handed to the gate as an additive input.
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

                // RATE-1: tested as text, same as build_map_snapshot —
                // `0 == null` is true in this engine, so the old
                // `== null` check called a real 0-minute rate "missing".
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

    // EXC-1 (US-EXC-1-01) — facts about each exception link's target
    // (published? Items row? same architecture?), for readiness WARNINGS.
    // Not logged as events here: this endpoint is polled, and a warn per
    // poll would flood event_log (the OBS-1 heartbeat lesson). Health
    // reads unpublished targets directly instead (US-EXC-1-07).
    function.run "exceptions/exception_targets" {
      input = {journey_map_id: $input.journey_map_id, snapshot: $snapshot_result.snapshot}
    } as $exception_targets

    function.run "pub/evaluate_gate" {
      input = {snapshot: $snapshot_result.snapshot, items_cells: $items_cells_for_readiness, account_id: $journey_map.account_id, exception_targets: $exception_targets}
    } as $gate
  }

  response = {
    ready        : $gate.ready
    blockers     : $gate.gate_failures
    warnings     : $gate.warnings
    ready_count  : $gate.ready_count
    total        : $gate.total
    gate_failures: $gate.gate_failures
  }
}
