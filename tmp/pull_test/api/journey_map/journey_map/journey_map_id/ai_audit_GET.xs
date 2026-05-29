// US-ATL-07 — Full audit trail query for a journey map.
// Returns turns from agent_turn_log with optional tool-call detail from agent_tool_log.
// Supports filtering by conversation, turn_id, status, hallucination_risk, and date range.
query "journey_map/{journey_map_id}/ai_audit" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id filters=min:1
  
    // Optional: scope to a specific conversation
    int conversation_id?
  
    // Optional: fetch a single turn with full tool_calls detail
    text turn_id? filters=trim
  
    // Optional: filter by turn outcome
    enum status? {
      values = ["in_progress", "success", "error", "empty_reply"]
    }
  
    // Optional: filter by hallucination risk level
    enum hallucination_risk? {
      values = ["none", "low", "medium", "high"]
    }
  
    // Optional: date range filters (ISO timestamps)
    text from_date? filters=trim
  
    text to_date? filters=trim
  
    // Page size — max 100
    int per_page?
  }

  stack {
    // ── Auth + ownership guard ──
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
  
    // ── Resolve page size ──
    var $page_size {
      value = 20
    }
  
    conditional {
      if ($input.per_page != null && $input.per_page > 0 && $input.per_page <= 100) {
        var.update $page_size {
          value = $input.per_page
        }
      }
    }
  
    // ── Build turn query ──
    // Note: WHERE expressions cannot be stored in variables in Xano XS.
    // Each filter combination requires its own db.query path.
    // We fetch all turns for this map, then filter in memory for optional fields.
  
    var $all_turns_for_map {
      value = []
    }
  
    conditional {
      if ($input.conversation_id != null) {
        db.query agent_turn_log {
          where = $db.agent_turn_log.journey_map == $input.journey_map_id && $db.agent_turn_log.conversation == $input.conversation_id
          sort = {created_at: "desc"}
          return = {type: "list"}
        } as $all_turns_for_map
      }
    
      else {
        db.query agent_turn_log {
          where = $db.agent_turn_log.journey_map == $input.journey_map_id
          sort = {created_at: "desc"}
          return = {type: "list"}
        } as $all_turns_for_map
      }
    }
  
    // Apply optional in-memory filters
    var $turns_raw {
      value = $all_turns_for_map
    }
  
    conditional {
      if ($input.turn_id != null && $input.turn_id != "") {
        var $filter_turn_id {
          value = $input.turn_id
        }
      
        api.lambda {
          code = "return ($var.turns_raw || []).filter(t => t.turn_id === $var.filter_turn_id);"
          timeout = 3
        } as $filtered
      
        var.update $turns_raw {
          value = $filtered
        }
      }
    }
  
    conditional {
      if ($input.status != null) {
        var $filter_status {
          value = $input.status
        }
      
        api.lambda {
          code = "return ($var.turns_raw || []).filter(t => t.status === $var.filter_status);"
          timeout = 3
        } as $filtered
      
        var.update $turns_raw {
          value = $filtered
        }
      }
    }
  
    conditional {
      if ($input.hallucination_risk != null) {
        var $filter_risk {
          value = $input.hallucination_risk
        }
      
        api.lambda {
          code = "return ($var.turns_raw || []).filter(t => t.hallucination_risk === $var.filter_risk);"
          timeout = 3
        } as $filtered
      
        var.update $turns_raw {
          value = $filtered
        }
      }
    }
  
    // ── Assemble canonical trace envelopes ──
    var $turns_out {
      value = []
    }
  
    foreach ($turns_raw) {
      each as $t {
        var $tool_calls {
          value = []
        }
      
        // When a specific turn_id is requested, include full tool_calls detail
        conditional {
          if ($input.turn_id != null && $input.turn_id != "") {
            db.query agent_tool_log {
              where = $db.agent_tool_log.turn_id == $t.turn_id && $db.agent_tool_log.journey_map == $input.journey_map_id
              sort = {execution_order: "asc", created_at: "asc"}
              return = {type: "list"}
            } as $tool_rows
          
            foreach ($tool_rows) {
              each as $tr {
                array.push $tool_calls {
                  value = {
                    order            : $tr.execution_order
                    name             : $tr.tool_name
                    category         : $tr.tool_category
                    duration_ms      : $tr.duration_ms
                    input_payload    : $tr.input_payload
                    output_payload   : $tr.output_payload
                    payload_truncated: $tr.payload_truncated
                    summary          : {
                      in : $tr.input_summary
                      out: $tr.output_summary
                    }
                  }
                }
              }
            }
          }
        }
      
        array.push $turns_out {
          value = {
            turn_id            : $t.turn_id
            mode               : $t.mode
            tier               : $t.log_tier
            timing             : {
              started_at : $t.started_at
              duration_ms: $t.duration_ms
            }
            tokens             : {
              input : $t.tokens_input
              output: $t.tokens_output
            }
            input              : {
              user_message      : $t.user_message_preview
              system_prompt_hash: $t.system_prompt_hash
            }
            output             : {
              reply  : $t.reply_preview
            }
            outcome            : {
              status      : $t.status
              cells_written: $t.cells_written
              error       : $t.error_message
            }
            tool_count         : $t.tool_count
            tool_calls         : $tool_calls
            hallucination_check: {
              risk_level: $t.hallucination_risk
              signals   : $t.hallucination_signals
            }
            flagged_by_user    : $t.flagged_by_user
            created_at         : $t.created_at
          }
        }
      }
    }
  }

  response = {
    journey_map_id: $input.journey_map_id
    total         : $turns_raw|count
    turns         : $turns_out
  }

  guid = "audit_trail_v1_placeholder"
}