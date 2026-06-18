// Publish a journey map: sets status to "active", compiles the automation snapshot
// (confirmed stage_automation_config + journey_link graph), and pushes to all
// registered automation_connection webhook URLs.
// Compile is atomic — snapshot only updates if compile succeeds without error.
query "journey_map/{journey_map_id}/publish" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
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
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Mark map as active
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {status: "active", updated_at: "now"}
    } as $updated_map
  
    // ── Compile step ─────────────────────────────────────────────────────────
    // Load all confirmed stage configs for this map
    db.query stage_automation_config {
      where = $db.stage_automation_config.journey_map == $input.journey_map_id && $db.stage_automation_config.status == "confirmed"
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $configs
  
    // Load stages for label/key lookup
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    // Load journey_links from this map
    db.query journey_link {
      where = $db.journey_link.source_map == $input.journey_map_id
      return = {type: "list"}
    } as $links
  
    // Load source cells for link lookup
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $source_cells
  
    // Build stage objects for the graph
    var $graph_stages {
      value = []
    }
  
    foreach ($stages) {
      each as $stage {
        // Find the config for this stage (may be null if no automation configured)
        var $stage_config {
          value = null
        }
      
        foreach ($configs) {
          each as $cfg {
            conditional {
              if ($cfg.journey_stage == $stage.id) {
                var.update $stage_config {
                  value = $cfg
                }
              }
            }
          }
        }
      
        // Find links originating from cells in this stage
        var $stage_links {
          value = []
        }
      
        foreach ($links) {
          each as $link {
            foreach ($source_cells) {
              each as $cell {
                conditional {
                  if ($cell.id == $link.source_cell && $cell.stage == $stage.id) {
                    // Load target map's confirmed configs (one level deep for sub-maps)
                    db.query stage_automation_config {
                      where = $db.stage_automation_config.journey_map == $link.target_map && $db.stage_automation_config.status == "confirmed"
                      sort = {created_at: "asc"}
                      return = {type: "list"}
                    } as $target_configs
                  
                    db.query journey_stage {
                      where = $db.journey_stage.journey_map == $link.target_map
                      sort = {display_order: "asc"}
                      return = {type: "list"}
                    } as $target_stages
                  
                    db.get journey_map {
                      field_name = "id"
                      field_value = $link.target_map
                    } as $target_map_record
                  
                    // Build target stage objects
                    var $target_stage_objects {
                      value = []
                    }
                  
                    foreach ($target_stages) {
                      each as $ts {
                        var $ts_config {
                          value = null
                        }
                      
                        foreach ($target_configs) {
                          each as $tc {
                            conditional {
                              if ($tc.journey_stage == $ts.id) {
                                var.update $ts_config {
                                  value = $tc
                                }
                              }
                            }
                          }
                        }
                      
                        array.push $target_stage_objects {
                          value = {
                            key                : $ts.key
                            label              : $ts.label
                            trigger_type       : $ts_config.trigger_type
                            trigger_config     : $ts_config.trigger_config
                            action_type        : $ts_config.action_type
                            action_config      : $ts_config.action_config
                            exception_condition: $ts_config.exception_condition
                            links              : []
                          }
                        }
                      }
                    }
                  
                    // Get exception_condition from the source stage's config for this link
                    var $link_condition {
                      value = null
                    }
                  
                    conditional {
                      if ($stage_config != null) {
                        var.update $link_condition {
                          value = $stage_config.exception_condition
                        }
                      }
                    }
                  
                    array.push $stage_links {
                      value = {
                        link_type        : $link.link_type
                        condition        : $link_condition
                        target_map_id    : $link.target_map
                        target_map_label : $target_map_record.title
                        target_map_stages: $target_stage_objects
                      }
                    }
                  }
                }
              }
            }
          }
        }
      
        array.push $graph_stages {
          value = {
            key                : $stage.key
            label              : $stage.label
            trigger_type       : $stage_config.trigger_type
            trigger_config     : $stage_config.trigger_config
            action_type        : $stage_config.action_type
            action_config      : $stage_config.action_config
            exception_condition: $stage_config.exception_condition
            links              : $stage_links
          }
        }
      }
    }
  
    // Determine new version number
    db.query automation_snapshot {
      where = $db.automation_snapshot.journey_map == $input.journey_map_id
      sort = {version: "desc"}
      return = {type: "list"}
    } as $existing_snapshots
  
    var $existing_snapshot {
      value = $existing_snapshots|first
    }
  
    var $new_version {
      value = 1
    }
  
    conditional {
      if ($existing_snapshot != null) {
        var.update $new_version {
          value = $existing_snapshot.version + 1
        }
      }
    }
  
    // Build final graph object
    var $graph {
      value = {
        map_id     : $input.journey_map_id
        map_title  : $journey_map.title
        version    : $new_version
        compiled_at: "now"
        stages     : $graph_stages
      }
    }
  
    // Upsert snapshot
    conditional {
      if ($existing_snapshot != null) {
        db.patch automation_snapshot {
          field_name = "id"
          field_value = $existing_snapshot.id
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
            owner_user          : $journey_map.owner_user
          }
        } as $snapshot
      }
    }
  
    // ── IL-01-03: Auto-generate ai_summary via LLM ───────────────────────────
    // Build stage label list for the prompt
    var $summary_stage_labels {
      value = ""
    }
  
    foreach ($stages) {
      each as $sum_stage {
        conditional {
          if ($summary_stage_labels == "") {
            var.update $summary_stage_labels {
              value = $sum_stage.label
            }
          }
        
          else {
            var.update $summary_stage_labels {
              value = $summary_stage_labels ~ ", " ~ $sum_stage.label
            }
          }
        }
      }
    }
  
    var $map_context_for_summary {
      value = "Map title: " ~ $journey_map.title ~ " | Stages: " ~ $summary_stage_labels ~ " | Scope: " ~ ($journey_map.journey_scope ?? "") ~ " | Primary actor: " ~ ($journey_map.primary_actor ?? "") ~ " | Start: " ~ ($journey_map.start_point ?? "") ~ " | End: " ~ ($journey_map.end_point ?? "")
    }
  
    var $summary_prompt_text {
      value = "Summarise this journey map for a search index. Use EXACTLY this 7-line format:\n\nProcess: [one sentence]\nActor: [primary actor]\nDomain: [industry/function]\nTriggers: [what starts it]\nOutcome: [what it produces]\nStages: " ~ $summary_stage_labels ~ "\nIntent: [sop | automation | hybrid]\n\nMap: " ~ $map_context_for_summary ~ "\n\nOutput the 7 lines only. No extra text. Max 500 chars total."
    }
  
    var $summary_messages {
      value = []
        |push:({}
          |set:"role":"user"
          |set:"content":$summary_prompt_text
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
                |set:"messages":$summary_messages
              headers = []
                |push:"x-api-key: " ~ $env.ANTHROPIC_KEY
                |push:"anthropic-version: 2023-06-01"
                |push:"Content-Type: application/json"
              timeout = 30000
            } as $summary_api_response
          
            var $ai_summary_text {
              value = $summary_api_response
                |get:"response"
                |get:"result"
                |get:"content"
                |first
                |get:"text"
            }
          
            db.patch journey_map {
              field_name = "id"
              field_value = $input.journey_map_id
              data = {ai_summary: $ai_summary_text, updated_at: "now"}
            } as $summary_patch
          }
        }
      }
    
      catch {
        // Non-fatal — publish succeeds even if summary generation fails.
        // ai_summary remains null; will be generated on next publish.
      }
    }
  
    // ── Webhook push to registered connections ───────────────────────────────
    db.query automation_connection {
      where = $db.automation_connection.journey_architecture == $journey_map.journey_architecture && $db.automation_connection.status == "active"
      return = {type: "list"}
    } as $connections
  
    var $push_results {
      value = []
    }
  
    foreach ($connections) {
      each as $conn {
        var $push_payload {
          value = {
            event   : "snapshot_updated"
            map_id  : $input.journey_map_id
            version : $new_version
            snapshot: $graph
          }
        }
      
        try_catch {
          try {
            group {
              stack {
                api.request {
                  url = $conn.webhook_url
                  method = "POST"
                  params = $push_payload
                  headers = ["Content-Type: application/json"]
                } as $push_response
              
                db.patch automation_connection {
                  field_name = "id"
                  field_value = $conn.id
                  data = {
                    status            : "active"
                    last_pushed_at    : "now"
                    last_error_message: null
                    updated_at        : "now"
                  }
                }
              
                array.push $push_results {
                  value = {
                    connection_id: $conn.id
                    label        : $conn.label
                    success      : true
                  }
                }
              }
            }
          }
        
          catch {
            db.patch automation_connection {
              field_name = "id"
              field_value = $conn.id
              data = {
                status            : "error"
                last_error_message: "Webhook push failed"
                updated_at        : "now"
              }
            }
          
            array.push $push_results {
              value = {
                connection_id: $conn.id
                label        : $conn.label
                success      : false
              }
            }
          }
        }
      }
    }
  }

  response = {
    journey_map : $updated_map
    snapshot    : $snapshot
    version     : $new_version
    push_results: $push_results
  }
}