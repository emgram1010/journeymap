// Publish a journey map: sets status to "active", compiles the automation snapshot
// (confirmed stage_automation_config + journey_link graph), and pushes to all
// registered automation_connection webhook URLs.
// Compile is atomic — snapshot only updates if compile succeeds without error.
//
// PUB-1: behind the account flag `publish_gate`, this endpoint also
// (a) refuses to publish a map that isn't ready, before writing anything,
// and (b) freezes an immutable journey_map_version row in the same
// transaction as the status change and the automation snapshot.
// With the flag OFF the behaviour is exactly what it was before PUB-1:
// no gate, no version row.
//
// The status change moved: it used to run before the compile, which left a
// map marked active with a stale snapshot whenever the compile failed. It
// is now inside the transaction with the snapshot and the version, so the
// three either all land or none do (US-PUB-1-03, GOV-1 atomicity).
query "journey_map/{journey_map_id}/publish" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    // `|to_int` up front: bare `now` is a numeric ms timestamp, but inside
    // an object literal it is parsed as the magic "now" token instead, so
    // the subtraction has to happen in a var (confirmed live — the first
    // push of this endpoint failed with "Not numeric." doing it inline).
    var $started_at {
      value = now|to_int
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

    // ── PUB-1 gate (flagged) ─────────────────────────────────────────────────
    // Everything in this block runs BEFORE the first write, so a rejection
    // leaves the map exactly as it was: still draft, no version, no compile,
    // no webhook (US-PUB-1-02).
    function.run "ops/feature_enabled" {
      input = {
        account_id: $journey_map.account_id
        flag_key  : "publish_gate"
      }
    } as $gate_flag

    var $gate {
      value = null
    }

    var $frozen_snapshot {
      value = null
    }

    conditional {
      if ($gate_flag.enabled == true) {
        conditional {
          if ($journey_map.status == "archived") {
            function.run "ops/log_event" {
              input = {
                feature    : "PUB-1"
                step       : "publish_version"
                outcome    : "rejected"
                severity   : "info"
                error_code : "E-PUB-005"
                message    : "Publish refused: the map is archived."
                user_id    : $auth.id
                account_id : $journey_map.account_id
                entity_type: "journey_map"
                entity_id  : $input.journey_map_id
              }
            } as $_archived_logged
          }
        }

        precondition ($journey_map.status != "archived") {
          error_type = "inputerror"
          error = "This map is archived and can't be published. (E-PUB-005)"
        }

        function.run "pub/build_map_snapshot" {
          input = {journey_map_id: $input.journey_map_id}
        } as $snapshot_result

        var.update $frozen_snapshot {
          value = $snapshot_result.snapshot
        }

        function.run "pub/evaluate_gate" {
          input = {snapshot: $snapshot_result.snapshot, account_id: $journey_map.account_id}
        } as $gate_result

        var.update $gate {
          value = $gate_result
        }

        // RATE-1 (US-RATE-1-04) — an inactive item pinned by a rate gets
        // its own code, message and event (E-RATE-001), ahead of the
        // generic "not ready" refusal, so the user is told exactly which
        // item to fix. The condition reads the loop item only.
        var $inactive_item_count {
          value = 0
        }

        var $inactive_item_message {
          value = ""
        }

        var $inactive_item_keys {
          value = []
        }

        var $gate_failure_list {
          value = $gate_result.gate_failures ?? []
        }

        foreach ($gate_failure_list) {
          each as $gate_failure {
            conditional {
              if ($gate_failure.code == "INACTIVE_ITEM") {
                var.update $inactive_item_count {
                  value = $inactive_item_count + 1
                }

                var.update $inactive_item_message {
                  value = $gate_failure.message
                }

                array.push $inactive_item_keys {
                  value = $gate_failure.item_key
                }
              }
            }
          }
        }

        conditional {
          if ($inactive_item_count > 0) {
            function.run "ops/log_event" {
              input = {
                feature    : "RATE-1"
                step       : "publish_blocked_inactive_item"
                outcome    : "rejected"
                severity   : "info"
                error_code : "E-RATE-001"
                message    : $inactive_item_message
                user_id    : $auth.id
                account_id : $journey_map.account_id
                entity_type: "journey_map"
                entity_id  : $input.journey_map_id
                metadata   : {item_keys: $inactive_item_keys}
              }
            } as $_inactive_logged
          }
        }

        var $inactive_item_error {
          value = $inactive_item_message ~ " (E-RATE-001)"
        }

        precondition ($inactive_item_count == 0) {
          error_type = "inputerror"
          error = $inactive_item_error
        }

        conditional {
          if ($gate_result.ready != true) {
            function.run "ops/log_event" {
              input = {
                feature    : "PUB-1"
                step       : "publish_version"
                outcome    : "rejected"
                severity   : "info"
                error_code : "E-PUB-001"
                message    : "Publish refused: the map isn't ready yet."
                user_id    : $auth.id
                account_id : $journey_map.account_id
                entity_type: "journey_map"
                entity_id  : $input.journey_map_id
                metadata   : {blocker_count: ($gate_result.gate_failures|count), ready_count: $gate_result.ready_count, total: $gate_result.total}
              }
            } as $_gate_logged
          }
        }

        precondition ($gate_result.ready == true) {
          error_type = "inputerror"
          error = "This map isn't ready yet. Open the checklist to see what needs attention. (E-PUB-001)"
        }
      }
    }

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
  
    // ── PUB-1: work out the next version number and hash BEFORE the write ───
    // Both are read-only/pure, so they stay outside the transaction and
    // keep it to plain database writes.
    var $map_version_no {
      value = 0
    }

    var $map_version_hash {
      value = null
    }

    // RATE-1 — the rows stage_rate gets, taken from the SAME frozen
    // snapshot that is hashed (one fact, two shapes). Empty for a v1
    // snapshot and whenever the gate flag is off.
    var $rates_to_write {
      value = []
    }

    conditional {
      if ($gate_flag.enabled == true) {
        db.query journey_map_version {
          where = $db.journey_map_version.journey_map_id == $input.journey_map_id
          return = {type: "list"}
        } as $existing_versions

        var $max_version_no {
          value = 0
        }

        foreach ($existing_versions) {
          each as $prev_version {
            conditional {
              if ($prev_version.version_no > $max_version_no) {
                var.update $max_version_no {
                  value = $prev_version.version_no
                }
              }
            }
          }
        }

        // Two publishes racing would compute the same number; the unique
        // index on (journey_map_id, version_no) makes the loser fail, which
        // fails its publish. That is the correct outcome — better a retry
        // than two rows claiming to be the same version.
        var.update $map_version_no {
          value = $max_version_no + 1
        }

        function.run "pub/canonical_hash" {
          input = {snapshot: $frozen_snapshot}
        } as $hash_result

        var.update $map_version_hash {
          value = $hash_result.hash
        }

        var.update $rates_to_write {
          value = $frozen_snapshot.rates ?? []
        }
      }
    }

    var $rates_written {
      value = $rates_to_write|count
    }

    var $map_version {
      value = null
    }

    db.transaction {
      description = "PUB-1: the status change, the automation snapshot and the frozen version all land, or none do. RATE-1: plus the stage_rate rows."
      stack {
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {status: "active", updated_at: "now"}
        } as $updated_map

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

        conditional {
          if ($gate_flag.enabled == true) {
            db.add journey_map_version {
              enforce_hidden_fields = false
              data = {
                created_at            : "now"
                journey_map_id        : $input.journey_map_id
                version_no            : $map_version_no
                snapshot              : $frozen_snapshot
                content_hash          : $map_version_hash
                readiness_report      : $gate
                automation_snapshot_id: $snapshot.id
                published_by          : $auth.id
                published_at          : "now"
              }
            } as $written_version

            var.update $map_version {
              value = $written_version
            }

            // RATE-1 (US-RATE-1-04) — the rate card, in the same
            // transaction as its version: both land or neither does.
            foreach ($rates_to_write) {
              each as $rate_row {
                db.add stage_rate {
                  data = {
                    created_at            : "now"
                    journey_map_version_id: $written_version.id
                    stage_key             : $rate_row.stage_key
                    quantity_key          : $rate_row.quantity_key
                    method_key            : $rate_row.method_key
                    minutes_per_unit      : $rate_row.minutes_per_unit
                    source                : $rate_row.source
                  }
                } as $_rate_added
              }
            }
          }
        }
      }
    }

    conditional {
      if ($gate_flag.enabled == true) {
        function.run "ops/log_event" {
          input = {
            feature    : "RATE-1"
            step       : "rates_materialized"
            outcome    : "success"
            severity   : "info"
            user_id    : $auth.id
            account_id : $journey_map.account_id
            entity_type: "journey_map_version"
            entity_id  : $map_version.id
            metadata   : {rates_written: $rates_written, journey_map_id: $input.journey_map_id, map_version_no: $map_version_no}
          }
        } as $_rates_logged
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

    // PUB-1 / OBS-1 — one success event per completed publish, carrying the
    // version number and how long it took. The Health page reads the most
    // recent of these for "time of the last successful publish".
    var $finished_at {
      value = now|to_int
    }

    var $publish_duration_ms {
      value = $finished_at - $started_at
    }

    function.run "ops/log_event" {
      input = {
        feature    : "PUB-1"
        step       : "publish_version"
        outcome    : "success"
        severity   : "info"
        user_id    : $auth.id
        account_id : $journey_map.account_id
        entity_type: "journey_map"
        entity_id  : $input.journey_map_id
        duration_ms: $publish_duration_ms
        metadata   : {map_version_no: $map_version_no, automation_version: $new_version, gate_enabled: $gate_flag.enabled}
      }
    } as $_publish_logged
  }

  response = {
    journey_map : $updated_map
    snapshot    : $snapshot
    version     : $new_version
    push_results: $push_results
    // PUB-1 additions. Both are null when the publish_gate flag is off, so
    // existing callers see the same four fields they always did.
    map_version : $map_version
    gate        : $gate
    // RATE-1 — stage_rate rows written with this version (0 when the gate
    // flag is off or the map has no Items row).
    rates_written: $rates_written
  }
}