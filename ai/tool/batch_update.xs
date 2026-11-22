// Updates multiple journey map cells in one call. Skips locked and confirmed cells.
// SAFE-1 (2026-11-21): rebuilt from the LIVE source (the local file was behind live: it lacked
// RES-6's per-cell try_catch and RES-8's telemetry). The patch wrote `content: $upd.content`
// with no fallback, so an update without a content key wiped (or failed on) the text. Content
// now goes through the one keep-or-clear rule, journey/cell_merge_patch.
tool batch_update {
  instructions = """
      Use this tool when you need to write content into multiple cells at once,
      such as after a multi-topic interview answer.

      Each update is identified by stage_key + lens_key. Locked and confirmed cells are
      skipped automatically. All successful writes set change_source='ai' and status='draft'.
      Leave content out (or send null) to keep a cell's text; send "" to clear it.

      Input:
      - journey_map_id: The ID of the journey map
      - updates: A JSON array of objects, each with { stage_key, lens_key, content }

      Response shape:
      {
        applied: [ { stage_key, lens_key, cell_id, content } ],
        skipped: [ { stage_key, lens_key, reason } ],
        applied_count: int,
        skipped_count: int
      }
    """

  input {
    // The ID of the journey map containing the cells.
    int journey_map_id filters=min:1

    // Optional: for tool trace logging (transparency layer).
    int conversation_id?

    text turn_id?

    // Array of { stage_key, lens_key, content } objects to apply.
    json updates

    // COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty.
    text ticket? filters=trim
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {
        journey_map_id: $input.journey_map_id
        ticket        : $input.ticket
        tool          : "batch_update"
        kind          : "write"
      }
    } as $cop1_gate

    // RES-6-04: hard cap on batch size to bound execution time and memory.
    precondition ($input.updates == null || ($input.updates|count) <= 500) {
      error_type = "inputerror"
      error = "Batch too large — max 500 updates per call. Split into multiple calls."
    }

    // Load all stages, lenses, and cells once — build dicts for O(1) in-loop lookup
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $all_cells

    var $stage_by_key {
      value = {}
    }

    foreach ($stages) {
      each as $s {
        var.update $stage_by_key {
          value = $stage_by_key|set:$s.key:$s
        }
      }
    }

    var $lens_by_key {
      value = {}
    }

    foreach ($lenses) {
      each as $l {
        var.update $lens_by_key {
          value = $lens_by_key|set:$l.key:$l
        }
      }
    }

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

    var $applied {
      value = []
    }

    var $skipped {
      value = []
    }

    var $applied_count {
      value = 0
    }

    var $skipped_count {
      value = 0
    }

    // RES-6-03: additive failure surface.
    var $failed {
      value = []
    }

    var $failed_count {
      value = 0
    }

    foreach ($input.updates) {
      each as $upd {
        // Resolve stage and lens from pre-loaded dicts — no per-item DB queries
        var $stage {
          value = $stage_by_key|get:$upd.stage_key
        }

        var $lens {
          value = $lens_by_key|get:$upd.lens_key
        }

        conditional {
          if ($stage == null || $lens == null) {
            array.push $skipped {
              value = {
                stage_key: $upd.stage_key
                lens_key : $upd.lens_key
                reason   : "not_found"
              }
            }

            var.update $skipped_count {
              value = $skipped_count + 1
            }
          }

          else {
            // Resolve cell from pre-loaded dict — no per-item DB query
            var $cell_key {
              value = ($stage.id|to_text) ~ "_" ~ ($lens.id|to_text)
            }

            var $cell {
              value = $cell_map|get:$cell_key
            }

            conditional {
              if ($cell == null) {
                array.push $skipped {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    reason   : "not_found"
                  }
                }

                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }

              elseif ($cell.is_locked) {
                array.push $skipped {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    reason   : "locked"
                  }
                }

                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }

              elseif ($cell.status == "confirmed") {
                array.push $skipped {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    reason   : "confirmed"
                  }
                }

                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }

              else {
                // RES-6-01: atomic per-cell write with failure capture into failed[].
                try_catch {
                  try {
                    // SAFE-1: only content is this tool's field. Picking it with |get turns a
                    // left-out key into null, which the shared rule keeps.
                    var $sent {
                      value = {content: ($upd|get:"content":null)}
                    }

                    function.run "journey/cell_merge_patch" {
                      input = {cell: $cell, patch: $sent}
                    } as $merged

                    db.transaction {
                      stack {
                        db.patch journey_cell {
                          field_name = "id"
                          field_value = $cell.id
                          data = {
                            content        : $merged.data.content
                            status         : "draft"
                            change_source  : "ai"
                            updated_at     : "now"
                            last_updated_at: "now"
                          }
                        } as $updated_cell
                      }
                    }

                    array.push $applied {
                      value = {
                        stage_key: $upd.stage_key
                        lens_key : $upd.lens_key
                        cell_id  : $cell.id
                        content  : $merged.data.content
                      }
                    }

                    var.update $applied_count {
                      value = $applied_count + 1
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
        }
      }
    }

    // Touch the journey map timestamp once after all updates
    conditional {
      if ($applied_count > 0) {
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $map_touch
      }
    }

    // US-RES-8-02: batch write metrics.
    db.add event_log {
      enforce_hidden_fields = false
      data = {
        created_at: "now"
        action    : "telemetry:batch_update"
        metadata  : {
        journey_map_id: $input.journey_map_id
        cells_applied : $applied_count
        cells_skipped : $skipped_count
      }
      }
    } as $_btelem

    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "batch_update"
            tool_category : "write"
            input_summary : $applied_count ~ " cells targeted"
            output_summary: $applied_count ~ " applied, " ~ $skipped_count ~ " skipped"
          }
        } as $tool_log
      }
    }
  }

  response = {
    applied      : $applied
    skipped      : $skipped
    applied_count: $applied_count
    skipped_count: $skipped_count
    failed       : $failed
    failed_count : $failed_count
  }
  guid = "t2Ykf_GhwtHa9p2MxPfJLQeu3hA"
}
