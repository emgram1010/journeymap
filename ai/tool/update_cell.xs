// Updates a single journey map cell identified by stage_key + lens_key.
// Respects is_locked — returns a skip result instead of writing if locked.
// SAFE-1 (2026-11-21): a field that was not sent is kept. The old patch wrote
// `$input.content ?? $cell.content`, but an omitted optional text arrives as "" and an omitted
// decimal as 0, and `??` keeps both — so a times-only call wiped the text and a text-only call
// zeroed the times. What was sent is now read from the raw request and merged by the one shared
// rule, journey/cell_merge_patch.
tool update_cell {
  instructions = """
      Use this tool to write content into a specific cell identified by its stage_key and lens_key.
      The tool resolves the target cell by joining stage and lens keys — do NOT pass cell IDs.
    
      The cell will be updated with change_source 'ai' and status 'draft'.
      If the target cell is locked (is_locked=true), the update is skipped and a skip result is returned.
      If the target cell has status 'confirmed', the update is skipped to protect user-confirmed content.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_key: The key of the target stage (e.g. 'awareness', 'consideration')
      - lens_key: The key of the target lens (e.g. 'goals', 'touchpoints')
      - content: The text content to write into the cell (optional — omit to update only time fields)
      Rule for every optional field: leave it out (or send null) to KEEP what is stored; send
      an empty string "" to CLEAR the text; a sent 0 is stored as 0. If nothing is sent, nothing
      is written and skip_reason is 'nothing_to_change'.
      - time_duration_value: (optional) decimal — planned time the actor spends at this stage
      - time_duration_unit: (optional) enum — minutes | hours | days | weeks
      - planned_duration: (optional) decimal — SOP/target time for this stage (same unit as time_duration_unit)
      - actual_duration: (optional) decimal — real observed time for this stage; gap vs planned is the leakage signal

      Response shape:
      {
        applied: true/false,
        cell: { id, stage_key, lens_key, content, status, is_locked, change_source, time_duration_value, time_duration_unit, planned_duration, actual_duration },
        skip_reason: null | 'locked' | 'confirmed' | 'not_found' | 'nothing_to_change',
        fields_set: [names of the fields this call wrote]
      }
    """

  input {
    // The ID of the journey map containing the cell.
    int journey_map_id filters=min:1
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
  
    // The key of the stage (column) for the target cell.
    text stage_key filters=trim
  
    // The key of the lens (row) for the target cell.
    text lens_key filters=trim
  
    // The text content to write into the cell (optional — omit to update only time fields).
    text content? filters=trim

    // Planned time this actor spends at this stage (optional — leakage math input).
    decimal time_duration_value?

    // Unit for time_duration_value.
    enum time_duration_unit? {
      values = ["minutes", "hours", "days", "weeks"]
    }

    // SOP/target time for this stage — used in plan vs actual leakage gap.
    decimal planned_duration?

    // Real observed time for this stage — gap vs planned_duration is the leakage signal.
    decimal actual_duration?

    // COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty.
    text ticket? filters=trim
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "update_cell", kind: "write"}
    } as $cop1_gate

    // SAFE-1: what the caller really sent. $input cannot tell "left out" from "" or 0.
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    // Resolve the stage by key within this journey map
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
      return = {type: "single"}
    } as $stage
  
    // Resolve the lens by key within this journey map
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
      return = {type: "single"}
    } as $lens
  
    var $result {
      value = {applied: false, cell: null, skip_reason: "not_found"}
    }
  
    conditional {
      if ($stage != null && $lens != null) {
        // Find the cell at the stage×lens intersection
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
          return = {type: "single"}
        } as $cell
      
        conditional {
          if ($cell == null) {
            var.update $result {
              value = {applied: false, cell: null, skip_reason: "not_found"}
            }
          }
        
          elseif ($cell.is_locked) {
            var.update $result {
              value = {
                applied    : false
                cell       : {
                  id           : $cell.id
                  stage_key    : $input.stage_key
                  lens_key     : $input.lens_key
                  content      : $cell.content
                  status       : $cell.status
                  is_locked    : $cell.is_locked
                  change_source: $cell.change_source
                }
                skip_reason: "locked"
              }
            }
          }
        
          elseif ($cell.status == "confirmed") {
            var.update $result {
              value = {
                applied    : false
                cell       : {
                  id           : $cell.id
                  stage_key    : $input.stage_key
                  lens_key     : $input.lens_key
                  content      : $cell.content
                  status       : $cell.status
                  is_locked    : $cell.is_locked
                  change_source: $cell.change_source
                }
                skip_reason: "confirmed"
              }
            }
          }
        
          else {
            // SAFE-1: the one keep-or-clear rule. Only this tool's own five fields are picked
            // (actor_fields is not one of them, so it is never written here). A left-out key
            // becomes null here, and the shared rule keeps the stored value for null.
            var $sent {
              value = {
                content            : ($raw_input|get:"content":null)
                time_duration_value: ($raw_input|get:"time_duration_value":null)
                time_duration_unit : ($raw_input|get:"time_duration_unit":null)
                planned_duration   : ($raw_input|get:"planned_duration":null)
                actual_duration    : ($raw_input|get:"actual_duration":null)
              }
            }

            function.run "journey/cell_merge_patch" {
              input = {cell: $cell, patch: $sent}
            } as $merged

            var $fields_set {
              value = $merged.fields_set
            }

            conditional {
              if ($merged.set_count == 0) {
                var.update $result {
                  value = {applied: false, cell: null, skip_reason: "nothing_to_change", fields_set: []}
                }
              }

              else {
                db.patch journey_cell {
                  field_name = "id"
                  field_value = $cell.id
                  data = {
                    content            : $merged.data.content
                    status             : "draft"
                    change_source      : "ai"
                    updated_at         : "now"
                    last_updated_at    : "now"
                    time_duration_value: $merged.data.time_duration_value
                    time_duration_unit : $merged.data.time_duration_unit
                    planned_duration   : $merged.data.planned_duration
                    actual_duration    : $merged.data.actual_duration
                  }
                } as $updated_cell

                // OBS-1: one success event per write. No cell text in the event.
                db.add event_log {
                  enforce_hidden_fields = false
                  data = {
                    created_at: "now"
                    action    : "cell.updated"
                    metadata  : {journey_map_id: $input.journey_map_id, cell_id: $cell.id, tool: "update_cell", fields_set: $fields_set}
                  }
                } as $_cell_event

                var.update $result {
                  value = {
                    applied    : true
                    cell       : {
                      id                  : $updated_cell.id
                      stage_key           : $input.stage_key
                      lens_key            : $input.lens_key
                      content             : $updated_cell.content
                      status              : $updated_cell.status
                      is_locked           : $updated_cell.is_locked
                      change_source       : $updated_cell.change_source
                      time_duration_value : $updated_cell.time_duration_value
                      time_duration_unit  : $updated_cell.time_duration_unit
                      planned_duration    : $updated_cell.planned_duration
                      actual_duration     : $updated_cell.actual_duration
                    }
                    skip_reason: null
                    fields_set : $fields_set
                  }
                }
              }
            }
          }
        }
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "update_cell"
            tool_category : "write"
            input_summary : $input.stage_key ~ " × " ~ $input.lens_key
            output_summary: $result.applied ? "Applied" : "Skipped: " ~ $result.skip_reason
          }
        } as $tool_log
      }
    }
  }

  response = $result
  guid = "LYVQ2a9fLK0u8U1Edrur3X42Rtw"
}