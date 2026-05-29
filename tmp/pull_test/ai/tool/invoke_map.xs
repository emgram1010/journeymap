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
  }

  stack {
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
      data = {
        created_at         : "now"
        updated_at         : "now"
        journey_map        : $input.target_map_id
        subject_label      : $input.subject_label
        status             : "running"
        execution_mode     : "auto"
        parent_execution_id: $input.parent_execution_id
        started_at         : "now"
      }
    } as $child_exec
  
    // Build context message for the sub-agent
    var $invoke_msg {
      value = `"## Map Invocation (Sub-Agent Mode)\nParent execution: " ~ ($input.parent_execution_id|to_text ?? "none") ~ "\nSubject: " ~ ($input.subject_label ?? "unspecified") ~ "\nInput context: " ~ ($input.input_data|json_encode ?? "{}")`
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