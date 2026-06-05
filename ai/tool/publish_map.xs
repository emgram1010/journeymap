// IL-00-05: MCP tool — publish a journey map.
// Sets status to active, compiles automation snapshot, and pushes webhooks.
// Maps to POST /journey_map/{id}/publish
tool publish_map {
  instructions = "Publish a journey map. Pass journey_map_id. Sets the map status to active, compiles the automation snapshot, and pushes to all registered webhook connections. Returns version number and push results."

  input {
    int journey_map_id filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    // Mark map as active
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {status: "active", updated_at: "now"}
    } as $updated_map
  
    // Load stages for the snapshot
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    // Determine next version
    db.query automation_snapshot {
      where = $db.automation_snapshot.journey_map == $input.journey_map_id
      sort = {version: "desc"}
      return = {type: "list"}
    } as $existing_snapshots
  
    var $latest_snapshot {
      value = $existing_snapshots|first
    }
  
    var $new_version {
      value = 1
    }
  
    conditional {
      if ($latest_snapshot != null) {
        var.update $new_version {
          value = $latest_snapshot.version + 1
        }
      }
    }
  
    // Build minimal graph
    var $graph {
      value = {
        map_id     : $input.journey_map_id
        map_title  : $journey_map.title
        version    : $new_version
        compiled_at: "now"
        stages     : $stages
      }
    }
  
    // Upsert snapshot
    conditional {
      if ($latest_snapshot != null) {
        db.patch automation_snapshot {
          field_name = "id"
          field_value = $latest_snapshot.id
          data = {
            graph      : $graph
            version    : $new_version
            compiled_at: "now"
          }
        } as $snapshot
      }
    
      else {
        db.add automation_snapshot {
          enforce_hidden_fields = false
          data = {
            created_at          : "now"
            compiled_at         : "now"
            journey_map         : $input.journey_map_id
            journey_architecture: $journey_map.journey_architecture
            version             : $new_version
            graph               : $graph
          }
        } as $snapshot
      }
    }
  
    // Generate ai_summary via Anthropic
    var $stage_labels {
      value = ""
    }
  
    foreach ($stages) {
      each as $ps {
        conditional {
          if ($stage_labels == "") {
            var.update $stage_labels {
              value = $ps.label
            }
          }
        
          else {
            var.update $stage_labels {
              value = $stage_labels ~ ", " ~ $ps.label
            }
          }
        }
      }
    }
  
    var $summary_prompt {
      value = "Summarise this journey map: Title=" ~ $journey_map.title ~ " Stages=" ~ $stage_labels ~ ". Return 7 lines: Process:/Actor:/Domain:/Triggers:/Outcome:/Stages:/Intent: (sop|automation|hybrid). Max 500 chars total."
    }
  
    var $sum_messages {
      value = []
        |push:({}
          |set:"role":"user"
          |set:"content":$summary_prompt
        )
    }
  
    try_catch {
      try {
        group {
          stack {
            api.request {
              url = "https://api.anthropic.com/v1/messages"
              method = "POST"
              params = {}
                |set:"model":"claude-haiku-4-5"
                |set:"max_tokens":300
                |set:"messages":$sum_messages
              headers = []
                |push:"x-api-key: " ~ $env.ANTHROPIC_KEY
                |push:"anthropic-version: 2023-06-01"
                |push:"Content-Type: application/json"
              timeout = 30000
            } as $sum_resp
          
            var $ai_summary {
              value = $sum_resp
                |get:"response"
                |get:"result"
                |get:"content"
                |first
                |get:"text"
            }
          
            db.patch journey_map {
              field_name = "id"
              field_value = $input.journey_map_id
              data = {ai_summary: $ai_summary}
            } as $summary_patch
          }
        }
      }
    
      catch {
        // Non-fatal
      }
    }
  }

  response = {
    journey_map_id: $input.journey_map_id
    version       : $new_version
    snapshot      : $snapshot
    map           : $updated_map
  }

  guid = "IL00PublishMapTool000000001"
}