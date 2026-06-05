// Returns workflow execution history for a journey map.
// Supports filtering by status and sorting newest-first.
// US-WE-18
query "journey_map/{journey_map_id}/workflow_executions" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id filters=min:1
  
    // Optional status filter: pending | running | paused | completed | failed | cancelled
    enum status? {
      values = ["pending", "running", "paused", "completed", "failed", "cancelled"]
    }
  
    // Max records to return (default 20, max 100).
    int limit?=20
  }

  stack {
    var $query_limit {
      value = $input.limit ?? 20
    }
  
    conditional {
      if ($query_limit > 100) {
        var.update $query_limit {
          value = 100
        }
      }
    }
  
    conditional {
      if ($input.status != null) {
        db.query workflow_execution {
          where = $db.workflow_execution.journey_map == $input.journey_map_id && $db.workflow_execution.status == $input.status
          sort = {created_at: "desc"}
          return = {type: "list"}
        } as $executions
      }
    
      else {
        db.query workflow_execution {
          where = $db.workflow_execution.journey_map == $input.journey_map_id
          sort = {created_at: "desc"}
          return = {type: "list"}
        } as $executions
      }
    }
  
    // Find the active (running/paused) execution if any
    var $active_execution {
      value = null
    }
  
    foreach ($executions) {
      each as $ex {
        conditional {
          if ($active_execution == null && ($ex.status == "running" || $ex.status == "paused")) {
            var.update $active_execution {
              value = $ex
            }
          }
        }
      }
    }
  }

  response = {
    journey_map_id  : $input.journey_map_id
    executions      : $executions
    active_execution: $active_execution
    total           : $executions|count
  }

  guid = "WadEv66F2TDKErUlmbVYbHwfr8Q"
}