// Exception Inbound — called by n8n/Make when an unknown exception fires at runtime.
// Creates a paused workflow_execution record so Marcus can review and resume.
// Option A (HITL only): no AI escalation. Human reviews and resumes from Emgram UI.
// n8n polls GET /journey_map/{id}/workflow_executions to detect when status changes to "running".
query "workflow_execution/exception" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  
    // The stage key where the exception occurred.
    text stage_key? filters=trim
  
    // Short description of the exception type.
    // Example: "unknown", "customer_unreachable", "vehicle_breakdown"
    text exception_type? filters=trim
  
    // Free-form context from the external tool.
    // Example: { "jobber_job_id": "4821", "driver_note": "Gate locked" }
    json context?
  
    // The automation_connection that triggered this exception (for traceability).
    int automation_connection_id?
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
  
    // Build exception_context blob
    var $exception_context {
      value = {
        stage_key       : $input.stage_key
        exception_type  : $input.exception_type ?? "unknown"
        external_context: $input.context ?? {}
        connection_id   : $input.automation_connection_id
        received_at     : "now"
        source          : "automation_inbound"
      }
    }
  
    // Create the paused execution record
    db.add workflow_execution {
      enforce_hidden_fields = false
      data = {
        created_at       : "now"
        updated_at       : "now"
        journey_map      : $input.journey_map_id
        owner_user       : $journey_map.owner_user
        subject_label    : "Automation Exception: " ~ ($input.exception_type ?? "unknown")
        status           : "paused"
        current_stage_key: $input.stage_key
        failure_reason   : "Paused by automation tool — awaiting human review"
        exception_context: $exception_context
      }
    } as $execution
  }

  response = {
    execution_id: $execution.id
    status      : "paused"
    journey_map : $input.journey_map_id
    stage_key   : $input.stage_key
    message     : "Exception recorded. Review and resume this execution in Emgram."
  }

  guid = "qBjDv2sFaXyUhOKgPnoL5eTrQWm"
}