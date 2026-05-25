// v1.0 — Reads current workflow execution state for an Orchestrator session.
// Returns the active execution for a conversation, or the most recent one for the map.
// Read-only — no writes performed.
tool get_workflow_state {
  instructions = """
      Use this tool at the start of an Orchestrator session to check for a prior
      execution run that can be resumed.
    
      Lookup priority:
      1. If execution_id is supplied — return that specific record.
      2. If conversation_id is supplied — return the active execution for that conversation.
      3. Fallback — return the most recent non-completed execution for journey_map_id.
    
      Response includes the full execution record plus a resume_prompt string that the
      orchestrator can surface to the user.
    
      If no execution exists: found = false, execution = null.
    
      Input:
      - journey_map_id: Required.
      - execution_id: (optional) Specific execution to load.
      - conversation_id: (optional) Filter by conversation.
    
      Response:
      {
        found: true/false,
        execution: { id, status, subject_label, current_stage_key, current_stage_index,
                     total_stages, stage_outputs, execution_mode, started_at, updated_at },
        resume_prompt: string | null
      }
    """

  input {
    int journey_map_id filters=min:1
    int execution_id?
    int conversation_id?
  }

  stack {
    var $found_exec {
      value = null
    }
  
    // Priority 1: specific execution ID
    conditional {
      if ($input.execution_id != null) {
        db.get workflow_execution {
          field_name = "id"
          field_value = $input.execution_id
        } as $found_exec
      }
    }
  
    // Priority 2: active execution for this conversation
    conditional {
      if ($found_exec == null && $input.conversation_id != null) {
        db.query workflow_execution {
          where = $db.workflow_execution.journey_map == $input.journey_map_id && $db.workflow_execution.conversation == $input.conversation_id
          sort = {created_at: "desc"}
          return = {type: "single"}
        } as $conv_exec
      
        conditional {
          if ($conv_exec != null) {
            var.update $found_exec {
              value = $conv_exec
            }
          }
        }
      }
    }
  
    // Priority 3: most recent non-completed execution for the map
    conditional {
      if ($found_exec == null) {
        db.query workflow_execution {
          where = $db.workflow_execution.journey_map == $input.journey_map_id && $db.workflow_execution.status != "completed" && $db.workflow_execution.status != "cancelled"
          sort = {created_at: "desc"}
          return = {type: "single"}
        } as $map_exec
      
        conditional {
          if ($map_exec != null) {
            var.update $found_exec {
              value = $map_exec
            }
          }
        }
      }
    }
  
    var $found {
      value = $found_exec != null
    }
  
    var $resume_prompt {
      value = null
    }
  
    conditional {
      if ($found_exec != null && ($found_exec.status == "paused" || $found_exec.status == "running")) {
        var.update $resume_prompt {
          value = "I found a prior execution run for "" ~ ($found_exec.subject_label ?? "this map") ~ "". It was paused at stage " ~ ($found_exec.current_stage_key ?? "unknown") ~ " (" ~ ($found_exec.current_stage_index|to_text) ~ " of " ~ ($found_exec.total_stages|to_text) ~ " stages completed). Would you like to resume from where you left off, or start a new run?"
        }
      }
    }
  }

  response = {
    found        : $found
    execution    : $found_exec
    resume_prompt: $resume_prompt
  }
}