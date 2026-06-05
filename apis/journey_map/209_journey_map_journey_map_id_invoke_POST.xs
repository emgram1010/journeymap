// IL-03-01: Map Invocation Protocol — Map A calls Map B and receives structured output.
// Creates a child workflow_execution linked to the parent via parent_execution_id.
// Circular invocation is rejected (a map cannot invoke itself).
// The orchestrator agent is run on the target map with input_data injected as context.
query "journey_map/{journey_map_id}/invoke" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  
    // Structured context to pass into the sub-map's execution as starting input.
    json input_data?
  
    // The workflow_execution id of the calling map — links parent → child.
    int parent_execution_id?
  
    // Domain subject being processed (e.g. "lead_42", "Acme Corp").
    text subject_id? filters=trim
  
    text subject_label? filters=trim
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $target_map
  
    precondition ($target_map != null) {
      error_type = "notfound"
      error = "Target journey map not found"
    }
  
    // Circular invocation guard — check parent execution's map is not the same map
    conditional {
      if ($input.parent_execution_id != null) {
        db.get workflow_execution {
          field_name = "id"
          field_value = $input.parent_execution_id
        } as $parent_exec
      
        precondition ($parent_exec == null || $parent_exec.journey_map != $input.journey_map_id) {
          error_type = "inputerror"
          error = "Circular map invocation detected: a map cannot invoke itself"
        }
      }
    }
  
    // Create child workflow_execution linked to parent
    db.add workflow_execution {
      enforce_hidden_fields = false
      data = {
        created_at         : "now"
        updated_at         : "now"
        journey_map        : $input.journey_map_id
        owner_user         : $auth.id
        subject_label      : $input.subject_label
        status             : "running"
        execution_mode     : "auto"
        parent_execution_id: $input.parent_execution_id
        started_at         : "now"
      }
    } as $child_exec
  
    // Build agent messages — inject input_data as the opening context
    var $invoke_context {
      value = `"## Map Invocation\nThis map has been invoked programmatically.\nParent execution ID: " ~ ($input.parent_execution_id|to_text ?? "none") ~ "\nSubject: " ~ ($input.subject_label ?? $input.subject_id ?? "unspecified") ~ "\nInput context:\n" ~ ($input.input_data|json_encode ?? "{}")`
    }
  
    var $invoke_messages {
      value = []
        |push:({}
          |set:"role":"user"
          |set:"content":$invoke_context
        )
    }
  
    // Run the orchestrator agent on the target map in auto mode
    var $agent_result {
      value = null
    }
  
    try_catch {
      try {
        group {
          stack {
            ai.agent.run "Journey Map Orchestrator" {
              args = {}|set:"messages":$invoke_messages
              allow_tool_execution = true
            } as $agent_result
          }
        }
      }
    
      catch {
        db.patch workflow_execution {
          field_name = "id"
          field_value = $child_exec.id
          data = {
            status        : "failed"
            failure_reason: "Agent run failed during map invocation"
            finished_at   : "now"
            updated_at    : "now"
          }
        } as $failed_exec
      }
    }
  
    // Extract final output text from agent result
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
  
    // Mark child execution complete
    var $final_status {
      value = "completed"
    }
  
    conditional {
      if ($agent_result == null) {
        var.update $final_status {
          value = "failed"
        }
      }
    }
  
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
    journey_map : $input.journey_map_id
  }
}