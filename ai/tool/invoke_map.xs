// IL-03-01: Tool — invoke a journey map as a sub-execution.
// Used by the Orchestrator when an ai_agent lens has agent_map_id set.
// Creates a child workflow_execution and runs the Orchestrator on the target map.
// Circular invocation guard: rejects if target_map_id == current journey_map_id.
tool invoke_map {
  instructions = "Invoke a journey map as a sub-agent execution. Pass target_map_id (the agent_map_id from the lens), input_data (current stage context as JSON), parent_execution_id (current execution id), and subject_label. Returns { execution_id, status, final_output }. NEVER pass target_map_id equal to the current map being executed."

  input {
    int target_map_id filters=min:1
    json input_data?
    int parent_execution_id?
    text subject_label? filters=trim
  
    // Pass the current map id for circular guard
    int current_map_id?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.target_map_id, ticket: $input.ticket, tool: "invoke_map", kind: "write"}
    } as $cop1_gate

    // Circular invocation guard
    precondition ($input.target_map_id != $input.current_map_id) {
      error_type = "inputerror"
      error = "Circular map invocation: target_map_id cannot equal current_map_id"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.target_map_id
    } as $target_map
  
    precondition ($target_map != null) {
      error_type = "notfound"
      error = "Target journey map not found"
    }
  
    // Create child workflow_execution
    db.add workflow_execution {
      enforce_hidden_fields = false
      data = {
        created_at         : "now"
        updated_at         : "now"
        journey_map        : $input.target_map_id
        owner_user         : $cop1_gate.user_id
        subject_label      : $input.subject_label
        status             : "running"
        execution_mode     : "auto"
        parent_execution_id: $input.parent_execution_id
        started_at         : "now"
      }
    } as $child_exec
  
    // COP-1: the nested agent works for the same person as this tool call. A caller we could
    // not identify (report mode only) gets no ticket and the nested tools report it again.
    // COP-3: the nested ticket keeps the caller's business pin.
    var $nested_ticket {
      value = ""
    }

    conditional {
      if ($cop1_gate.user_id != 0) {
        function.run "usr/mint_tool_ticket" {
          input = {user_id: $cop1_gate.user_id, journey_map_id: $input.target_map_id, journey_architecture_id: ($cop1_gate.pin_architecture_id ?? 0), source: "invoke_map", ttl_seconds: 0}
        } as $cop1_nested

        var.update $nested_ticket {
          value = $cop1_nested.ticket
        }
      }
    }

    // Build context message for the sub-agent. COP-1 review (2026-11-14): each piped value is
    // wrapped in its own parentheses before `??` — unwrapped, the filter swallowed the rest.
    var $invoke_msg {
      value = `"## Map Invocation (Sub-Agent Mode)\nParent execution: " ~ (($input.parent_execution_id|to_text) ?? "none") ~ "\nSubject: " ~ ($input.subject_label ?? "unspecified") ~ "\nInput context: " ~ (($input.input_data|json_encode) ?? "{}") ~ "\n- ticket: " ~ $nested_ticket`
    }
  
    var $invoke_messages {
      value = []
        |push:({}
          |set:"role":"user"
          |set:"content":$invoke_msg
        )
    }
  
    var $agent_result {
      value = null
    }
  
    var $final_status {
      value = "failed"
    }
  
    try_catch {
      try {
        group {
          stack {
            ai.agent.run "Journey Map Orchestrator" {
              args = {}|set:"messages":$invoke_messages
              allow_tool_execution = true
            } as $agent_result
          
            var.update $final_status {
              value = "completed"
            }
          }
        }
      }
    
      catch {
        // Status remains failed
      }
    }
  
    // Extract final output
    var $final_output {
      value = null
    }
  
    conditional {
      if ($agent_result != null) {
        var.update $final_output {
          value = $agent_result
            |get:"messages"
            |last
            |get:"content"
        }
      }
    }
  
    // Mark child execution complete/failed
    db.patch workflow_execution {
      field_name = "id"
      field_value = $child_exec.id
      data = {
        status     : $final_status
        finished_at: "now"
        updated_at : "now"
      }
    } as $completed_exec
  }

  response = {
    execution_id: $child_exec.id
    status      : $final_status
    final_output: $final_output
    target_map  : $input.target_map_id
  }

  guid = "IL03InvokeMapTool00000000001"
}