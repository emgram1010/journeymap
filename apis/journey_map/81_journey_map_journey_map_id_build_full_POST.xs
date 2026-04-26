// Server-side multi-turn build loop for the Journey Map Assistant.
// Runs [CONTINUE_BUILD] turns autonomously until the map is complete, stalled,
// or max_turns is reached. Designed for MCP callers and server-side integrations
// that have no frontend to drive the continuation loop.
// US-BIM-02
query "journey_map/{journey_map_id}/build_full" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1

    // Optional domain context injected into the first build prompt.
    text context? filters=trim

    // Maximum number of agent turns to run. Default 8.
    int max_turns?
  }

  stack {
    // ── Defaults ──
    var $resolved_max_turns {
      value = $input.max_turns != null ? $input.max_turns : 8
    }

    // ── Validate map exists and belongs to this user ──
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

    // ── Create a dedicated conversation for this build run ──
    db.add agent_conversation {
      data = {
        created_at     : "now"
        journey_map    : $input.journey_map_id
        title          : "Build Full — " ~ $journey_map.title
        mode           : "interview"
        last_message_at: "now"
      }
    } as $conversation

    // ── Build loop state ──
    var $turns_used       { value = 0 }
    var $total_cells_filled { value = 0 }
    var $stall_count      { value = 0 }
    var $loop_status      { value = "running" }
    var $tool_trace_summary { value = [] }
    var $skipped_cells    { value = [] }

    // ── Build the first user message ──
    var $context_suffix {
      value = ""
    }

    conditional {
      if ($input.context != null && $input.context != "") {
        var.update $context_suffix {
          value = " Context: " ~ $input.context
        }
      }
    }

    var $first_message {
      value = "Build the full journey map." ~ $context_suffix
    }

    // ── Seed message history ──
    var $agent_messages {
      value = [{role: "user", content: $first_message}]
    }

    // ── Main loop ──
    var $loop_idx { value = 0 }

    repeat {
      while = $loop_status == "running"

      stack {
        var $turn_id {
          value = "build_full_" ~ $input.journey_map_id ~ "_t" ~ $loop_idx
        }

        // Run one agent turn
        var $agent_run { value = null }
        var $agent_error { value = null }

        try_catch {
          try {
            ai.agent.run "Journey Map Assistant" {
              args = {}|set:"messages":$agent_messages
              allow_tool_execution = true
            } as $agent_run
          }
          catch {
            var.update $agent_error { value = $error.message }
          }
        }

        // ── Count cells written this turn ──
        db.query agent_tool_log {
          where = $db.agent_tool_log.conversation == $conversation.id
            AND $db.agent_tool_log.turn_id == $turn_id
          return = {type: "list"}
        } as $turn_logs

        var $turn_cells_written { value = 0 }
        var $turn_skips         { value = 0 }

        foreach ($turn_logs) {
          each as $tl {
            conditional {
              if ($tl.tool_category == "write") {
                conditional {
                  if ($tl.output_summary|starts_with:"Applied") {
                    var.update $turn_cells_written { value = $turn_cells_written + 1 }
                  }
                }
                conditional {
                  if ($tl.output_summary|starts_with:"Skipped") {
                    var.update $turn_skips { value = $turn_skips + 1 }
                    array.push $skipped_cells {
                      value = {
                        tool    : $tl.tool_name
                        target  : $tl.input_summary
                        reason  : $tl.output_summary
                      }
                    }
                  }
                }
              }
            }
          }
        }

        var.update $total_cells_filled {
          value = $total_cells_filled + $turn_cells_written
        }

        // Record turn summary
        array.push $tool_trace_summary {
          value = {
            turn          : $loop_idx + 1
            tools_called  : $turn_logs|count
            cells_written : $turn_cells_written
            skips         : $turn_skips
          }
        }

        // ── Stall detection ──
        conditional {
          if ($turn_cells_written == 0) {
            var.update $stall_count { value = $stall_count + 1 }
          }
          else {
            var.update $stall_count { value = 0 }
          }
        }

        var.update $turns_used { value = $turns_used + 1 }
        var.update $loop_idx   { value = $loop_idx + 1 }

        // ── Check progress via get_gaps ──
        tool.call get_gaps {
          input = {journey_map_id: $input.journey_map_id}
        } as $gaps_check

        var $remaining_gaps {
          value = $gaps_check.total_gaps
        }

        // ── Compute progress percentage ──
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id
          return = {type: "list"}
        } as $all_cells

        var $total_count { value = $all_cells|count }
        var $progress_pct {
          value = $total_count > 0 ? (($total_count - $remaining_gaps) * 100) / $total_count : 100
        }

        // ── Exit conditions ──
        conditional {
          if ($progress_pct >= 95) {
            var.update $loop_status { value = "complete" }
          }
          elseif ($stall_count >= 2) {
            var.update $loop_status { value = "stalled" }
          }
          elseif ($turns_used >= $resolved_max_turns) {
            var.update $loop_status { value = "partial" }
          }
          else {
            // ── Set up next continuation message ──
            var.update $agent_messages {
              value = [{role: "user", content: "[CONTINUE_BUILD] Continue filling empty cells. Call get_gaps first, then fill the next batch."}]
            }
          }
        }
      }
    }

    // ── Final progress snapshot ──
    tool.call get_gaps {
      input = {journey_map_id: $input.journey_map_id}
    } as $final_gaps

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $final_cells

    var $final_total   { value = $final_cells|count }
    var $final_remaining { value = $final_gaps.total_gaps }
    var $final_filled  { value = $final_total - $final_remaining }
    var $final_pct     {
      value = $final_total > 0 ? ($final_filled * 100) / $final_total : 100
    }

    // ── Update conversation timestamp ──
    db.patch agent_conversation {
      field_name  = "id"
      field_value = $conversation.id
      data        = {last_message_at: "now"}
    } as $conv_update
  }

  response = {
    status             : $loop_status
    turns_used         : $turns_used
    cells_filled       : $final_filled
    cells_remaining    : $final_remaining
    progress_percentage: $final_pct
    skipped_cells      : $skipped_cells
    tool_trace_summary : $tool_trace_summary
    conversation_id    : $conversation.id
  }
}
