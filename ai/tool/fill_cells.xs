// IL-00-04: MCP tool — fill journey map cells with content and/or actor_fields.
// Maps to batch cell writes. Input: journey_map_id + array of { stage_key, lens_key, content?, actor_fields? }.
// SAFE-1 (2026-11-21): (1) locked and confirmed cells are now SKIPPED, like update_cell and
// batch_update — before this, fill_cells overwrote them; (2) each write goes through the one
// keep-or-clear rule, journey/cell_merge_patch (left out or null = keep, "" = clear).
tool fill_cells {
  instructions = "Write content into journey map cells. Pass journey_map_id and an array of cell updates, each with stage_key, lens_key, and optionally content (text), actor_fields (JSON object, merged into what is stored), time_duration_value (decimal), time_duration_unit (minutes|hours|days|weeks), planned_duration (decimal), and actual_duration (decimal). Leave a field out (or send null) to keep what is stored; send an empty string to clear the text. Locked and confirmed cells are skipped and listed in skipped_detail with the reason. Returns count of cells written and skipped."

  input {
    int journey_map_id filters=min:1

    // Array of { stage_key, lens_key, content?, actor_fields? }
    json cell_updates

    // COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty.
    text ticket? filters=trim
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {
        journey_map_id: $input.journey_map_id
        ticket        : $input.ticket
        tool          : "fill_cells"
        kind          : "write"
      }
    } as $cop1_gate

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    // RES-6-04: hard cap on batch size to bound execution time and memory.
    precondition ($input.cell_updates == null || ($input.cell_updates|count) <= 500) {
      error_type = "inputerror"
      error = "Batch too large — max 500 cell_updates per call. Split into multiple calls."
    }

    // Load stages and lenses for key lookups
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses

    // Load all cells for the map once and build a (stage_id)_(lens_id) → cell lookup
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $all_cells

    var $cell_map {
      value = {}
    }

    foreach ($all_cells) {
      each as $c {
        var $ck {
          value = ($c.stage|to_text) ~ "_" ~ ($c.lens|to_text)
        }

        var.update $cell_map {
          value = $cell_map|set:$ck:$c
        }
      }
    }

    var $written {
      value = 0
    }

    var $skipped {
      value = 0
    }

    // SAFE-1: why each cell was skipped (additive response field).
    var $skipped_detail {
      value = []
    }

    // RES-6-03: additive failure surface.
    var $failed {
      value = []
    }

    var $failed_count {
      value = 0
    }

    foreach ($input.cell_updates) {
      each as $upd {
        // Resolve stage
        var $matched_stage {
          value = null
        }

        foreach ($stages) {
          each as $s {
            conditional {
              if ($s.key == $upd.stage_key) {
                var.update $matched_stage {
                  value = $s
                }
              }
            }
          }
        }

        // Resolve lens
        var $matched_lens {
          value = null
        }

        foreach ($lenses) {
          each as $l {
            conditional {
              if ($l.key == $upd.lens_key) {
                var.update $matched_lens {
                  value = $l
                }
              }
            }
          }
        }

        conditional {
          if ($matched_stage != null && $matched_lens != null) {
            // Resolve cell from pre-loaded dict — no per-item DB query
            var $cell_key {
              value = ($matched_stage.id|to_text) ~ "_" ~ ($matched_lens.id|to_text)
            }

            var $cell {
              value = $cell_map|get:$cell_key
            }

            conditional {
              if ($cell == null) {
                var.update $skipped {
                  value = $skipped + 1
                }

                array.push $skipped_detail {
                  value = {stage_key: $upd.stage_key, lens_key: $upd.lens_key, reason: "not_found"}
                }
              }

              // SAFE-1: never overwrite a locked or user-confirmed cell.
              elseif ($cell.is_locked) {
                var.update $skipped {
                  value = $skipped + 1
                }

                array.push $skipped_detail {
                  value = {stage_key: $upd.stage_key, lens_key: $upd.lens_key, reason: "locked"}
                }
              }

              elseif ($cell.status == "confirmed") {
                var.update $skipped {
                  value = $skipped + 1
                }

                array.push $skipped_detail {
                  value = {stage_key: $upd.stage_key, lens_key: $upd.lens_key, reason: "confirmed"}
                }
              }

              else {
                // RES-6-01: atomic per-cell write with failure capture into failed[].
                try_catch {
                  try {
                    // SAFE-1: the one keep-or-clear rule.
                    function.run "journey/cell_merge_patch" {
                      input = {cell: $cell, patch: $upd}
                    } as $merged

                    db.transaction {
                      stack {
                        db.patch journey_cell {
                          field_name = "id"
                          field_value = $cell.id
                          data = {
                            content            : $merged.data.content
                            actor_fields       : $merged.data.actor_fields
                            time_duration_value: $merged.data.time_duration_value
                            time_duration_unit : $merged.data.time_duration_unit
                            planned_duration   : $merged.data.planned_duration
                            actual_duration    : $merged.data.actual_duration
                            status             : "draft"
                            change_source      : "ai"
                            updated_at         : "now"
                          }
                        } as $patched_cell
                      }
                    }

                    var.update $written {
                      value = $written + 1
                    }
                  }

                  catch {
                    array.push $failed {
                      value = {
                        stage_key: $upd.stage_key
                        lens_key : $upd.lens_key
                        reason   : "write_error"
                        error    : $error.message
                      }
                    }

                    var.update $failed_count {
                      value = $failed_count + 1
                    }
                  }
                }
              }
            }
          }

          else {
            var.update $skipped {
              value = $skipped + 1
            }

            array.push $skipped_detail {
              value = {stage_key: $upd.stage_key, lens_key: $upd.lens_key, reason: "not_found"}
            }
          }
        }
      }
    }

    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $map_touch

    // US-RES-8-02: batch write metrics.
    db.add event_log {
      enforce_hidden_fields = false
      data = {
        created_at: "now"
        action    : "telemetry:fill_cells"
        metadata  : {
        journey_map_id: $input.journey_map_id
        cells_written : $written
        cells_skipped : $skipped
      }
      }
    } as $_ftelem
  }

  response = {
    journey_map_id: $input.journey_map_id
    written       : $written
    skipped       : $skipped
    skipped_detail: $skipped_detail
    failed        : $failed
    failed_count  : $failed_count
  }
  guid = "3rC1w0U6nIEjfX8zYNZKS_gLK-s"
}
