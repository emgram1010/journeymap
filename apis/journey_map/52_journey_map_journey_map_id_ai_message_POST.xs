// Calls Anthropic API with debug logging and error handling
query "journey_map/{journey_map_id}/ai_message" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int conversation_id?
    text content? filters=trim
    text mode? filters=trim
    // US-WE-05: set to true to route to the Orchestrator agent (bypasses mode enum constraint)
    bool orchestrator_mode?
  
    json selected_cell?
    json journey_settings?
    json parent_context?
  
    // When true, routes to Journey Map Builder (reasoning:false, max_steps:15)
    // Used for fill phases 2-6 in the phase queue build loop.
    bool builder_mode?

    // HUX-03: when true forces log_tier=full regardless of mode (debug payload capture).
    bool capture_payloads?

    // Specialist Mode: lens key of the active actor the AI should embody.
    text specialist_actor_key?

    // Consortium Mode: array of lens keys for the panel of active actors.
    json consortium_actor_keys?
  }

  stack {
    // â”€â”€ Validate inputs â”€â”€
    precondition ($input.content != null && $input.content != "") {
      error_type = "inputerror"
      error = "Message content is required"
    }
  
    precondition ($input.mode != null && $input.mode != "") {
      error_type = "inputerror"
      error = "Mode is required"
    }

    // Resolve effective mode: orchestrator_mode=true overrides the mode field (US-WE-05)
    var $effective_mode {
      value = $input.mode
    }

    conditional {
      if ($input.orchestrator_mode == true) {
        var.update $effective_mode {
          value = "orchestrator"
        }
      }
    }
  
    // â”€â”€ Load map bundle â”€â”€
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
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $lenses
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $cells
  
    // â”€â”€ Compute fill summary â”€â”€
    var $total_cells {
      value = $cells|count
    }
  
    var $filled_cells {
      value = 0
    }
  
    var $locked_cells {
      value = 0
    }
  
    var $confirmed_cells {
      value = 0
    }
  
    foreach ($cells) {
      each as $c {
        conditional {
          if ($c.content != null && $c.content != "") {
            var.update $filled_cells {
              value = $filled_cells + 1
            }
          }
        }
      
        conditional {
          if ($c.is_locked) {
            var.update $locked_cells {
              value = $locked_cells + 1
            }
          }
        }
      
        conditional {
          if ($c.status == "confirmed") {
            var.update $confirmed_cells {
              value = $confirmed_cells + 1
            }
          }
        }
      }
    }
  
    var $empty_cells {
      value = $total_cells - $filled_cells
    }
  
    // â”€â”€ Build stage and lens label lists for the system prompt â”€â”€
    var $stage_labels {
      value = []
    }
  
    foreach ($stages) {
      each as $st {
        // SGAC-01: start with "Label (key)"
        var $stage_entry {
          value = "%s (%s)"|sprintf:$st.label:$st.key
        }
      
        // Append stage goal if set
        conditional {
          if ($st.stage_goal != null && $st.stage_goal != "") {
            var.update $stage_entry {
              value = $stage_entry ~ " — Goal: " ~ $st.stage_goal
            }
          }
        }
      
        // Resolve primary_actor_lens key → lens label and append Owner
        conditional {
          if ($st.primary_actor_lens != null && $st.primary_actor_lens != "") {
            var $actor_label {
              value = ""
            }
          
            foreach ($lenses) {
              each as $ln {
                conditional {
                  if ($ln.key == $st.primary_actor_lens) {
                    var.update $actor_label {
                      value = $ln.label
                    }
                  }
                }
              }
            }
          
            conditional {
              if ($actor_label != "") {
                var.update $stage_entry {
                  value = $stage_entry ~ " | Owner: " ~ $actor_label
                }
              }
            }
          }
        }
      
        array.push $stage_labels {
          value = $stage_entry
        }
      }
    }
  
    var $lens_labels {
      value = []
    }
  
    // ARO-08: include actor_type so the agent can apply the correct write tool per row
    foreach ($lenses) {
      each as $ln {
        var $at_suffix {
          value = ""
        }

        conditional {
          if ($ln.actor_type != null && $ln.actor_type != "") {
            var.update $at_suffix {
              value = " [actor_type: " ~ $ln.actor_type ~ "]"
            }
          }
        }

        conditional {
          if ($ln.description != null && $ln.description != "") {
            array.push $lens_labels {
              value = "- **" ~ $ln.label ~ "** (" ~ $ln.key ~ ")" ~ $at_suffix ~ ": " ~ $ln.description
            }
          }

          else {
            array.push $lens_labels {
              value = "- " ~ $ln.label ~ " (" ~ $ln.key ~ ")" ~ $at_suffix
            }
          }
        }
      }
    }
  
    // â”€â”€ Build dynamic system prompt context â”€â”€
    var $dynamic_context {
      value = "\n\n## Current Map Context\n"
    }
  
    var.update $dynamic_context {
      value = $dynamic_context|concat:"- **Map title:** ":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context|concat:$journey_map.title:""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context|concat:"\n- **Map status:** ":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context|concat:$journey_map.status:""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n- **Active mode:** ":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context|concat:$effective_mode:""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n- **Journey Map ID:** ":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:($input.journey_map_id|to_text):""
    }
  
    // â”€â”€ Inject journey settings context if provided â”€â”€
    conditional {
      if ($input.journey_settings != null && ($input.journey_settings|is_empty) == false) {
        var $settings_section {
          value = "\n\n## Journey Settings\n"
        }
      
        var $settings_fields {
          value = [
            {key: "primary_actor",       label: "Primary Actor"}
            {key: "journey_scope",       label: "Journey Scope"}
            {key: "start_point",         label: "Start Point"}
            {key: "end_point",           label: "End Point"}
            {key: "duration",            label: "Duration"}
            {key: "success_metrics",     label: "Success Metrics"}
            {key: "key_stakeholders",    label: "Key Stakeholders"}
            {key: "dependencies",        label: "Dependencies & Assumptions"}
            {key: "pain_points_summary", label: "Pain Points Summary"}
            {key: "opportunities",       label: "Opportunities"}
            {key: "version",             label: "Version / Last Updated"}
          ]
        }
      
        foreach ($settings_fields) {
          each as $sf {
            var $sf_value {
              value = $input.journey_settings|get:$sf.key
            }
          
            conditional {
              if ($sf_value != null && $sf_value != "") {
                var.update $settings_section {
                  value = $settings_section
                    |concat:"- **":""
                    |concat:$sf.label:""
                    |concat:":** ":""
                    |concat:$sf_value:""
                    |concat:"\n":""
                }
              }
            }
          }
        }
      
        var.update $dynamic_context {
          value = $dynamic_context|concat:$settings_section:""
        }
      }
    }
  
    // â”€â”€ Inject smart AI behaviour settings directives â”€â”€
    // Use |get: filter throughout â€” dot notation throws a fatal error if the column doesn't exist yet.
    conditional {
      if ($journey_map|get:"smart_ai_settings" != null) {
        var $smart_section {
          value = "\n\n## Smart AI Behaviour\n"
        }
      
        var $has_smart_directive {
          value = false
        }
      
        // Interview Depth
        var $interview_depth {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"interview_depth"
        }
      
        conditional {
          if ($interview_depth == "strategic") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- At every stage, fully understand context before moving on. Explore upstream triggers, downstream consequences, and cross-functional connections. Do not advance until the current stage has solid, specific coverage across all populated lens rows.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        conditional {
          if ($interview_depth == "rapid_capture") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Move quickly across the map. Accept first-level answers. One question per area, then advance. Prioritise breadth over depth.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        // Insight Standard
        var $insight_standard {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"insight_standard"
        }
      
        conditional {
          if ($insight_standard == "surface") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Accept the user's stated answer and write it immediately. Do not probe or challenge. Prioritise capturing everything given, however brief.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        conditional {
          if ($insight_standard == "deep_dive") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Write the cell with the best available content, then follow up with a probing question to deepen it toward root cause. Use a 5-Whys approach in your follow-ups â€” always write first, enrich second. For pain points aim to surface across turns: WHAT + WHO + HOW OFTEN + DOWNSTREAM CONSEQUENCE â€” never as a gate before writing.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        // Emotional Mapping
        var $emotional_mapping {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"emotional_mapping"
        }
      
        conditional {
          if ($emotional_mapping) {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Write the factual cell content first. Then, before moving to the next topic, ask one follow-up to surface the emotional dimension: 'How does the customer feel at this exact moment â€” frustrated, uncertain, relieved, trusting?' If the user provides emotional context alongside their answer, capture both in the same write turn. Never withhold writing while waiting for emotional data.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        // Business Impact Framing
        var $business_impact_framing {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"business_impact_framing"
        }
      
        conditional {
          if ($business_impact_framing) {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Write the pain point cell with whatever content is available. Then ask the one follow-up that surfaces the missing impact dimension â€” frequency, severity, or downstream consequence â€” and enrich the cell on the next turn. Target structure across turns: [What] affects [Who] [How often], causing [Business consequence]. Never withhold writing a pain point cell while waiting for this structure.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        // Lens Priority
        var $lens_priority {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"lens_priority"
        }
      
        conditional {
          if ($lens_priority == "customer") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- When choosing which empty area to explore next, prioritise lens rows with actor_type: customer.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        conditional {
          if ($lens_priority == "operations") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Prioritise internal actor and handoff lens rows when deciding what to ask about next.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        conditional {
          if ($lens_priority == "engineering") {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Prioritise engineering lens rows when deciding what to ask about next.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        // Auto-Confirm Writes
        var $auto_confirm_writes {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"auto_confirm_writes"
        }
      
        conditional {
          if ($auto_confirm_writes) {
            var.update $smart_section {
              value = $smart_section
                |concat:"- Set cell status to 'confirmed' (not 'draft') for all AI writes this session.":""
            }
          
            var.update $has_smart_directive {
              value = true
            }
          }
        }
      
        // Neurodivergent Mode
        var $neurodivergent_mode {
          value = $journey_map
            |get:"smart_ai_settings"
            |get:"neurodivergent_mode"
        }

        conditional {
          if ($neurodivergent_mode) {
            var.update $smart_section {
              value = $smart_section
                |concat:"- OUTPUT FORMAT (Neurodivergent Mode ON): Lead with the answer in one sentence â€” no preamble. Follow with max 3 bullet points, each â‰¤ 15 words. One action item if relevant. Max one question at the end. NEVER use horizontal rules (---) or H1/H2 headers. Bold only the key decision or term â€” not full sentences. Hard cap: 120 words.":""
            }

            var.update $has_smart_directive {
              value = true
            }
          }
        }
        // Only append the section if at least one directive was injected
        conditional {
          if ($has_smart_directive) {
            var.update $dynamic_context {
              value = $dynamic_context|concat:$smart_section:""
            }
          }
        }
      }
    }
  
    // â”€â”€ Inject account-level AI context â”€â”€
    conditional {
      if ($journey_map.account_id != null) {
        db.get account {
          field_name = "id"
          field_value = $journey_map.account_id
          output = ["id", "name", "ai_context"]
        } as $account

        conditional {
          if ($account != null && $account.ai_context != null && $account.ai_context != "") {
            var $company_section {
              value = "\n\n## Company Context\n"
                |concat:"Organisation: ":""
                |concat:$account.name:""
                |concat:"\n":""
                |concat:$account.ai_context:""
            }

            var.update $dynamic_context {
              value = $dynamic_context|concat:$company_section:""
            }
          }
        }
      }
    }

    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n\n### Stages (columns)\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:($stage_labels|join:", "):""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n\n### Lenses (rows)\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:($lens_labels|join:"\n"):""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n\n### Fill Summary\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:("- Total cells: "|concat:($total_cells|to_text):"")
        |concat:"\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:("- Filled: "
          |concat:($filled_cells|to_text):""
        )
        |concat:"\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:("- Empty: "|concat:($empty_cells|to_text):"")
        |concat:"\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:("- Locked: "
          |concat:($locked_cells|to_text):""
        )
        |concat:"\n":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:("- Confirmed: "
          |concat:($confirmed_cells|to_text):""
        )
        |concat:"\n":""
    }
  
    // â”€â”€ ARO-08: Per-lens cell fill grid â€” shows which stage keys are filled vs empty â”€â”€
    // Gives the agent precise per-cell visibility so it doesn't overwrite filled cells
    // or skip empty ones when handling scoped manual requests.
    var $cell_fill_grid {
      value = "\n\n### Cell Fill Grid\n"
    }

    foreach ($lenses) {
      each as $ln {
        var $row_line {
          value = "- " ~ $ln.key ~ ": "
        }

        foreach ($stages) {
          each as $st {
            var $cell_filled {
              value = false
            }

            foreach ($cells) {
              each as $c {
                conditional {
                  if ($c.lens == $ln.id && $c.stage == $st.id) {
                    conditional {
                      if ($c.content != null && $c.content != "") {
                        var.update $cell_filled {
                          value = true
                        }
                      }
                    }
                  }
                }
              }
            }

            conditional {
              if ($cell_filled) {
                var.update $row_line {
                  value = $row_line ~ $st.key ~ "âœ… "
                }
              }

              else {
                var.update $row_line {
                  value = $row_line ~ $st.key ~ "â¬œ "
                }
              }
            }
          }
        }

        var.update $cell_fill_grid {
          value = $cell_fill_grid ~ $row_line ~ "\n"
        }
      }
    }

    var.update $dynamic_context {
      value = $dynamic_context|concat:$cell_fill_grid:""
    }

    // â”€â”€ Inject selected cell context (if the user has a cell focused) â”€â”€
    conditional {
      if ($input.selected_cell != null && ($input.selected_cell|is_empty) == false) {
        var $cell_section {
          value = "\n### Currently Selected Cell\n"
        }
      
        var.update $cell_section {
          value = $cell_section
            |concat:"- **Reference:** ":($input.selected_cell|get:"reference"):""
            |concat:"\n":""
        }
      
        var.update $cell_section {
          value = $cell_section
            |concat:"- **Shorthand:** ":($input.selected_cell|get:"shorthand"):""
            |concat:"\n":""
        }
      
        var.update $cell_section {
          value = $cell_section
            |concat:"- **Stage key:** ":($input.selected_cell|get:"stage_key"):""
            |concat:"\n":""
        }
      
        var.update $cell_section {
          value = $cell_section
            |concat:"- **Lens key:** ":($input.selected_cell|get:"lens_key"):""
            |concat:"\n":""
        }
      
        var.update $cell_section {
          value = $cell_section
            |concat:"- **Stage label:** ":($input.selected_cell|get:"stage_label"):""
            |concat:"\n":""
        }
      
        var.update $cell_section {
          value = $cell_section
            |concat:"- **Lens label:** ":($input.selected_cell|get:"lens_label"):""
            |concat:"\n":""
        }
      
        conditional {
          if (($input.selected_cell|get:"journey_cell_id") != null) {
            var.update $cell_section {
              value = $cell_section
                |concat:"- **Cell ID:** ":(($input.selected_cell|get:"journey_cell_id")|to_text):""
                |concat:"\n":""
            }
          }
        }
      
        var.update $dynamic_context {
          value = $dynamic_context|concat:$cell_section:""
        }
      }
    }
  
    // â”€â”€ Inject actor role context for the selected cell's parent lens â”€â”€
    conditional {
      if ($input.selected_cell != null && ($input.selected_cell|is_empty) == false) {
        var $selected_lens_id {
          value = $input.selected_cell|get:"lens_id"
        }
      
        conditional {
          if ($selected_lens_id != null) {
            var $actor_lens {
              value = null
            }
          
            foreach ($lenses) {
              each as $ln {
                conditional {
                  if ($ln.id == $selected_lens_id) {
                    var.update $actor_lens {
                      value = $ln
                    }
                  }
                }
              }
            }
          
            conditional {
              if ($actor_lens != null && $actor_lens.actor_type != null) {
                var $actor_section {
                  value = "\n\n## Active Actor Context\n"
                }
              
                var.update $actor_section {
                  value = $actor_section
                    |concat:"- **Actor:** ":""
                    |concat:$actor_lens.label:""
                    |concat:" (":""
                    |concat:$actor_lens.actor_type:""
                    |concat:")\n":""
                }
              
                conditional {
                  if ($actor_lens.persona_description != null && $actor_lens.persona_description != "") {
                    var.update $actor_section {
                      value = $actor_section
                        |concat:"- **Persona:** ":$actor_lens.persona_description:""
                        |concat:"\n":""
                    }
                  }
                }
              
                conditional {
                  if ($actor_lens.primary_goal != null && $actor_lens.primary_goal != "") {
                    var.update $actor_section {
                      value = $actor_section
                        |concat:"- **Primary Goal:** ":$actor_lens.primary_goal:""
                        |concat:"\n":""
                    }
                  }
                }
              
                conditional {
                  if ($actor_lens.standing_constraints != null && $actor_lens.standing_constraints != "") {
                    var.update $actor_section {
                      value = $actor_section
                        |concat:"- **Constraints:** ":$actor_lens.standing_constraints:""
                        |concat:"\n":""
                    }
                  }
                }
              
                conditional {
                  if ($actor_lens.role_prompt != null && $actor_lens.role_prompt != "") {
                    var.update $actor_section {
                      value = $actor_section
                        |concat:"- **Role Instructions:** ":$actor_lens.role_prompt:""
                        |concat:"\n":""
                    }
                  }
                }
              
                var.update $dynamic_context {
                  value = $dynamic_context|concat:$actor_section:""
                }
              }
            }
          }
        }
      }
    }
  
    // â”€â”€ Inject structured actor cell fields (filled vs empty) for selected cell â”€â”€
    conditional {
      if ($input.selected_cell != null && ($input.selected_cell|is_empty) == false) {
        var $cell_id_for_fields {
          value = $input.selected_cell|get:"journey_cell_id"
        }
      
        conditional {
          if ($cell_id_for_fields != null) {
            db.get journey_cell {
              field_name = "id"
              field_value = $cell_id_for_fields
            } as $cell_record
          
            conditional {
              if ($cell_record != null && $cell_record.actor_fields != null) {
                // Fetch the parent lens to determine actor_type for label selection
                db.get journey_lens {
                  field_name = "id"
                  field_value = $cell_record.lens
                } as $cell_lens_record
              
                var $cell_actor_type {
                  value = null
                }
              
                conditional {
                  if ($cell_lens_record != null) {
                    var.update $cell_actor_type {
                      value = $cell_lens_record.actor_type
                    }
                  }
                }
              
                var $fields_section {
                  value = "\n\n## Cell Actor Fields â€” Current State\n"
                }
              
                var $filled_lines {
                  value = ""
                }
              
                var $empty_lines {
                  value = ""
                }
              
                // single reusable temp â€” declared once so it stays in scope for all inner conditionals
                var $fv_temp {
                  value = null
                }
              
                // â”€â”€ Customer fields â”€â”€
                conditional {
                  if ($cell_actor_type == "customer") {
                    // entry_trigger
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"entry_trigger"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Entry Point / Trigger [key: entry_trigger]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Entry Point / Trigger [key: entry_trigger]\n":""
                        }
                      }
                    }
                  
                    // emotions
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"emotions"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Feelings / Emotions [key: emotions]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Feelings / Emotions [key: emotions]\n":""
                        }
                      }
                    }
                  
                    // information_needs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"information_needs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Information Needs [key: information_needs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information Needs [key: information_needs]\n":""
                        }
                      }
                    }
                  
                    // decisions_required
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"decisions_required"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Decisions Required [key: decisions_required]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Decisions Required [key: decisions_required]\n":""
                        }
                      }
                    }
                  
                    // friction_points
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"friction_points"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Friction Points [key: friction_points]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Friction Points [key: friction_points]\n":""
                        }
                      }
                    }
                  
                    // assumptions
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"assumptions"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Assumptions [key: assumptions]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Assumptions [key: assumptions]\n":""
                        }
                      }
                    }
                  
                    // acceptance_criteria
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"acceptance_criteria"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Acceptance Criteria [key: acceptance_criteria]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Acceptance Criteria [key: acceptance_criteria]":""
                        }
                      }
                    }
                  
                    // expected_output
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"expected_output"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Expected Output / Confirmation [key: expected_output]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Expected Output / Confirmation [key: expected_output]":""
                        }
                      }
                    }
                  
                    // channel_touchpoint
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"channel_touchpoint"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Channel / Touchpoint [key: channel_touchpoint]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Channel / Touchpoint [key: channel_touchpoint]":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Internal employee fields â”€â”€
                conditional {
                  if ($cell_actor_type == "internal") {
                    // task_objective
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"task_objective"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Task / Objective [key: task_objective]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Task / Objective [key: task_objective]\n":""
                        }
                      }
                    }
                  
                    // entry_trigger
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"entry_trigger"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Entry Point / Trigger [key: entry_trigger]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Entry Point / Trigger [key: entry_trigger]\n":""
                        }
                      }
                    }
                  
                    // tools_systems
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"tools_systems"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Tools & Systems Used [key: tools_systems]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Tools & Systems Used [key: tools_systems]\n":""
                        }
                      }
                    }
                  
                    // information_needs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"information_needs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Information Needs [key: information_needs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information Needs [key: information_needs]\n":""
                        }
                      }
                    }
                  
                    // decisions_required
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"decisions_required"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Decisions Required [key: decisions_required]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Decisions Required [key: decisions_required]\n":""
                        }
                      }
                    }
                  
                    // friction_points
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"friction_points"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Friction Points [key: friction_points]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Friction Points [key: friction_points]\n":""
                        }
                      }
                    }
                  
                    // assumptions
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"assumptions"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Assumptions Being Made [key: assumptions]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Assumptions Being Made [key: assumptions]\n":""
                        }
                      }
                    }
                  
                    // handoff_dependencies
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"handoff_dependencies"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Handoff Dependencies [key: handoff_dependencies]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Handoff Dependencies [key: handoff_dependencies]":""
                        }
                      }
                    }
                  
                    // success_criteria
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"success_criteria"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Success Criteria [key: success_criteria]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Success Criteria [key: success_criteria]\n":""
                        }
                      }
                    }
                  
                    // output_deliverable
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"output_deliverable"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Output / Deliverable [key: output_deliverable]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Output / Deliverable [key: output_deliverable]":""
                        }
                      }
                    }
                  
                    // employee_constraints
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"employee_constraints"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Employee Constraints [key: employee_constraints]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Employee Constraints [key: employee_constraints]":""
                        }
                      }
                    }
                  
                    // pain_points
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"pain_points"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Pain Points [key: pain_points]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Pain Points [key: pain_points]\n":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Engineering fields â”€â”€
                conditional {
                  if ($cell_actor_type == "engineering") {
                    // system_service_owner
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"system_service_owner"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- System / Service Owner [key: system_service_owner]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- System / Service Owner [key: system_service_owner]":""
                        }
                      }
                    }
                  
                    // data_inputs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"data_inputs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Data Inputs [key: data_inputs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Inputs [key: data_inputs]\n":""
                        }
                      }
                    }
                  
                    // data_outputs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"data_outputs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Data Outputs [key: data_outputs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Outputs [key: data_outputs]\n":""
                        }
                      }
                    }
                  
                    // api_integration_dependencies
                    var.update $fv_temp {
                      value = $cell_record.actor_fields
                        |get:"api_integration_dependencies"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- API / Integration Dependencies [key: api_integration_dependencies]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- API / Integration Dependencies [key: api_integration_dependencies]":""
                        }
                      }
                    }
                  
                    // business_rules_logic
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"business_rules_logic"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Business Rules / Logic [key: business_rules_logic]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Business Rules / Logic [key: business_rules_logic]":""
                        }
                      }
                    }
                  
                    // error_states_edge_cases
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"error_states_edge_cases"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Error States / Edge Cases [key: error_states_edge_cases]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Error States / Edge Cases [key: error_states_edge_cases]":""
                        }
                      }
                    }
                  
                    // data_storage_requirements
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"data_storage_requirements"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Data Storage Requirements [key: data_storage_requirements]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Storage Requirements [key: data_storage_requirements]":""
                        }
                      }
                    }
                  
                    // security_permissions
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"security_permissions"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Security & Permissions [key: security_permissions]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Security & Permissions [key: security_permissions]":""
                        }
                      }
                    }
                  
                    // performance_requirements
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"performance_requirements"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Performance Requirements [key: performance_requirements]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Performance Requirements [key: performance_requirements]":""
                        }
                      }
                    }
                  
                    // audit_logging_needs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"audit_logging_needs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Audit / Logging Needs [key: audit_logging_needs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Audit / Logging Needs [key: audit_logging_needs]":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ AI Agent fields â”€â”€
                conditional {
                  if ($cell_actor_type == "ai_agent") {
                    // ai_model_agent
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"ai_model_agent"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- AI Model / Agent [key: ai_model_agent]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- AI Model / Agent [key: ai_model_agent]\n":""
                        }
                      }
                    }
                  
                    // input_data
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"input_data"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Input Data [key: input_data]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Input Data [key: input_data]\n":""
                        }
                      }
                    }
                  
                    // decision_output
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"decision_output"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Decision / Output [key: decision_output]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Decision / Output [key: decision_output]\n":""
                        }
                      }
                    }
                  
                    // confidence_threshold
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"confidence_threshold"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Confidence Threshold [key: confidence_threshold]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Confidence Threshold [key: confidence_threshold]":""
                        }
                      }
                    }
                  
                    // escalation_logic
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"escalation_logic"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Escalation Logic [key: escalation_logic]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Escalation Logic [key: escalation_logic]\n":""
                        }
                      }
                    }
                  
                    // training_data
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"training_data"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Training Data [key: training_data]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Training Data [key: training_data]\n":""
                        }
                      }
                    }
                  
                    // retraining_frequency
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"retraining_frequency"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Retraining Frequency [key: retraining_frequency]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Retraining Frequency [key: retraining_frequency]":""
                        }
                      }
                    }
                  
                    // bias_fairness_considerations
                    var.update $fv_temp {
                      value = $cell_record.actor_fields
                        |get:"bias_fairness_considerations"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Bias & Fairness Considerations [key: bias_fairness_considerations]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Bias & Fairness Considerations [key: bias_fairness_considerations]":""
                        }
                      }
                    }
                  
                    // failure_scenarios
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"failure_scenarios"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Failure Scenarios [key: failure_scenarios]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Failure Scenarios [key: failure_scenarios]\n":""
                        }
                      }
                    }
                  
                    // performance_metrics
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"performance_metrics"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Performance Metrics [key: performance_metrics]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Performance Metrics [key: performance_metrics]":""
                        }
                      }
                    }
                  
                    // model_owner
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"model_owner"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Model Owner [key: model_owner]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Model Owner [key: model_owner]\n":""
                        }
                      }
                    }
                  
                    // explainability_needs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"explainability_needs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Explainability Needs [key: explainability_needs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Explainability Needs [key: explainability_needs]":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Handoff fields â”€â”€
                conditional {
                  if ($cell_actor_type == "handoff") {
                    // trigger_event
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"trigger_event"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Trigger Event [key: trigger_event]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Trigger Event [key: trigger_event]\n":""
                        }
                      }
                    }
                  
                    // upstream_actor
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"upstream_actor"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Upstream Actor [key: upstream_actor]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Upstream Actor [key: upstream_actor]\n":""
                        }
                      }
                    }
                  
                    // prerequisite_data
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"prerequisite_data"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Prerequisite Data [key: prerequisite_data]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Prerequisite Data [key: prerequisite_data]\n":""
                        }
                      }
                    }
                  
                    // upstream_dependencies
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"upstream_dependencies"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Upstream Dependencies [key: upstream_dependencies]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Upstream Dependencies [key: upstream_dependencies]":""
                        }
                      }
                    }
                  
                    // handoff_output
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"handoff_output"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Handoff Output [key: handoff_output]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Handoff Output [key: handoff_output]\n":""
                        }
                      }
                    }
                  
                    // handoff_format
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"handoff_format"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Handoff Format [key: handoff_format]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Handoff Format [key: handoff_format]\n":""
                        }
                      }
                    }
                  
                    // handoff_timing
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"handoff_timing"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Handoff Timing [key: handoff_timing]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Handoff Timing [key: handoff_timing]\n":""
                        }
                      }
                    }
                  
                    // downstream_actor
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"downstream_actor"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Downstream Actor [key: downstream_actor]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Downstream Actor [key: downstream_actor]\n":""
                        }
                      }
                    }
                  
                    // validation_rules
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"validation_rules"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Validation Rules [key: validation_rules]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Validation Rules [key: validation_rules]\n":""
                        }
                      }
                    }
                  
                    // failure_recovery
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"failure_recovery"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Failure Recovery [key: failure_recovery]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Failure Recovery [key: failure_recovery]\n":""
                        }
                      }
                    }
                  
                    // communication_method
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"communication_method"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Communication Method [key: communication_method]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Communication Method [key: communication_method]":""
                        }
                      }
                    }
                  
                    // data_retention_policy
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"data_retention_policy"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Data Retention Policy [key: data_retention_policy]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Retention Policy [key: data_retention_policy]":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Vendor fields â”€â”€
                conditional {
                  if ($cell_actor_type == "vendor") {
                    // vendor_name_type
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"vendor_name_type"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Vendor Name / Type [key: vendor_name_type]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Vendor Name / Type [key: vendor_name_type]\n":""
                        }
                      }
                    }
                  
                    // role_at_step
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"role_at_step"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Role at This Step [key: role_at_step]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Role at This Step [key: role_at_step]\n":""
                        }
                      }
                    }
                  
                    // engagement_trigger
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"engagement_trigger"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Engagement Trigger [key: engagement_trigger]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Engagement Trigger [key: engagement_trigger]\n":""
                        }
                      }
                    }
                  
                    // contractual_obligations
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"contractual_obligations"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Contractual Obligations [key: contractual_obligations]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Contractual Obligations [key: contractual_obligations]":""
                        }
                      }
                    }
                  
                    // information_needs
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"information_needs"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Information Needs [key: information_needs]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information Needs [key: information_needs]\n":""
                        }
                      }
                    }
                  
                    // information_returned
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"information_returned"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Information They Return [key: information_returned]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information They Return [key: information_returned]":""
                        }
                      }
                    }
                  
                    // integration_method
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"integration_method"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Integration Method [key: integration_method]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Integration Method [key: integration_method]\n":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Vendor fields (continued: fields 8-14) â”€â”€
                conditional {
                  if ($cell_actor_type == "vendor") {
                    // sla_performance_metrics
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"sla_performance_metrics"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- SLA / Performance Metrics [key: sla_performance_metrics]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- SLA / Performance Metrics [key: sla_performance_metrics]":""
                        }
                      }
                    }
                  
                    // failure_scenario
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"failure_scenario"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Failure Scenario [key: failure_scenario]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Failure Scenario [key: failure_scenario]\n":""
                        }
                      }
                    }
                  
                    // escalation_path
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"escalation_path"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Escalation Path [key: escalation_path]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Escalation Path [key: escalation_path]\n":""
                        }
                      }
                    }
                  
                    // data_privacy_compliance
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"data_privacy_compliance"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Data Privacy & Compliance [key: data_privacy_compliance]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Privacy & Compliance [key: data_privacy_compliance]":""
                        }
                      }
                    }
                  
                    // vendor_constraints
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"vendor_constraints"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Vendor Constraints [key: vendor_constraints]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Vendor Constraints [key: vendor_constraints]\n":""
                        }
                      }
                    }
                  
                    // cost_impact
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"cost_impact"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Cost Impact [key: cost_impact]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Cost Impact [key: cost_impact]\n":""
                        }
                      }
                    }
                  
                    // dependency_on_internal
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"dependency_on_internal"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Dependency on Internal Actors [key: dependency_on_internal]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Dependency on Internal Actors [key: dependency_on_internal]":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Financial Intelligence fields â”€â”€
                conditional {
                  if ($cell_actor_type == "financial") {
                    // cost_to_serve
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"cost_to_serve"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Cost to Serve [key: cost_to_serve]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Cost to Serve [key: cost_to_serve]\n":""
                        }
                      }
                    }
                  
                    // revenue_at_risk
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"revenue_at_risk"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Revenue at Risk [key: revenue_at_risk]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Revenue at Risk [key: revenue_at_risk]\n":""
                        }
                      }
                    }
                  
                    // automation_savings
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"automation_savings"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Automation Savings [key: automation_savings]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Automation Savings [key: automation_savings]\n":""
                        }
                      }
                    }
                  
                    // upsell_opportunity
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"upsell_opportunity"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Upsell / Cross-sell Opportunity [key: upsell_opportunity]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Upsell / Cross-sell Opportunity [key: upsell_opportunity]":""
                        }
                      }
                    }
                  
                    // revenue_leakage
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"revenue_leakage"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Revenue Leakage [key: revenue_leakage]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Revenue Leakage [key: revenue_leakage]\n":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Financial Intelligence fields (continued: fields 6-10) â”€â”€
                conditional {
                  if ($cell_actor_type == "financial") {
                    // cost_efficiency_note
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"cost_efficiency_note"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Cost Efficiency Note [key: cost_efficiency_note]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Cost Efficiency Note [key: cost_efficiency_note]":""
                        }
                      }
                    }
                  
                    // breakeven_threshold
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"breakeven_threshold"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Breakeven Threshold [key: breakeven_threshold]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Breakeven Threshold [key: breakeven_threshold]":""
                        }
                      }
                    }
                  
                    // cac_contribution
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"cac_contribution"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- CAC Contribution [key: cac_contribution]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- CAC Contribution [key: cac_contribution]\n":""
                        }
                      }
                    }
                  
                    // clv_impact
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"clv_impact"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- CLV Impact [key: clv_impact]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- CLV Impact [key: clv_impact]\n":""
                        }
                      }
                    }
                  
                    // priority_score
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"priority_score"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Financial Priority Score [key: priority_score]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Financial Priority Score [key: priority_score]":""
                        }
                      }
                    }
                  }
                }
              
                // â”€â”€ Metrics fields â”€â”€
                conditional {
                  if ($cell_actor_type == "metrics") {
                    var.update $fields_section {
                      value = $fields_section
                        |concat:"Healthy thresholds: csat_score >= 8.0 | completion_rate >= 90% | drop_off_rate <= 10% | error_rate <= 5%":""
                    }
                  
                    // csat_score
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"csat_score"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- CSAT Score (1-10) [key: csat_score]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- CSAT Score (1-10) [key: csat_score]\n":""
                        }
                      }
                    }
                  
                    // completion_rate
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"completion_rate"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Completion Rate % [key: completion_rate]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Completion Rate % [key: completion_rate]\n":""
                        }
                      }
                    }
                  
                    // drop_off_rate
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"drop_off_rate"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Drop-off Rate % [key: drop_off_rate]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Drop-off Rate % [key: drop_off_rate]\n":""
                        }
                      }
                    }
                  
                    // avg_time_to_complete
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"avg_time_to_complete"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Avg Time to Complete (min) [key: avg_time_to_complete]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Avg Time to Complete (min) [key: avg_time_to_complete]":""
                        }
                      }
                    }
                  
                    // error_rate
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"error_rate"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Error Rate % [key: error_rate]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Error Rate % [key: error_rate]\n":""
                        }
                      }
                    }
                  
                    // sla_compliance_rate
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"sla_compliance_rate"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- SLA Compliance Rate % [key: sla_compliance_rate]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- SLA Compliance Rate % [key: sla_compliance_rate]":""
                        }
                      }
                    }
                  
                    // volume_frequency
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"volume_frequency"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Volume / Frequency [key: volume_frequency]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Volume / Frequency [key: volume_frequency]\n":""
                        }
                      }
                    }
                  
                    // stage_health
                    var.update $fv_temp {
                      value = $cell_record.actor_fields|get:"stage_health"
                    }
                  
                    conditional {
                      if ($fv_temp != null && $fv_temp != "") {
                        var.update $filled_lines {
                          value = $filled_lines
                            |concat:"- Stage Health Score (1-10) [key: stage_health]: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Stage Health Score (1-10) [key: stage_health]\n":""
                        }
                      }
                    }
                  }
                }
              
                // Assemble the section
                conditional {
                  if ($filled_lines != "") {
                    var.update $fields_section {
                      value = $fields_section
                        |concat:"Already captured at this stage:\n":$filled_lines:""
                    }
                  }
                }
              
                conditional {
                  if ($empty_lines != "") {
                    var.update $fields_section {
                      value = $fields_section
                        |concat:"Fields still to complete:\n":$empty_lines:""
                        |concat:"Focus your response on completing the empty fields above. For already-captured fields, only refine if they are incomplete or unclear.":""
                    }
                  }
                }
              
                conditional {
                  if ($empty_lines == "") {
                    var.update $fields_section {
                      value = $fields_section
                        |concat:"All fields are complete for this cell. Offer refinements or deeper insight rather than filling gaps.":""
                    }
                  }
                }
              
                var.update $dynamic_context {
                  value = $dynamic_context|concat:$fields_section:""
                }
              }
            }
          }
        }
      }
    }
  
    // â”€â”€ Load enabled capabilities and append to dynamic context â”€â”€
    db.query agent_capability {
      where = $db.agent_capability.enabled == true
      return = {type: "list"}
    } as $capabilities
  
    conditional {
      if (($capabilities|count) > 0) {
        var $cap_section {
          value = "\n### Enabled Capabilities\n"
        }
      
        foreach ($capabilities) {
          each as $cap {
            var.update $cap_section {
              value = $cap_section
                |concat:("- **%s** (%s): %s\n"
                  |sprintf:$cap.label:$cap.key:$cap.instructions
                ):""
            }
          }
        }
      
        var.update $dynamic_context {
          value = $dynamic_context|concat:$cap_section:""
        }
      }
    }
  
    // â”€â”€ Inject parent journey context (anti-journey / exception / sub-journey) â”€â”€
    conditional {
      if ($input.parent_context != null && ($input.parent_context|is_empty) == false) {
        var $parent_section {
          value = "\n\n## Parent Journey Context\n"
        }
      
        var $pc_link_type {
          value = $input.parent_context|get:"link_type"
        }
      
        var $pc_parent_title {
          value = $input.parent_context|get:"parent_map_title"
        }
      
        var $pc_stage {
          value = $input.parent_context|get:"source_stage_label"
        }
      
        var $pc_lens {
          value = $input.parent_context|get:"source_lens_label"
        }
      
        var $pc_trigger {
          value = $input.parent_context|get:"trigger_content"
        }
      
        conditional {
          if ($pc_link_type != null) {
            var.update $parent_section {
              value = $parent_section
                |concat:"- **Link type:** " ~ $pc_link_type ~ "\n":""
            }
          }
        }
      
        conditional {
          if ($pc_parent_title != null) {
            var.update $parent_section {
              value = $parent_section
                |concat:"- **Parent map:** " ~ $pc_parent_title ~ "\n":""
            }
          }
        }
      
        conditional {
          if ($pc_stage != null && $pc_lens != null) {
            var.update $parent_section {
              value = $parent_section
                |concat:"- **Trigger location:** " ~ $pc_stage ~ " Ã— " ~ $pc_lens ~ "\n":""
            }
          }
        }
      
        conditional {
          if ($pc_trigger != null && $pc_trigger != "") {
            var.update $parent_section {
              value = $parent_section
                |concat:"- **Trigger cell content:** \"" ~ $pc_trigger ~ "\"\n":""
            }
          }
        }
      
        var.update $parent_section {
          value = $parent_section
            |concat:"""
            
            This map was branched from the above step in the parent happy-path map.
            """:""
            |concat:"Use this context to ground your suggestions â€” the friction or failure described ":""
            |concat:"in the trigger cell is the starting point for this scenario.":""
        }
      
        var.update $dynamic_context {
          value = $dynamic_context|concat:$parent_section:""
        }
      }
    }
  
    // â”€â”€ Resolve or create conversation â”€â”€
    var $conversation {
      value = null
    }
  
    conditional {
      if ($input.conversation_id != null) {
        db.get agent_conversation {
          field_name = "id"
          field_value = $input.conversation_id
        } as $req_conv
      
        precondition ($req_conv != null && $req_conv.journey_map == $input.journey_map_id) {
          error_type = "inputerror"
          error = "Conversation does not belong to this journey map"
        }
      
        var.update $conversation {
          value = $req_conv
        }
      }
    
      else {
        // Find the most recent conversation for this map, or create one
        db.query agent_conversation {
          where = $db.agent_conversation.journey_map == $input.journey_map_id
          sort = {last_message_at: "desc"}
          return = {type: "list"}
        } as $existing_convs
      
        conditional {
          if (($existing_convs|count) > 0) {
            var.update $conversation {
              value = $existing_convs|first
            }
          }
        }
      }
    }
  
    conditional {
      if ($conversation == null) {
        db.add agent_conversation {
          data = {
            created_at     : "now"
            journey_map    : $input.journey_map_id
            title          : "Journey Map Conversation"
            mode           : $effective_mode
            last_message_at: "now"
          }
        } as $new_conv
      
        var.update $conversation {
          value = $new_conv
        }
      }
    }
  
    // â”€â”€ Load conversation history â”€â”€
    db.query agent_message {
      where = $db.agent_message.conversation == $conversation.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $history_messages
  
    // â”€â”€ Build messages array for the agent â”€â”€
    // â”€â”€ Persist user message first (needed to generate turn_id) â”€â”€
    db.add agent_message {
      data = {
        created_at  : "now"
        conversation: $conversation.id
        role        : "user"
        mode        : $effective_mode
        content     : []|push:({}|set:"type":"text"|set:"text":$input.content)
      }
    } as $user_message
  
    // â”€â”€ Generate turn_id for tool trace logging â”€â”€
    var $turn_id {
      value = "turn_" ~ $conversation.id ~ "_" ~ $user_message.id
    }

    // â”€â”€ Resolve log tier (US-ATL-01) â”€â”€
    // full = builder_mode (payloads captured in tools)
    // minimal = orchestrator / S2S (tool logs written async post-response)
    // summary = chat / interview (summaries only, existing behaviour)
    var $log_tier {
      value = "summary"
    }

    conditional {
      // HUX-03: capture_payloads=true also forces full tier (debug payload capture)
      if ($input.builder_mode == true || $input.capture_payloads == true) {
        var.update $log_tier {
          value = "full"
        }
      }

      elseif ($effective_mode == "orchestrator") {
        var.update $log_tier {
          value = "minimal"
        }
      }
    }

    // â”€â”€ SENTINEL: write turn log BEFORE LLM call (US-ATL-01) â”€â”€
    // Status = in_progress. Orphaned turns (never patched) are detectable by
    // querying status=in_progress with started_at older than a threshold.
    var $sentinel_id {
      value = null
    }

    try_catch {
      try {
        db.add agent_turn_log {
          data = {
            created_at          : "now"
            started_at          : "now"
            conversation        : $conversation.id
            journey_map         : $input.journey_map_id
            turn_id             : $turn_id
            mode                : $effective_mode
            log_tier            : $log_tier
            status              : "in_progress"
            user_message_preview: $input.content
          }
        } as $sentinel_record

        var.update $sentinel_id {
          value = $sentinel_record.id
        }
      }

      catch {
        // Sentinel write failed â€” non-fatal, proceed without sentinel id
        var $sentinel_write_failed {
          value = true
        }
      }
    }


    // â”€â”€ Inject Specialist Persona block (SCM-03) â”€â”€
    conditional {
      if ($input.specialist_actor_key != null && $input.specialist_actor_key != "") {
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.specialist_actor_key
          return = {type: "single"}
        } as $specialist_lens

        conditional {
          if ($specialist_lens != null) {
            var $specialist_section {
              value = "\n\n## Specialist Persona\nYou ARE this actor for this entire conversation. Speak in first person.\n"
                |concat:"- Actor: " ~ $specialist_lens.label ~ " (" ~ ($specialist_lens.actor_type ?? "internal") ~ ")\n":""
            }

            conditional {
              if ($specialist_lens.persona_description != null && $specialist_lens.persona_description != "") {
                var.update $specialist_section {
                  value = $specialist_section
                    |concat:"- Persona: " ~ $specialist_lens.persona_description ~ "\n":""
                }
              }
            }

            conditional {
              if ($specialist_lens.primary_goal != null && $specialist_lens.primary_goal != "") {
                var.update $specialist_section {
                  value = $specialist_section
                    |concat:"- Primary Goal: " ~ $specialist_lens.primary_goal ~ "\n":""
                }
              }
            }

            conditional {
              if ($specialist_lens.standing_constraints != null && $specialist_lens.standing_constraints != "") {
                var.update $specialist_section {
                  value = $specialist_section
                    |concat:"- Standing Constraints: " ~ $specialist_lens.standing_constraints ~ "\n":""
                }
              }
            }

            var.update $dynamic_context {
              value = $dynamic_context|concat:$specialist_section:""
            }
          }
        }
      }
    }

    // â”€â”€ Inject Consortium Panel block (SCM-04) â”€â”€
    conditional {
      if ($input.consortium_actor_keys != null && ($input.consortium_actor_keys|count) > 0) {
        var $consortium_section {
          value = "\n\n## Consortium Panel\nYou represent ALL of the following actors simultaneously.\nFor each question give each actor's perspective labeled with their name.\nEnd with a Synthesis line.\n"
        }

        foreach ($input.consortium_actor_keys) {
          each as $cak {
            db.query journey_lens {
              where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $cak
              return = {type: "single"}
            } as $panel_lens

            conditional {
              if ($panel_lens != null) {
                var $panel_line {
                  value = "- " ~ $panel_lens.label
                }

                conditional {
                  if ($panel_lens.persona_description != null && $panel_lens.persona_description != "") {
                    var.update $panel_line {
                      value = $panel_line
                        |concat:": " ~ $panel_lens.persona_description:""
                    }
                  }
                }

                conditional {
                  if ($panel_lens.primary_goal != null && $panel_lens.primary_goal != "") {
                    var.update $panel_line {
                      value = $panel_line
                        |concat:" | Goal: " ~ $panel_lens.primary_goal:""
                    }
                  }
                }

                var.update $consortium_section {
                  value = $consortium_section|concat:$panel_line ~ "\n":""
                }
              }
            }
          }
        }

        var.update $dynamic_context {
          value = $dynamic_context|concat:$consortium_section:""
        }
      }
    }
    // â”€â”€ Orchestrator mode: inject session marker (US-WE-05) â”€â”€
    // The agent's system prompt instructs it to self-initiate validate_workflow
    // and get_workflow_state on session start. This marker confirms the mode context.
    conditional {
      if ($effective_mode == "orchestrator") {
        var.update $dynamic_context {
          value = $dynamic_context
            |concat:"\n\n## Orchestrator Mode Active\n":""
<<<<<<<
            |concat:"You are running as the Journey Map Orchestrator (mode=orchestrator).\n":""
=======
            |concat:"You are running as the Journey Map Orchestrator (mode=orchestrator).":""
>>>>>>>
            |concat:"On your FIRST turn in this session:\n":""
<<<<<<<
            |concat:"1. Call validate_workflow to run pre-flight checks.\n":""
            |concat:"2. Call get_workflow_state to check for a prior execution run.\n":""
            |concat:"3. Follow the sequencing rules in your system prompt.\n":""
            |concat:"Do NOT start execution until you have completed steps 1-2.\n":""
=======
            |concat:"1. Call validate_workflow to run pre-flight checks.":""
            |concat:"2. Call get_workflow_state to check for a prior execution run.":""
            |concat:"3. Follow the sequencing rules in your system prompt.":""
            |concat:"Do NOT start execution until you have completed steps 1-2.":""
>>>>>>>
        }
      }
    }

    // â”€â”€ Inject journey_map_id, conversation_id and turn_id into dynamic context â”€â”€
    // ALL THREE must be passed to every tool call â€” the agent reads this section.
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n\n### Tool Logging (pass to every tool call)\n":""
        |concat:"- journey_map_id: " ~ ($input.journey_map_id|to_text):""
        |concat:"\n- conversation_id: " ~ $conversation.id:""
        |concat:"\n- turn_id: " ~ $turn_id:""
        |concat:"\n- log_tier: " ~ $log_tier:""
    }
  
    // â”€â”€ Build messages array (system uses the NOW-complete context) â”€â”€
    var $agent_messages {
      value = []
    }
  
    array.push $agent_messages {
      value = {role: "system", content: $dynamic_context}
    }
  
    // â”€â”€ Cap conversation history to a predictable window (last 20 messages) â”€â”€
    var $max_history_messages {
      value = 20
    }
  
    var $history_skip {
      value = 0
    }
  
    conditional {
      if (($history_messages|count) > $max_history_messages) {
        var.update $history_skip {
          value = ($history_messages|count) - $max_history_messages
        }
      }
    }
  
    var $history_idx {
      value = 0
    }
  
    // Append conversation history (capped to last $max_history_messages entries)
    foreach ($history_messages) {
      each as $hm {
        conditional {
          if ($history_idx >= $history_skip) {
            // Flatten content array to text for the agent
            var $msg_text {
              value = ""
            }
          
            conditional {
              if ($hm.content != null) {
                // Content is stored as JSON array [{type:"text", text:"..."}]
                // Extract the text for the agent
                api.lambda {
                  code = """
                      const content = $var.hm.content;
                      if (Array.isArray(content)) {
                        return content.map(c => c.text || '').join('\n');
                      }
                      return typeof content === 'string' ? content : JSON.stringify(content);
                    """
                  timeout = 5
                } as $extracted_text
              
                var.update $msg_text {
                  value = $extracted_text
                }
              }
            }
          
            conditional {
              if ($msg_text != "") {
                array.push $agent_messages {
                  value = {role: $hm.role, content: $msg_text}
                }
              }
            }
          }
        }
      
        var.update $history_idx {
          value = $history_idx + 1
        }
      }
    }
  
    // Append the current user message
    array.push $agent_messages {
      value = {role: "user", content: $input.content}
    }
  
    // â”€â”€ Call the agent (with error capture for turn logging) â”€â”€
    var $agent_run {
      value = null
    }
  
    var $agent_error {
      value = null
    }
  
    try_catch {
      try {
        group {
          stack {
            conditional {
              if ($input.builder_mode) {
                ai.agent.run "Journey Map Builder" {
                  args = {}|set:"messages":$agent_messages
                  allow_tool_execution = true
                } as $agent_run_inner
              }

              else {
                // Route by mode:
                // chat â†’ read-only Chat Agent (Specialist/Consortium are sub-modes of chat)
                // orchestrator â†’ Workflow Execution Orchestrator (US-WE-05)
                // interview (default) â†’ Journey Map Assistant
                conditional {
                  if ($effective_mode == "chat") {
                    ai.agent.run "Journey Map Chat Agent" {
                      args = {}|set:"messages":$agent_messages
                      allow_tool_execution = true
                    } as $agent_run_inner
                  }

                  elseif ($effective_mode == "orchestrator") {
                    ai.agent.run "Journey Map Orchestrator" {
                      args = {}|set:"messages":$agent_messages
                      allow_tool_execution = true
                    } as $agent_run_inner
                  }

                  else {
                    ai.agent.run "Journey Map Assistant" {
                      args = {}|set:"messages":$agent_messages
                      allow_tool_execution = true
                    } as $agent_run_inner
                  }
                }
              }
            }
          
            var.update $agent_run {
              value = $agent_run_inner
            }
          }
        }
      }
    
      catch {
        var.update $agent_error {
          value = $error.message
        }
      }
    }
  
    // â”€â”€ Retrieve tool trace for this turn â”€â”€
    db.query agent_tool_log {
      where = $db.agent_tool_log.turn_id == $turn_id
      sort = {execution_order: "asc", created_at: "asc"}
      return = {type: "list"}
    } as $tool_trace_raw
  
    var $tool_trace {
      value = []
    }
  
    var $trace_order {
      value = 1
    }
  
    foreach ($tool_trace_raw) {
      each as $tl {
        array.push $tool_trace {
          value = {
            tool_name      : $tl.tool_name
            tool_category  : $tl.tool_category
            input_summary  : $tl.input_summary
            output_summary : $tl.output_summary
            execution_order: $trace_order
          }
        }
      
        var.update $trace_order {
          value = $trace_order + 1
        }
      }
    }
  
    // Extract the agent result â€” guard against null when agent threw an error
    var $agent_result {
      value = $agent_run|get:"result"
    }
  
    // â”€â”€ Extract assistant reply text â”€â”€
    var $reply_text {
      value = ""
    }
  
    conditional {
      if ($agent_result != null && $agent_result != "") {
        var.update $reply_text {
          value = $agent_result
        }
      }
    }
  
    conditional {
      if ($agent_error != null && $reply_text == "") {
        var.update $reply_text {
          value = $agent_error
        }
      }
    }
  
    // â”€â”€ Extract thinking output (safe: |get returns null if field absent) â”€â”€
    var $thinking_text {
      value = $agent_run|get:"thinking"
    }
  
    // â”€â”€ Persist assistant reply â”€â”€
    conditional {
      if ($reply_text != "") {
        db.add agent_message {
          data = {
            created_at  : "now"
            conversation: $conversation.id
            role        : "assistant"
            mode        : $effective_mode
            content     : []|push:({}|set:"type":"text"|set:"text":$reply_text)
            thinking    : $thinking_text
          }
        } as $assistant_message
      }
    }
  
    // â”€â”€ Re-read cells to capture any agent-applied changes â”€â”€
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $updated_cells
  
    // â”€â”€ Detect which cells changed (BUG-07: also track actor_fields) â”€â”€
    var $cell_updates {
      value = []
    }
  
    // Build a lookup of original content AND actor_fields by cell ID
    var $original_map {
      value = {}
    }
  
    foreach ($cells) {
      each as $oc {
        var.update $original_map {
          value = $original_map
            |set:($oc.id|to_text):{content: $oc.content, actor_fields: $oc.actor_fields}
        }
      }
    }
  
    // Build lens lookup for actor_type resolution
    var $lens_actor_map {
      value = {}
    }
  
    foreach ($lenses) {
      each as $lns {
        var.update $lens_actor_map {
          value = $lens_actor_map
            |set:($lns.id|to_text):$lns.actor_type
        }
      }
    }
  
    foreach ($updated_cells) {
      each as $uc {
        var $orig_snapshot {
          value = $original_map|get:($uc.id|to_text)
        }
      
        var $orig_content {
          value = $orig_snapshot|get:"content"
        }
      
        var $actor_type {
          value = $lens_actor_map|get:($uc.lens|to_text)
        }
      
        var $content_changed {
          value = $uc.content != $orig_content
        }
      
        // Detect actor_fields filled: avoid JSON object comparison (unsafe in xs).
        // Instead: actor cell is "changed" if it NOW has at least one non-null value.
        // Re-sending already-applied values is idempotent on the frontend.
        var $actor_fields_changed {
          value = false
        }
      
        conditional {
          if ($actor_type != null && $actor_type != "") {
            conditional {
              if ($uc.actor_fields != null && ($uc.actor_fields|count) > 0) {
                var $af_keys {
                  value = $uc.actor_fields|keys
                }
              
                var $has_real {
                  value = false
                }
              
                foreach ($af_keys) {
                  each as $fk {
                    var $fv {
                      value = $uc.actor_fields|get:$fk
                    }
                  
                    conditional {
                      if ($fv != null && $fv != "") {
                        var.update $has_real {
                          value = true
                        }
                      }
                    }
                  }
                }
              
                var.update $actor_fields_changed {
                  value = $has_real
                }
              }
            }
          }
        }
      
        conditional {
          if ($content_changed || $actor_fields_changed) {
            array.push $cell_updates {
              value = {
                cell_id      : $uc.id
                stage_id     : $uc.stage
                lens_id      : $uc.lens
                content      : $uc.content
                actor_fields : $uc.actor_fields
                status       : $uc.status
                change_source: $uc.change_source
                is_locked    : $uc.is_locked
              }
            }
          }
        }
      }
    }
  
    // â”€â”€ Detect structural changes (compare stage/lens counts) â”€â”€
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $updated_stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $updated_lenses
  
    var $structural_changes {
      value = {
        stages_changed: ($updated_stages|count) != ($stages|count)
        lenses_changed: ($updated_lenses|count) != ($lenses|count)
        current_stages: $updated_stages
        current_lenses: $updated_lenses
      }
    }
  
    // â”€â”€ Compute updated progress (BUG-08: count actor cells by actor_fields, not content) â”€â”€
    var $updated_total {
      value = $updated_cells|count
    }
  
    var $updated_filled {
      value = 0
    }
  
    foreach ($updated_cells) {
      each as $fc {
        var $fc_actor_type {
          value = $lens_actor_map|get:($fc.lens|to_text)
        }
      
        var $fc_is_filled {
          value = false
        }
      
        conditional {
          if ($fc_actor_type != null && $fc_actor_type != "") {
            // Actor cell: filled when actor_fields has at least one non-null value
            conditional {
              if ($fc.actor_fields != null && ($fc.actor_fields|count) > 0) {
                var $fc_af_keys {
                  value = $fc.actor_fields|keys
                }
              
                foreach ($fc_af_keys) {
                  each as $fak {
                    var $fav {
                      value = $fc.actor_fields|get:$fak
                    }
                  
                    conditional {
                      if ($fav != null && $fav != "") {
                        var.update $fc_is_filled {
                          value = true
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        
          else {
            // Non-actor cell: filled when content is present
            var.update $fc_is_filled {
              value = $fc.content != null && $fc.content != ""
            }
          }
        }
      
        conditional {
          if ($fc_is_filled) {
            var.update $updated_filled {
              value = $updated_filled + 1
            }
          }
        }
      }
    }
  
    var $progress_pct {
      value = 0
    }
  
    conditional {
      if ($updated_total > 0) {
        var.update $progress_pct {
          value = ($updated_filled * 100) / $updated_total
        }
      }
    }
  
    // â”€â”€ Derive skipped_updates from write tool trace entries â”€â”€
    var $skipped_updates {
      value = []
    }
  
    foreach ($tool_trace_raw) {
      each as $tl {
        conditional {
          if ($tl.tool_category == "write" && $tl.output_summary != "Applied") {
            array.push $skipped_updates {
              value = {
                tool_name  : $tl.tool_name
                target     : $tl.input_summary
                skip_reason: $tl.output_summary
              }
            }
          }
        }
      }
    }

    // â”€â”€ Hallucination signal detection (US-ATL-08) â”€â”€
    // All checks are deterministic â€” no second LLM call.
    // Wrapped in try_catch so a check failure never surfaces to the user.
    var $hallucination_signals {
      value = []
    }

    var $hallucination_risk {
      value = "none"
    }

    var $write_tools_fired {
      value = 0
    }

    try_catch {
      try {
        // Count write tools that reported success (Applied)
        foreach ($tool_trace_raw) {
          each as $htl {
            conditional {
              if ($htl.tool_category == "write" && $htl.output_summary == "Applied") {
                var.update $write_tools_fired {
                  value = $write_tools_fired + 1
                }
              }
            }
          }
        }

        var $cells_actually_written {
          value = $cell_updates|count
        }

        var $tool_count_now {
          value = $tool_trace|count
        }

        // Signal: no_tools_interview
        conditional {
          if ($tool_count_now == 0 && $agent_error == null) {
            array.push $hallucination_signals {
              value = {
                type        : "no_tools_interview"
                severity    : "medium"
                detail      : ($effective_mode|to_text) ~ " turn completed with zero tool calls — LLM answered from memory, not live map data"
                auto_flagged: true
              }
            }
          }
        }

        // Signal: count_mismatch â€” write tools fired but nothing landed in DB
        conditional {
          if ($write_tools_fired > 0 && $cells_actually_written == 0) {
            api.lambda {
              code    = """
                const trace = ($var.tool_trace_raw || []);
                return trace
                  .filter(t => t.tool_category === "write" && t.output_summary === "Applied")
                  .map(t => ({ tool: t.tool_name, target: t.input_summary || null }));
              """
              timeout = 3
            } as $mismatch_offenders

            array.push $hallucination_signals {
              value = {
                type        : "count_mismatch"
                severity    : "high"
                detail      : "Write tools reported Applied (" ~ ($write_tools_fired|to_text) ~ ") but DB diff shows 0 cells changed"
                offenders   : $mismatch_offenders
                auto_flagged: true
              }
            }
          }
        }

        // Signal: step_limit_truncation â€” mode-aware thresholds
        var $step_threshold {
          value = 16
        }

        conditional {
          if ($input.builder_mode == true) {
            var.update $step_threshold { value = 12 }
          }

          elseif ($effective_mode == "orchestrator") {
            var.update $step_threshold { value = 24 }
          }

          elseif ($effective_mode == "chat") {
            var.update $step_threshold { value = 4 }
          }
        }

        conditional {
          if ($tool_count_now >= $step_threshold) {
            array.push $hallucination_signals {
              value = {
                type        : "step_limit_truncation"
                severity    : "medium"
                detail      : "tool_count=" ~ ($tool_count_now|to_text) ~ " is at or near max_steps threshold â€” reasoning may be incomplete"
                auto_flagged: true
              }
            }
          }
        }

        // Signal: zero_cells_build â€” builder looped without writing
        conditional {
          if ($cells_actually_written == 0 && $tool_count_now > 5) {
            api.lambda {
              code    = """
                const trace = ($var.tool_trace_raw || []);
                return trace.map(t => ({ tool: t.tool_name, category: t.tool_category }));
              """
              timeout = 3
            } as $zero_build_trace

            array.push $hallucination_signals {
              value = {
                type        : "zero_cells_build"
                severity    : "medium"
                detail      : ($effective_mode|to_text) ~ " mode ran " ~ ($tool_count_now|to_text) ~ " tool calls but wrote 0 cells"
                tool_trace  : $zero_build_trace
                auto_flagged: true
              }
            }
          }
        }

        // Signal: no_tools_chat — chat turn referenced map data with zero tool calls
        conditional {
          if ($effective_mode == "chat" && $tool_count_now == 0 && $agent_error == null) {
            api.lambda {
              code    = """
                const reply = ($var.reply_text || '').toLowerCase();
                const mapWords = ['map', 'stage', 'lens', 'actor', 'cell', 'gap', 'journey',
                                  'currently', 'your map', 'the map', 'filled', 'empty'];
                return mapWords.some(w => reply.includes(w));
              """
              timeout = 3
            } as $has_map_ref

            conditional {
              if ($has_map_ref == true) {
                array.push $hallucination_signals {
                  value = {
                    type        : "no_tools_chat"
                    severity    : "medium"
                    detail      : "Chat turn referenced map data with zero tool calls — LLM answered from memory, not live map"
                    auto_flagged: true
                  }
                }
              }
            }
          }
        }

        // Signal: action_without_write â€” reply claims writes but none happened
        conditional {
          if ($cells_actually_written == 0 && $write_tools_fired == 0 && $reply_text != null) {
            api.lambda {
              code    = """
                const reply = ($var.reply_text || '').toLowerCase();
                const actionWords = ['updated', 'wrote', 'filled', 'saved', 'logged',
                                     'recorded', 'written', 'added', 'captured', 'populated'];
                const matched = actionWords.filter(w => reply.includes(w));
                return { triggered: matched.length > 0, matched_words: matched };
              """
              timeout = 3
            } as $action_check

            conditional {
              if ($action_check.triggered == true) {
                array.push $hallucination_signals {
                  value = {
                    type          : "action_without_write"
                    severity      : "high"
                    detail        : "Reply contains write-action language but cells_written=0 and no write tools fired"
                    matched_words : $action_check.matched_words
                    auto_flagged  : true
                  }
                }
              }
            }
          }
        }

        // Signal: write_on_locked â€” agent tried to write locked cells
        conditional {
          if (($skipped_updates|count) > 0) {
            array.push $hallucination_signals {
              value = {
                type        : "write_on_locked"
                severity    : "low"
                detail      : ($skipped_updates|count|to_text) ~ " write(s) skipped due to locked or confirmed cells"
                offenders   : $skipped_updates
                auto_flagged: true
              }
            }
          }
        }

        // Roll up risk level from worst signal
        foreach ($hallucination_signals) {
          each as $sig {
            conditional {
              if ($sig.severity == "high") {
                var.update $hallucination_risk { value = "high" }
              }

              elseif ($sig.severity == "medium" && $hallucination_risk != "high") {
                var.update $hallucination_risk { value = "medium" }
              }

              elseif ($sig.severity == "low" && $hallucination_risk == "none") {
                var.update $hallucination_risk { value = "low" }
              }
            }
          }
        }
      }

      catch {
        // Hallucination check failed â€” non-fatal, leave signals empty and risk=none
        var $hallucination_check_failed {
          value = true
        }
      }
    }

    // â”€â”€ Build suggested prompts from remaining empty cells â”€â”€
    var $suggested_prompts {
      value = []
    }
  
    var $stage_label_lookup {
      value = {}
    }
  
    foreach ($updated_stages) {
      each as $sl {
        var.update $stage_label_lookup {
          value = $stage_label_lookup|set:($sl.id|to_text):$sl.label
        }
      }
    }
  
    var $lens_label_lookup {
      value = {}
    }
  
    foreach ($updated_lenses) {
      each as $ll {
        var.update $lens_label_lookup {
          value = $lens_label_lookup|set:($ll.id|to_text):$ll.label
        }
      }
    }
  
    var $prompt_count {
      value = 0
    }
  
    foreach ($updated_cells) {
      each as $ec {
        conditional {
          if ($prompt_count < 3 && ($ec.content == null || $ec.content == "")) {
            var $s_label {
              value = $stage_label_lookup|get:($ec.stage|to_text)
            }
          
            var $l_label {
              value = $lens_label_lookup|get:($ec.lens|to_text)
            }
          
            conditional {
              if ($s_label != null && $l_label != null) {
                array.push $suggested_prompts {
                  value = "Tell me about " ~ $l_label ~ " in " ~ $s_label
                }
              
                var.update $prompt_count {
                  value = $prompt_count + 1
                }
              }
            }
          }
        }
      }
    }
  
    // â”€â”€ Resolve turn status â”€â”€
    var $turn_status {
      value = "success"
    }

    conditional {
      if ($agent_error != null) {
        var.update $turn_status {
          value = "error"
        }
      }

      elseif ($reply_text == "" || $reply_text == null) {
        var.update $turn_status {
          value = "empty_reply"
        }
      }
    }

    // â”€â”€ Compute turn duration (US-ATL-01) â”€â”€
    var $duration_ms {
      value = null
    }

    conditional {
      if ($sentinel_id != null) {
        db.get agent_turn_log {
          field_name  = "id"
          field_value = $sentinel_id
          output      = ["started_at"]
        } as $sentinel_ts

        conditional {
          if ($sentinel_ts != null && $sentinel_ts.started_at != null) {
            api.lambda {
              code    = """
                const start = $var.sentinel_ts.started_at;
                return Date.now() - start;
              """
              timeout = 3
            } as $computed_duration

            var.update $duration_ms {
              value = $computed_duration
            }
          }
        }
      }
    }

    // â”€â”€ Extract token usage from agent run result â”€â”€
    var $tokens_input {
      value = $agent_run|get:"input_tokens"
    }

    var $tokens_output {
      value = $agent_run|get:"output_tokens"
    }

    // â”€â”€ PATCH sentinel turn log with final state (US-ATL-01 + US-ATL-02) â”€â”€
    // Wrapped in try_catch â€” a log failure must NEVER cause the user to lose their reply.
    var $turn_log {
      value = null
    }

    try_catch {
      try {
        conditional {
          if ($sentinel_id != null) {
            db.patch agent_turn_log {
              field_name  = "id"
              field_value = $sentinel_id
              data        = {
                reply_preview        : $reply_text
                tool_count           : $tool_trace|count
                cells_written        : $cell_updates|count
                status               : $turn_status
                error_message        : $agent_error
                duration_ms          : $duration_ms
                tokens_input         : $tokens_input
                tokens_output        : $tokens_output
                log_tier             : $log_tier
                hallucination_risk   : $hallucination_risk
                hallucination_signals: $hallucination_signals
              }
            } as $patched_turn_log

            var.update $turn_log {
              value = $patched_turn_log
            }
          }

          else {
            // Sentinel was never written â€” fall back to insert
            db.add agent_turn_log {
              data = {
                created_at           : "now"
                conversation         : $conversation.id
                journey_map          : $input.journey_map_id
                turn_id              : $turn_id
                mode                 : $effective_mode
                log_tier             : $log_tier
                user_message_preview : $input.content
                reply_preview        : $reply_text
                tool_count           : $tool_trace|count
                cells_written        : $cell_updates|count
                status               : $turn_status
                error_message        : $agent_error
                duration_ms          : $duration_ms
                tokens_input         : $tokens_input
                tokens_output        : $tokens_output
                hallucination_risk   : $hallucination_risk
                hallucination_signals: $hallucination_signals
              }
            } as $fallback_turn_log

            var.update $turn_log {
              value = $fallback_turn_log
            }
          }
        }
      }

      catch {
        // Turn log write failed â€” user is unaffected, response returns with turn_log=null
        var $turn_log_failed {
          value = true
        }
      }
    }

    // â”€â”€ Update conversation metadata â”€â”€
    db.patch agent_conversation {
      field_name = "id"
      field_value = $conversation.id
      data = {mode: $effective_mode, last_message_at: "now"}
    } as $conversation_record

    // â”€â”€ Reload last 50 messages for return (US-ATL-03 â€” prevents unbounded growth) â”€â”€
    // Sort desc to get the most recent 50, then reverse to chronological order.
    db.query agent_message {
      where  = $db.agent_message.conversation == $conversation.id
      sort   = {created_at: "desc"}
      return = {type: "list"}
    } as $all_messages_desc

    api.lambda {
      code    = "return ($var.all_messages_desc || []).slice(0, 50).reverse();"
      timeout = 3
    } as $all_messages

    // â”€â”€ Touch journey map â”€â”€
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $map_touch
  }

  response = {
    reply              : $reply_text
    cell_updates       : $cell_updates
    skipped_updates    : $skipped_updates
    suggested_prompts  : $suggested_prompts
    structural_changes : $structural_changes
    progress           : ```
      {
        total_cells : $updated_total
        filled_cells: $updated_filled
        percentage  : $progress_pct
      }
      ```
    tool_trace         : $tool_trace
    thinking           : $thinking_text
    turn_log           : $turn_log
    conversation       : $conversation_record
    messages           : $all_messages
    hallucination_check: ```
      {
        ran                  : true
        risk_level           : $hallucination_risk
        signals              : $hallucination_signals
        cells_claimed_vs_actual: {
          write_tools_fired     : $write_tools_fired
          cells_actually_written: $cell_updates|count
          mismatch              : $write_tools_fired > 0 && ($cell_updates|count) == 0
        }
      }
      ```
  }
  guid = "1DsxYN89rpBm53Lto6pg9xy637U"
}
