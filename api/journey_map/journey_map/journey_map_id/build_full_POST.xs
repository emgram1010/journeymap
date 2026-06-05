//  Server-side multi-turn build loop for the Journey Map Assistant.
//  Runs phase-queue turns autonomously until the map is complete, stalled,
//  or max_turns is reached. Designed for MCP callers and server-side integrations
//  that have no frontend to drive the continuation loop.
//  US-BIM-02
// 
//  ── ARO-07: Diagnostic workflow ──────────────────────────────────────────────
//  When a build produces unexpected results (wrong % complete, missing lenses,
//  empty cells), run these three calls in order to root-cause the issue:
// 
//  1. GET /journey_map/{id}/turn-logs
//     → Shows which phases ran, tool counts, cells written, and step limit warnings.
//     → If tools_called == 0 for a phase: system context was missing or prompt rejected.
//     → If cells_written == 0 but tools_called > 0: agent called get_map_state only,
//       did not proceed to write — check for a scope fence conflict or already-filled cells.
// 
//  2. GET /journey_map/{id}/tool-logs?turn_id={turn_id_from_step_1}
//     → Per-tool detail: what was called, what was passed, what was returned.
//     → output_summary starts with "Skipped" → cell was locked or confirmed, not a bug.
//     → output_summary starts with "Applied" → cell was written successfully.
//     → Empty output_summary → tool errored silently; check input_summary for bad stage/lens key.
// 
//  3. GET /journey_map/load_bundle/{id}
//     → Current map state: stage labels, lens labels, cell content + actor_fields.
//     → Stage labels still "Stage 1/2/3..." → scaffold phase didn't run or failed.
//     → Lens actor_type empty on a lens that should be actor-typed → identity phase skipped.
//     → content == "" on a non-actor cell → description/structural phase missed that cell.
//     → actor_fields == {} on an actor cell → customer/internal/metrics phase missed that cell.
// 
//  Common root causes and fixes:
//    tools_called == 0 on phase 0 (scaffold) → journey_map_id not in system context
//    status == "stalled" after 2 turns      → stall counter hitting non-fill phases (ARO-02)
//    progress_percentage stuck at 55%       → fill counter ignoring actor_fields (ARO-09)
//    agent writes to wrong lens             → phase prompt missing scope fence (ARO-04)
//  ─────────────────────────────────────────────────────────────────────────────
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
      enforce_hidden_fields = false
      data = {
        created_at     : "now"
        journey_map    : $input.journey_map_id
        title          : "Build Full — " ~ $journey_map.title
        mode           : "interview"
        last_message_at: "now"
      }
    } as $conversation
  
    // ── Build loop state ──
    var $turns_used {
      value = 0
    }
  
    var $total_cells_filled {
      value = 0
    }
  
    var $stall_count {
      value = 0
    }
  
    var $loop_status {
      value = "running"
    }
  
    var $tool_trace_summary {
      value = []
    }
  
    var $skipped_cells {
      value = []
    }
  
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
  
    // ── Phase queue (BPC-06) ──
    // Phases 0-1 and 7 use Journey Map Assistant (reasoning ON).
    // Phases 2-6 use Journey Map Builder (reasoning OFF, max_steps 15) for speed.
    var $phase_prompts {
      value = [
        "[BUILD_PHASE:scaffold] Scaffold stages and lenses only. DO NOT fill any cells. DO NOT call batch_update or update_actor_cell_fields. Report what you created."
        "[BUILD_PHASE:identity] Fill actor identity fields (persona_description, primary_goal, standing_constraints) for all actor lenses using update_actor_identity only. DO NOT call batch_update. DO NOT write to any cells."
        "[BUILD_PHASE:description] Fill the Description lens ONLY across all stages. Use batch_update only. DO NOT call update_actor_cell_fields. DO NOT touch any other lens."
        "[BUILD_PHASE:customer] Fill Customer actor lenses ONLY (actor_type=customer) across all stages. Use update_actor_cell_fields only. DO NOT call batch_update. DO NOT touch non-customer lenses."
        "[BUILD_PHASE:internal] Fill Internal actor lenses ONLY (actor_type=internal) across all stages. Use update_actor_cell_fields only. DO NOT call batch_update. DO NOT touch non-internal lenses."
        "[BUILD_PHASE:structural] Fill structural lenses ONLY (Top Pain Point, Key Variable, Cascade Risk, Systems — actor_type empty) across all stages. Use batch_update only. DO NOT call update_actor_cell_fields. DO NOT touch actor lenses."
        "[BUILD_PHASE:metrics] Fill Metrics and Financial actor lenses ONLY (actor_type=metrics or actor_type=financial) across all stages. Use update_actor_cell_fields only. DO NOT call batch_update. DO NOT touch non-metrics lenses."
        "[BUILD_PHASE:verify] Run cross-lens consistency check ONLY. Call get_map_state. Surface inconsistencies only. DO NOT call any write tools (batch_update, update_actor_cell_fields, mutate_structure, scaffold_structure)."
      ]
    }
  
    var $phase_keys {
      value = [
        "scaffold"
        "identity"
        "description"
        "customer"
        "internal"
        "structural"
        "metrics"
        "verify"
      ]
    }
  
    // Indices of phases that use the fast builder agent (no reasoning)
    var $builder_phase_indices {
      value = [2, 3, 4, 5, 6]
    }
  
    // ── Query initial map structure for system context ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $init_stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $init_lenses
  
    // ── Build base system context (journey_map_id is critical for all tool calls) ──
    var $stage_summary {
      value = ""
    }
  
    foreach ($init_stages) {
      each as $st {
        var.update $stage_summary {
          value = $stage_summary ~ "- " ~ $st.key ~ ": " ~ $st.label ~ "\n"
        }
      }
    }
  
    var $lens_summary {
      value = ""
    }
  
    foreach ($init_lenses) {
      each as $ln {
        var.update $lens_summary {
          value = $lens_summary ~ "- " ~ $ln.key ~ " [" ~ $ln.actor_type ~ "]: " ~ $ln.label ~ "\n"
        }
      }
    }
  
    var $base_system_context {
      value = "You are the Journey Map Assistant running in autonomous build mode. You MUST use tools to build the journey map — do not just respond with text.\n\n## Journey Map\nID: " ~ ($input.journey_map_id|to_text) ~ "\nTitle: " ~ $journey_map.title ~ "\n\n## Current Stages\n" ~ $stage_summary ~ "\n## Current Lenses\n" ~ $lens_summary ~ "\n\n### Tool Logging (pass to every tool call)\n- journey_map_id: " ~ ($input.journey_map_id|to_text)
    }
  
    // ── Main loop ──
    var $loop_idx {
      value = 0
    }
  
    // First phase message: scaffold prompt (skip $first_message — go straight to phases)
    var $current_phase_message {
      value = $phase_prompts[0] ~ " " ~ $first_message
    }
  
    while ($loop_status == "running") {
      each {
        var $turn_id {
          value = "build_full_" ~ $input.journey_map_id ~ "_t" ~ $loop_idx
        }
      
        // Determine which agent to use for this phase
        var $use_builder_agent {
          value = $builder_phase_indices|contains:$loop_idx
        }
      
        // ── Build messages array with system context injected per turn ──
        var $system_ctx {
          value = $base_system_context ~ "\n- conversation_id: " ~ $conversation.id ~ "\n- turn_id: " ~ $turn_id
        }
      
        var $agent_messages {
          value = [
            {role: "system", content: $system_ctx}
            {role: "user", content: $current_phase_message}
          ]
        }
      
        // Run one agent turn
        var $agent_run {
          value = null
        }
      
        var $agent_error {
          value = null
        }
      
        try_catch {
          try {
            conditional {
              if ($use_builder_agent) {
                ai.agent.run "Journey Map Builder" {
                  args = {}|set:"messages":$agent_messages
                  allow_tool_execution = true
                } as $agent_run
              }
            
              else {
                ai.agent.run "" {
                  args = {}|set:"messages":$agent_messages
                  allow_tool_execution = true
                } as $agent_run
              }
            }
          }
        
          catch {
            var.update $agent_error {
              value = $error.message
            }
          }
        }
      
        // ── Count cells written this turn ──
        db.query agent_tool_log {
          where = $db.agent_tool_log.conversation == $conversation.id && $db.agent_tool_log.turn_id == $turn_id
          return = {type: "list"}
        } as $turn_logs
      
        var $turn_cells_written {
          value = 0
        }
      
        var $turn_skips {
          value = 0
        }
      
        foreach ($turn_logs) {
          each as $tl {
            conditional {
              if ($tl.tool_category == "write") {
                conditional {
                  if ($tl.output_summary|starts_with:"Applied") {
                    var.update $turn_cells_written {
                      value = $turn_cells_written + 1
                    }
                  }
                }
              
                conditional {
                  if ($tl.output_summary|starts_with:"Skipped") {
                    var.update $turn_skips {
                      value = $turn_skips + 1
                    }
                  
                    array.push $skipped_cells {
                      value = {
                        tool  : $tl.tool_name
                        target: $tl.input_summary
                        reason: $tl.output_summary
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
      
        // Record turn summary with phase_key
        array.push $tool_trace_summary {
          value = {
            turn         : $loop_idx + 1
            phase_key    : $phase_keys[$loop_idx]
            tools_called : $turn_logs|count
            cells_written: $turn_cells_written
            skips        : $turn_skips
          }
        }
      
        // ── Stall detection ──
        // Phases 0 (scaffold) and 1 (identity) write 0 cells by design — exclude them.
        // Only count stalls for fill phases (index >= 2).
        conditional {
          if ($turn_cells_written == 0 && $loop_idx >= 2) {
            var.update $stall_count {
              value = $stall_count + 1
            }
          }
        
          else {
            var.update $stall_count {
              value = 0
            }
          }
        }
      
        var.update $turns_used {
          value = $turns_used + 1
        }
      
        var.update $loop_idx {
          value = $loop_idx + 1
        }
      
        // ── Check progress: count empty cells inline ──
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id
          return = {type: "list"}
        } as $all_cells
      
        // ARO-09: build lens→actor_type map so actor cells are counted correctly
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id
          return = {type: "list"}
        } as $all_lenses_prog
      
        var $lens_actor_map_prog {
          value = {}
        }
      
        foreach ($all_lenses_prog) {
          each as $lp {
            var.update $lens_actor_map_prog {
              value = $lens_actor_map_prog
                |set:($lp.id|to_text):$lp.actor_type
            }
          }
        }
      
        var $total_count {
          value = $all_cells|count
        }
      
        var $empty_count {
          value = 0
        }
      
        foreach ($all_cells) {
          each as $cell {
            var $cp_actor_type {
              value = $lens_actor_map_prog|get:($cell.lens|to_text)
            }
          
            var $cp_is_empty {
              value = false
            }
          
            conditional {
              if ($cp_actor_type != null && $cp_actor_type != "") {
                // Actor cell: empty when actor_fields has no real values
                conditional {
                  if ($cell.actor_fields == null || ($cell.actor_fields|count) == 0) {
                    var.update $cp_is_empty {
                      value = true
                    }
                  }
                }
              
                conditional {
                  if ($cell.actor_fields != null && ($cell.actor_fields|count) > 0) {
                    var $cp_af_keys {
                      value = $cell.actor_fields|keys
                    }
                  
                    var $cp_has_real {
                      value = false
                    }
                  
                    foreach ($cp_af_keys) {
                      each as $cpfk {
                        var $cpfv {
                          value = $cell.actor_fields|get:$cpfk
                        }
                      
                        conditional {
                          if ($cpfv != null && $cpfv != "") {
                            var.update $cp_has_real {
                              value = true
                            }
                          }
                        }
                      }
                    }
                  
                    conditional {
                      if ($cp_has_real == false) {
                        var.update $cp_is_empty {
                          value = true
                        }
                      }
                    }
                  }
                }
              }
            
              else {
                // Non-actor cell: empty when content is absent
                var.update $cp_is_empty {
                  value = $cell.content == null || $cell.content == ""
                }
              }
            }
          
            conditional {
              if ($cp_is_empty) {
                var.update $empty_count {
                  value = $empty_count + 1
                }
              }
            }
          }
        }
      
        var $remaining_gaps {
          value = $empty_count
        }
      
        var $progress_pct {
          value = $total_count > 0 ? (($total_count - $remaining_gaps) * 100) / $total_count : 100
        }
      
        // ── Exit conditions ──
        conditional {
          if ($progress_pct >= 95) {
            var.update $loop_status {
              value = "complete"
            }
          }
        
          elseif ($stall_count >= 2) {
            var.update $loop_status {
              value = "stalled"
            }
          }
        
          elseif ($loop_idx >= ($phase_prompts|count)) {
            // All 8 phases done
            var.update $loop_status {
              value = "complete"
            }
          }
        
          elseif ($turns_used >= $resolved_max_turns) {
            var.update $loop_status {
              value = "partial"
            }
          }
        
          else {
            // ── Set up next phase message ──
            var.update $current_phase_message {
              value = $phase_prompts[$loop_idx]
            }
          }
        }
      }
    }
  
    // ── Final progress snapshot ──
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $final_cells
  
    // ARO-09: lens→actor_type map for accurate final fill count
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $final_lenses
  
    var $final_lens_actor_map {
      value = {}
    }
  
    foreach ($final_lenses) {
      each as $fl {
        var.update $final_lens_actor_map {
          value = $final_lens_actor_map
            |set:($fl.id|to_text):$fl.actor_type
        }
      }
    }
  
    var $final_total {
      value = $final_cells|count
    }
  
    var $final_empty {
      value = 0
    }
  
    foreach ($final_cells) {
      each as $fc {
        var $fc_actor_type {
          value = $final_lens_actor_map|get:($fc.lens|to_text)
        }
      
        var $fc_is_empty {
          value = false
        }
      
        conditional {
          if ($fc_actor_type != null && $fc_actor_type != "") {
            // Actor cell: empty when actor_fields has no real values
            conditional {
              if ($fc.actor_fields == null || ($fc.actor_fields|count) == 0) {
                var.update $fc_is_empty {
                  value = true
                }
              }
            }
          
            conditional {
              if ($fc.actor_fields != null && ($fc.actor_fields|count) > 0) {
                var $fc_af_keys {
                  value = $fc.actor_fields|keys
                }
              
                var $fc_has_real {
                  value = false
                }
              
                foreach ($fc_af_keys) {
                  each as $fcfk {
                    var $fcfv {
                      value = $fc.actor_fields|get:$fcfk
                    }
                  
                    conditional {
                      if ($fcfv != null && $fcfv != "") {
                        var.update $fc_has_real {
                          value = true
                        }
                      }
                    }
                  }
                }
              
                conditional {
                  if ($fc_has_real == false) {
                    var.update $fc_is_empty {
                      value = true
                    }
                  }
                }
              }
            }
          }
        
          else {
            // Non-actor cell: empty when content is absent
            var.update $fc_is_empty {
              value = $fc.content == null || $fc.content == ""
            }
          }
        }
      
        conditional {
          if ($fc_is_empty) {
            var.update $final_empty {
              value = $final_empty + 1
            }
          }
        }
      }
    }
  
    var $final_remaining {
      value = $final_empty
    }
  
    var $final_filled {
      value = $final_total - $final_remaining
    }
  
    var $final_pct {
      value = $final_total > 0 ? ($final_filled * 100) / $final_total : 100
    }
  
    // ── Update conversation timestamp ──
    db.patch agent_conversation {
      field_name = "id"
      field_value = $conversation.id
      data = {last_message_at: "now"}
    } as $conv_patched
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

  guid = "rhR2PRz4N2WcoHdm7SNjfWWq-kU"
}