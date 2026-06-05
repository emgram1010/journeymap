// v1.0 — Creates or updates a workflow_execution record.
// Used by Orchestrator to persist execution state after each stage advance.
// Upserts on (journey_map_id, conversation_id) when no execution_id is supplied.
tool save_workflow_state {
  instructions = """
      Use this tool to persist Orchestrator execution state.
    
      Call it in these situations:
      1. Starting a new execution run — omit execution_id to create a fresh record.
      2. After completing a stage — pass execution_id + current_stage_key + stage_output.
      3. Pausing or completing the run — pass execution_id + status.
    
      Fields:
      - execution_id: ID of an existing workflow_execution to update. Omit to create.
      - journey_map_id: Required always.
      - conversation_id: Required for a new execution; optional for updates.
      - subject_label: Short label for the subject of this run (e.g. "Jeff", "Acme").
      - subject_context: Free-form context about the subject for agent injection.
      - execution_mode: 'step' (user confirms each stage) | 'auto' (runs unattended).
      - status: pending | running | paused | completed | failed | cancelled
      - current_stage_key: The stage key currently being executed.
      - current_stage_index: Zero-based index of current stage.
      - total_stages: Total executable stages in the map.
      - stage_key_output: Stage key whose output to record (use with stage_output).
      - stage_output: Output text for the stage identified by stage_key_output.
      - validation_snapshot: Pass the full validate_workflow response on first call.
      - failure_reason: Short reason for failed/cancelled status.
    
      Response: { execution_id, status, current_stage_key, stage_outputs, updated_at }
    """

  input {
    int journey_map_id filters=min:1
    int execution_id?
    int conversation_id?
    int owner_user_id?
    text subject_label?
    text subject_context?
    enum execution_mode? {
      values = ["step", "auto"]
    }
  
    enum status? {
      values = ["pending", "running", "paused", "completed", "failed", "cancelled"]
    }
  
    text current_stage_key?
    int current_stage_index?
    int total_stages?
    text stage_key_output?
    text stage_output?
    json validation_snapshot?
    text failure_reason?
    int conversation_id_log?
    text turn_id?
  }

  stack {
    var $exec_record {
      value = null
    }
  
    // Load existing execution if ID provided
    conditional {
      if ($input.execution_id != null) {
        db.get workflow_execution {
          field_name = "id"
          field_value = $input.execution_id
        } as $exec_record
      }
    }
  
    // Merge stage output into existing stage_outputs map
    var $updated_stage_outputs {
      value = {}
    }
  
    conditional {
      if ($exec_record != null && $exec_record.stage_outputs != null) {
        var.update $updated_stage_outputs {
          value = $exec_record.stage_outputs
        }
      }
    }
  
    conditional {
      if ($input.stage_key_output != null && $input.stage_output != null) {
        var.update $updated_stage_outputs {
          value = $updated_stage_outputs
            |set:$input.stage_key_output:```
              {
                output      : $input.stage_output
                completed_at: "now"
              }
              ```
        }
      }
    }
  
    // Build patch/insert data
    var $data {
      value = {}|set:"updated_at":"now"
    }
  
    conditional {
      if ($input.subject_label != null && $input.subject_label != "") {
        var.update $data {
          value = $data
            |set:"subject_label":$input.subject_label
        }
      }
    }
  
    conditional {
      if ($input.subject_context != null && $input.subject_context != "") {
        var.update $data {
          value = $data
            |set:"subject_context":$input.subject_context
        }
      }
    }
  
    conditional {
      if ($input.execution_mode != null) {
        var.update $data {
          value = $data
            |set:"execution_mode":$input.execution_mode
        }
      }
    }
  
    conditional {
      if ($input.status != null) {
        var.update $data {
          value = $data|set:"status":$input.status
        }
      }
    }
  
    conditional {
      if ($input.current_stage_key != null) {
        var.update $data {
          value = $data
            |set:"current_stage_key":$input.current_stage_key
        }
      }
    }
  
    conditional {
      if ($input.current_stage_index != null) {
        var.update $data {
          value = $data
            |set:"current_stage_index":$input.current_stage_index
        }
      }
    }
  
    conditional {
      if ($input.total_stages != null) {
        var.update $data {
          value = $data
            |set:"total_stages":$input.total_stages
        }
      }
    }
  
    conditional {
      if ($input.validation_snapshot != null) {
        var.update $data {
          value = $data
            |set:"validation_snapshot":$input.validation_snapshot
        }
      }
    }
  
    var $result_exec {
      value = null
    }
  
    conditional {
      if ($exec_record != null) {
        // Update existing
        db.patch workflow_execution {
          field_name = "id"
          field_value = $exec_record.id
          data = $data
        } as $result_exec
      }
    
      else {
        // Create minimal record first (db.add requires inline literal)
        db.add workflow_execution {
          enforce_hidden_fields = false
          data = {
            created_at : "now"
            journey_map: $input.journey_map_id
            status     : "pending"
          }
        } as $new_exec
      
        // Enrich $data with foreign keys before patching
        var.update $data {
          value = $data
            |set:"journey_map":$input.journey_map_id
            |set:"status":$input.status ?? "pending"
        }
      
        conditional {
          if ($input.conversation_id != null) {
            var.update $data {
              value = $data
                |set:"conversation":$input.conversation_id
            }
          }
        }
      
        conditional {
          if ($input.owner_user_id != null) {
            var.update $data {
              value = $data
                |set:"owner_user":$input.owner_user_id
            }
          }
        }
      
        // Patch the new record with all dynamic fields
        db.patch workflow_execution {
          field_name = "id"
          field_value = $new_exec.id
          data = $data
        } as $result_exec
      }
    }
  
    // Tool trace logging
    conditional {
      if ($input.conversation_id_log != null && $input.turn_id != null) {
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id_log
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "save_workflow_state"
            tool_category : "workflow"
            input_summary : "execution: " ~ ($result_exec.id|to_text) ~ " stage: " ~ ($input.current_stage_key ?? "—")
            output_summary: "status: " ~ $result_exec.status
          }
        } as $sw_log
      }
    }
  }

  response = {
    execution_id     : $result_exec.id
    status           : $result_exec.status
    current_stage_key: $result_exec.current_stage_key
    stage_outputs    : $result_exec.stage_outputs
    updated_at       : $result_exec.updated_at
  }
}