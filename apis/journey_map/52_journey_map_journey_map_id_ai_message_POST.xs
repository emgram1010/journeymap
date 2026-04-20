// Calls Anthropic API with debug logging and error handling
query "journey_map/{journey_map_id}/ai_message" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int conversation_id?
    text content? filters=trim
    enum mode? {
      values = ["interview", "chat"]
    }
  
    json selected_cell?
    json journey_settings?
  }

  stack {
    // ── Validate inputs ──
    precondition ($input.content != null && $input.content != "") {
      error_type = "inputerror"
      error = "Message content is required"
    }
  
    precondition ($input.mode != null) {
      error_type = "inputerror"
      error = "Mode is required (interview or chat)"
    }
  
    // ── Load map bundle ──
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
  
    // ── Compute fill summary ──
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
  
    // ── Build stage and lens label lists for the system prompt ──
    var $stage_labels {
      value = []
    }
  
    foreach ($stages) {
      each as $st {
        array.push $stage_labels {
          value = "%s (%s)"|sprintf:$st.label:$st.key
        }
      }
    }
  
    var $lens_labels {
      value = []
    }
  
    foreach ($lenses) {
      each as $ln {
        conditional {
          if ($ln.description != null && $ln.description != "") {
            array.push $lens_labels {
              value = "- **%s** (%s): %s"
                |sprintf:$ln.label:$ln.key:$ln.description
            }
          }
        
          else {
            array.push $lens_labels {
              value = "- %s (%s)"|sprintf:$ln.label:$ln.key
            }
          }
        }
      }
    }
  
    // ── Build dynamic system prompt context ──
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
      value = $dynamic_context|concat:$input.mode:""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n- **Journey Map ID:** ":""
    }
  
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:($input.journey_map_id|to_text):""
    }
  
    // ── Inject journey settings context if provided ──
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
  
    // ── Inject smart AI behaviour settings directives ──
    // Use |get: filter throughout — dot notation throws a fatal error if the column doesn't exist yet.
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
                |concat:"- Write the cell with the best available content, then follow up with a probing question to deepen it toward root cause. Use a 5-Whys approach in your follow-ups — always write first, enrich second. For pain points aim to surface across turns: WHAT + WHO + HOW OFTEN + DOWNSTREAM CONSEQUENCE — never as a gate before writing.":""
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
                |concat:"- Write the factual cell content first. Then, before moving to the next topic, ask one follow-up to surface the emotional dimension: 'How does the customer feel at this exact moment — frustrated, uncertain, relieved, trusting?' If the user provides emotional context alongside their answer, capture both in the same write turn. Never withhold writing while waiting for emotional data.":""
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
                |concat:"- Write the pain point cell with whatever content is available. Then ask the one follow-up that surfaces the missing impact dimension — frequency, severity, or downstream consequence — and enrich the cell on the next turn. Target structure across turns: [What] affects [Who] [How often], causing [Business consequence]. Never withhold writing a pain point cell while waiting for this structure.":""
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
  
    // ── Inject selected cell context (if the user has a cell focused) ──
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
  
    // ── Inject actor role context for the selected cell's parent lens ──
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
  
    // ── Inject structured actor cell fields (filled vs empty) for selected cell ──
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
                  value = "\n\n## Cell Actor Fields — Current State\n"
                }
              
                var $filled_lines {
                  value = ""
                }
              
                var $empty_lines {
                  value = ""
                }
              
                // single reusable temp — declared once so it stays in scope for all inner conditionals
                var $fv_temp {
                  value = null
                }
              
                // ── Customer fields ──
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
                            |concat:"- Entry Point / Trigger: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Entry Point / Trigger\n":""
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
                            |concat:"- Feelings / Emotions: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Feelings / Emotions\n":""
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
                            |concat:"- Information Needs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information Needs\n":""
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
                            |concat:"- Decisions Required: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Decisions Required\n":""
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
                            |concat:"- Friction Points: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Friction Points\n":""
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
                            |concat:"- Assumptions: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Assumptions\n":""
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
                            |concat:"- Acceptance Criteria: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Acceptance Criteria\n":""
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
                            |concat:"- Expected Output / Confirmation: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Expected Output / Confirmation\n":""
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
                            |concat:"- Channel / Touchpoint: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Channel / Touchpoint\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Internal employee fields ──
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
                            |concat:"- Task / Objective: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Task / Objective\n":""
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
                            |concat:"- Entry Point / Trigger: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Entry Point / Trigger\n":""
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
                            |concat:"- Tools & Systems Used: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Tools & Systems Used\n":""
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
                            |concat:"- Information Needs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information Needs\n":""
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
                            |concat:"- Decisions Required: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Decisions Required\n":""
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
                            |concat:"- Friction Points: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Friction Points\n":""
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
                            |concat:"- Assumptions Being Made: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Assumptions Being Made\n":""
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
                            |concat:"- Handoff Dependencies: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Handoff Dependencies\n":""
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
                            |concat:"- Success Criteria: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Success Criteria\n":""
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
                            |concat:"- Output / Deliverable: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Output / Deliverable\n":""
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
                            |concat:"- Employee Constraints: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Employee Constraints\n":""
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
                            |concat:"- Pain Points: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Pain Points\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Engineering fields ──
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
                            |concat:"- System / Service Owner: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- System / Service Owner\n":""
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
                            |concat:"- Data Inputs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Data Inputs\n":""
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
                            |concat:"- Data Outputs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Data Outputs\n":""
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
                            |concat:"- API / Integration Dependencies: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- API / Integration Dependencies\n":""
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
                            |concat:"- Business Rules / Logic: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Business Rules / Logic\n":""
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
                            |concat:"- Error States / Edge Cases: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Error States / Edge Cases\n":""
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
                            |concat:"- Data Storage Requirements: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Storage Requirements\n":""
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
                            |concat:"- Security & Permissions: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Security & Permissions\n":""
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
                            |concat:"- Performance Requirements: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Performance Requirements\n":""
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
                            |concat:"- Audit / Logging Needs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Audit / Logging Needs\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── AI Agent fields ──
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
                            |concat:"- AI Model / Agent: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- AI Model / Agent\n":""
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
                            |concat:"- Input Data: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Input Data\n":""
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
                            |concat:"- Decision / Output: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Decision / Output\n":""
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
                            |concat:"- Confidence Threshold: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Confidence Threshold\n":""
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
                            |concat:"- Escalation Logic: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Escalation Logic\n":""
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
                            |concat:"- Training Data: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Training Data\n":""
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
                            |concat:"- Retraining Frequency: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Retraining Frequency\n":""
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
                            |concat:"- Bias & Fairness Considerations: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Bias & Fairness Considerations\n":""
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
                            |concat:"- Failure Scenarios: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Failure Scenarios\n":""
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
                            |concat:"- Performance Metrics: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Performance Metrics\n":""
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
                            |concat:"- Model Owner: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Model Owner\n":""
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
                            |concat:"- Explainability Needs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Explainability Needs\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Handoff fields ──
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
                            |concat:"- Trigger Event: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Trigger Event\n":""
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
                            |concat:"- Upstream Actor: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Upstream Actor\n":""
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
                            |concat:"- Prerequisite Data: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Prerequisite Data\n":""
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
                            |concat:"- Upstream Dependencies: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Upstream Dependencies\n":""
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
                            |concat:"- Handoff Output: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Handoff Output\n":""
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
                            |concat:"- Handoff Format: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Handoff Format\n":""
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
                            |concat:"- Handoff Timing: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Handoff Timing\n":""
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
                            |concat:"- Downstream Actor: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Downstream Actor\n":""
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
                            |concat:"- Validation Rules: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Validation Rules\n":""
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
                            |concat:"- Failure Recovery: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Failure Recovery\n":""
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
                            |concat:"- Communication Method: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Communication Method\n":""
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
                            |concat:"- Data Retention Policy: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Retention Policy\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Vendor fields ──
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
                            |concat:"- Vendor Name / Type: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Vendor Name / Type\n":""
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
                            |concat:"- Role at This Step: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Role at This Step\n":""
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
                            |concat:"- Engagement Trigger: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Engagement Trigger\n":""
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
                            |concat:"- Contractual Obligations: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Contractual Obligations\n":""
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
                            |concat:"- Information Needs: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information Needs\n":""
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
                            |concat:"- Information They Return: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Information They Return\n":""
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
                            |concat:"- Integration Method: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Integration Method\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Vendor fields (continued: fields 8-14) ──
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
                            |concat:"- SLA / Performance Metrics: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- SLA / Performance Metrics\n":""
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
                            |concat:"- Failure Scenario: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Failure Scenario\n":""
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
                            |concat:"- Escalation Path: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Escalation Path\n":""
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
                            |concat:"- Data Privacy & Compliance: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Data Privacy & Compliance\n":""
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
                            |concat:"- Vendor Constraints: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Vendor Constraints\n":""
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
                            |concat:"- Cost Impact: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Cost Impact\n":""
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
                            |concat:"- Dependency on Internal Actors: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Dependency on Internal Actors\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Financial Intelligence fields ──
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
                            |concat:"- Cost to Serve: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Cost to Serve\n":""
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
                            |concat:"- Revenue at Risk: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Revenue at Risk\n":""
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
                            |concat:"- Automation Savings: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Automation Savings\n":""
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
                            |concat:"- Upsell / Cross-sell Opportunity: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Upsell / Cross-sell Opportunity\n":""
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
                            |concat:"- Revenue Leakage: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- Revenue Leakage\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Financial Intelligence fields (continued: fields 6-10) ──
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
                            |concat:"- Cost Efficiency Note: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Cost Efficiency Note\n":""
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
                            |concat:"- Breakeven Threshold: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Breakeven Threshold\n":""
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
                            |concat:"- CAC Contribution: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- CAC Contribution\n":""
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
                            |concat:"- CLV Impact: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines|concat:"- CLV Impact\n":""
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
                            |concat:"- Financial Priority Score: ":$fv_temp:"\n":""
                        }
                      }
                    }
                  
                    conditional {
                      if ($fv_temp == null) {
                        var.update $empty_lines {
                          value = $empty_lines
                            |concat:"- Financial Priority Score\n":""
                        }
                      }
                    }
                  }
                }
              
                // ── Metrics fields ──
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
  
    // ── Load enabled capabilities and append to dynamic context ──
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
  
    // ── Resolve or create conversation ──
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
            mode           : $input.mode
            last_message_at: "now"
          }
        } as $new_conv
      
        var.update $conversation {
          value = $new_conv
        }
      }
    }
  
    // ── Load conversation history ──
    db.query agent_message {
      where = $db.agent_message.conversation == $conversation.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $history_messages
  
    // ── Build messages array for the agent ──
    // ── Persist user message first (needed to generate turn_id) ──
    db.add agent_message {
      data = {
        created_at  : "now"
        conversation: $conversation.id
        role        : "user"
        mode        : $input.mode
        content     : []|push:({}|set:"type":"text"|set:"text":$input.content)
      }
    } as $user_message
  
    // ── Generate turn_id for tool trace logging ──
    var $turn_id {
      value = "turn_" ~ $conversation.id ~ "_" ~ $user_message.id
    }
  
    // ── Inject journey_map_id, conversation_id and turn_id into dynamic context ──
    // ALL THREE must be passed to every tool call — the agent reads this section.
    var.update $dynamic_context {
      value = $dynamic_context
        |concat:"\n\n### Tool Logging (pass to every tool call)\n":""
        |concat:"- journey_map_id: " ~ ($input.journey_map_id|to_text):""
        |concat:"\n- conversation_id: " ~ $conversation.id:""
        |concat:"\n- turn_id: " ~ $turn_id:""
    }
  
    // ── Build messages array (system uses the NOW-complete context) ──
    var $agent_messages {
      value = []
    }
  
    array.push $agent_messages {
      value = {role: "system", content: $dynamic_context}
    }
  
    // ── Cap conversation history to a predictable window (last 20 messages) ──
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
  
    // ── Call the agent (with error capture for turn logging) ──
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
            ai.agent.run "Journey Map Assistant" {
              args = {}|set:"messages":$agent_messages
              allow_tool_execution = true
            } as $agent_run_inner
          
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
  
    // ── Retrieve tool trace for this turn ──
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
  
    // Extract the agent result — guard against null when agent threw an error
    var $agent_result {
      value = $agent_run|get:"result"
    }
  
    // ── Extract assistant reply text ──
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
  
    // ── Extract thinking output (safe: |get returns null if field absent) ──
    var $thinking_text {
      value = $agent_run|get:"thinking"
    }
  
    // ── Persist assistant reply ──
    conditional {
      if ($reply_text != "") {
        db.add agent_message {
          data = {
            created_at  : "now"
            conversation: $conversation.id
            role        : "assistant"
            mode        : $input.mode
            content     : []|push:({}|set:"type":"text"|set:"text":$reply_text)
            thinking    : $thinking_text
          }
        } as $assistant_message
      }
    }
  
    // ── Re-read cells to capture any agent-applied changes ──
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $updated_cells
  
    // ── Detect which cells changed ──
    var $cell_updates {
      value = []
    }
  
    // Build a lookup of original cell content by ID
    var $original_map {
      value = {}
    }
  
    foreach ($cells) {
      each as $oc {
        var.update $original_map {
          value = $original_map|set:($oc.id|to_text):$oc.content
        }
      }
    }
  
    foreach ($updated_cells) {
      each as $uc {
        var $orig_content {
          value = $original_map|get:($uc.id|to_text)
        }
      
        conditional {
          if ($uc.content != $orig_content) {
            array.push $cell_updates {
              value = {
                cell_id      : $uc.id
                stage_id     : $uc.stage
                lens_id      : $uc.lens
                content      : $uc.content
                status       : $uc.status
                change_source: $uc.change_source
                is_locked    : $uc.is_locked
              }
            }
          }
        }
      }
    }
  
    // ── Detect structural changes (compare stage/lens counts) ──
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
  
    // ── Compute updated progress ──
    var $updated_total {
      value = $updated_cells|count
    }
  
    var $updated_filled {
      value = 0
    }
  
    foreach ($updated_cells) {
      each as $fc {
        conditional {
          if ($fc.content != null && $fc.content != "") {
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
  
    // ── Derive skipped_updates from write tool trace entries ──
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
  
    // ── Build suggested prompts from remaining empty cells ──
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
  
    // ── Write agent_turn_log ──
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
  
    db.add agent_turn_log {
      data = {
        created_at          : "now"
        conversation        : $conversation.id
        journey_map         : $input.journey_map_id
        turn_id             : $turn_id
        mode                : $input.mode
        user_message_preview: $input.content
        reply_preview       : $reply_text
        tool_count          : $tool_trace|count
        cells_written       : $cell_updates|count
        status              : $turn_status
        error_message       : $agent_error
      }
    } as $turn_log
  
    // ── Update conversation metadata ──
    db.patch agent_conversation {
      field_name = "id"
      field_value = $conversation.id
      data = {mode: $input.mode, last_message_at: "now"}
    } as $conversation_record
  
    // ── Reload all messages for return ──
    db.query agent_message {
      where = $db.agent_message.conversation == $conversation.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $all_messages
  
    // ── Touch journey map ──
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $map_touch
  }

  response = {
    reply             : $reply_text
    cell_updates      : $cell_updates
    skipped_updates   : $skipped_updates
    suggested_prompts : $suggested_prompts
    structural_changes: $structural_changes
    progress          : ```
      {
        total_cells : $updated_total
        filled_cells: $updated_filled
        percentage  : $progress_pct
      }
      ```
    tool_trace        : $tool_trace
    thinking          : $thinking_text
    turn_log          : $turn_log
    conversation      : $conversation_record
    messages          : $all_messages
  }
}