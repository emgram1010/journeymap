// AI Config Extraction — reads actor_fields text from handoff/internal lenses and
// calls Claude to propose structured machine config for each stage.
// Stores results as status="draft" in stage_automation_config.
// Idempotent: re-running replaces existing draft records but never overwrites confirmed ones.
// One LLM call for the entire map — tokens spent once at configure time, never at runtime.
// v2: returns handoff_lens_found + structured gap objects + supports single-stage re-extract via stage_key
query "stage_automation_config/ai_extract" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  
    // Optional: pass a single stage_key to re-extract only that stage (US-UX-07)
    text stage_key? filters=trim
  }

  stack {
    precondition ($input.journey_map_id != null) {
      error_type = "inputerror"
      error = "journey_map_id is required"
    }
  
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
  
    // Load stages ordered by display_order
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    precondition (($stages|count) > 0) {
      error_type = "inputerror"
      error = "Journey map has no stages. Build the map before extracting automation config."
    }
  
    // Load handoff lenses for this map (actor_type = handoff — primary source for automation intent)
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.actor_type == "handoff"
      return = {type: "list"}
    } as $handoff_lenses
  
    // Expose whether a handoff lens exists at all — used by frontend to show correct failure state
    var $handoff_lens_found {
      value = ($handoff_lenses|count) > 0
    }
  
    // Load all cells for this map for efficient lookup
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $all_cells
  
    // Load existing journey_links for exception branch context
    db.query journey_link {
      where = $db.journey_link.source_map == $input.journey_map_id
      return = {type: "list"}
    } as $links
  
    // Build stage context array for the extraction prompt
    // If stage_key is provided, filter to just that stage (single-stage re-extract, US-UX-07)
    var $stage_context {
      value = []
    }
  
    foreach ($stages) {
      each as $stage {
        // Skip stages not matching the requested stage_key (when single-stage re-extract requested)
        conditional {
          if ($input.stage_key != null && $input.stage_key != "" && $stage.key != $input.stage_key) {
            continue
          }
        }
      
        // Find handoff cells for this stage
        var $handoff_fields {
          value = {}
        }
      
        foreach ($handoff_lenses) {
          each as $lens {
            foreach ($all_cells) {
              each as $cell {
                conditional {
                  if ($cell.stage == $stage.id && $cell.lens == $lens.id && $cell.actor_fields != null) {
                    var.update $handoff_fields {
                      value = $handoff_fields
                        |set:"trigger_event":($cell.actor_fields|get:"trigger_event") ?? ""
                        |set:"communication_method":($cell.actor_fields|get:"communication_method") ?? ""
                        |set:"downstream_actor":($cell.actor_fields|get:"downstream_actor") ?? ""
                        |set:"failure_recovery":($cell.actor_fields|get:"failure_recovery") ?? ""
                    }
                  }
                }
              }
            }
          }
        }
      
        // Find links originating from this stage
        var $stage_links {
          value = []
        }
      
        foreach ($links) {
          each as $link {
            foreach ($all_cells) {
              each as $cell {
                conditional {
                  if ($cell.id == $link.source_cell && $cell.stage == $stage.id) {
                    array.push $stage_links {
                      value = {}
                        |set:"link_type":$link.link_type
                        |set:"target_map_id":$link.target_map
                        |set:"label":$link.label
                    }
                  }
                }
              }
            }
          }
        }
      
        array.push $stage_context {
          value = {}
            |set:"stage_id":$stage.id
            |set:"stage_key":$stage.key
            |set:"stage_label":$stage.label
            |set:"fields":$handoff_fields
            |set:"links":$stage_links
        }
      }
    }
  
    // Build extraction prompt using concatenation (triple-quote strings are not valid in API stack vars)
    var $prompt_intro {
      value = "You are an automation configuration extractor. Read the human-readable journey stage descriptions and extract structured machine-executable config for each stage. Journey Map: " ~ $journey_map.title
    }
  
    var $prompt_schema {
      value = " For each stage return a JSON array. Each object shape: {stage_key, trigger_type (webhook|inbound_status|schedule|manual|null), trigger_config ({provider,event,filter}|null), action_type (sms|email|http_post|jobber_update|slack|none|null), action_config ({provider,template,recipient_field}|null), exception_condition ({field,op,value}|null), confidence (0.0-1.0), gaps: [{field_key, lens_type, label, hint, resolvable_inline}]}."
    }
  
    var $prompt_rules {
      value = " Rules: Set confidence<0.7 when guessing — add a structured gap object. SMS communication_method => action_type=sms. Email => action_type=email. Status change trigger_event => trigger_type=inbound_status. Linked exception map => set exception_condition from failure_recovery text. Gap field_key must be one of: trigger_event, communication_method, failure_recovery, downstream_actor. lens_type is always 'handoff'. resolvable_inline=true only for communication_method and template. hint should be a short plain-English example of what to write. Return ONLY a valid JSON array, no markdown."
    }
  
    var $extraction_prompt {
      value = $prompt_intro ~ $prompt_schema ~ $prompt_rules ~ " Stages: " ~ ($stage_context|json_encode)
    }
  
    // Call Claude for extraction
    var $anthropic_messages {
      value = []
        |push:({}
          |set:"role":"user"
          |set:"content":$extraction_prompt
        )
    }
  
    var $anthropic_auth_header {
      value = "x-api-key: " ~ $env.ANTHROPIC_KEY
    }
  
    api.request {
      url = "https://api.anthropic.com/v1/messages"
      method = "POST"
      params = {}
        |set:"model":"claude-sonnet-4-5"
        |set:"max_tokens":4096
        |set:"messages":$anthropic_messages
      headers = []
        |push:$anthropic_auth_header
        |push:"anthropic-version: 2023-06-01"
        |push:"Content-Type: application/json"
      timeout = 60000
    } as $claude_response
  
    // api.request wraps the response: { request: {...}, response: { result: <body>, status: N } }
    // Claude's actual JSON body is at response.result
    var $response_text {
      value = $claude_response
        |get:"response"
        |get:"result"
        |get:"content"
        |first
        |get:"text"
    }
  
    api.lambda {
      code = "try { var t = ($var.response_text || '').trim(); var s = t.indexOf('['); var e = t.lastIndexOf(']'); if (s !== -1 && e !== -1) { t = t.slice(s, e + 1); } return JSON.parse(t); } catch(ex) { return []; }"
      timeout = 3
    } as $proposed_configs
  
    // Store draft records — skip stages that already have confirmed configs
    var $created_count {
      value = 0
    }
  
    var $skipped_count {
      value = 0
    }
  
    foreach ($proposed_configs) {
      each as $proposal {
        // Find the stage ID from stage_key
        var $matched_stage {
          value = null
        }
      
        foreach ($stages) {
          each as $s {
            conditional {
              if ($s.key == $proposal.stage_key) {
                var.update $matched_stage {
                  value = $s
                }
              }
            }
          }
        }
      
        conditional {
          if ($matched_stage != null) {
            // Check if a confirmed record already exists for this stage
            db.query stage_automation_config {
              where = $db.stage_automation_config.journey_stage == $matched_stage.id && $db.stage_automation_config.status == "confirmed"
              return = {type: "exists"}
            } as $confirmed_exists
          
            conditional {
              if ($confirmed_exists) {
                // Skip — never overwrite confirmed config
                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }
            
              else {
                // Remove any existing draft for this stage before inserting new one
                db.query stage_automation_config {
                  where = $db.stage_automation_config.journey_stage == $matched_stage.id && $db.stage_automation_config.status == "draft"
                  return = {type: "list"}
                } as $existing_drafts
              
                foreach ($existing_drafts) {
                  each as $draft {
                    db.patch stage_automation_config {
                      field_name = "id"
                      field_value = $draft.id
                      data = {status: "disabled", updated_at: "now"}
                    }
                  }
                }
              
                db.add stage_automation_config {
                  enforce_hidden_fields = false
                  data = {
                    created_at         : "now"
                    updated_at         : "now"
                    journey_map        : $input.journey_map_id
                    journey_stage      : $matched_stage.id
                    trigger_type       : $proposal.trigger_type
                    trigger_config     : $proposal.trigger_config
                    action_type        : $proposal.action_type
                    action_config      : $proposal.action_config
                    exception_condition: $proposal.exception_condition
                    status             : "draft"
                    owner_user         : $auth.id
                  }
                }
              
                var.update $created_count {
                  value = $created_count + 1
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    journey_map_id    : $input.journey_map_id
    proposed_configs  : $proposed_configs
    created_count     : $created_count
    skipped_count     : $skipped_count
    handoff_lens_found: $handoff_lens_found
    stage_key_filter  : $input.stage_key
    debug_claude      : $claude_response
  }
}