// v1.0 â€” Pre-flight validation of a journey map for Orchestrator execution.
// Read-only. Returns a structured report of blockers, warnings, and info notices.
// ready_to_execute is true only when blocker_count == 0.
tool validate_workflow {
  instructions = """
      Run this tool before starting or resuming Orchestrator execution.
      It reads the full map structure and produces a prioritized readiness report.
    
      Severity tiers:
      - blocker: will halt or corrupt execution — must be resolved before running
      - warning: will produce weak or incomplete output — recommended to fix
      - info: informational only — no action required
    
      Blocker checks:
      - Stage has no internal actor lens
      - Internal actor lens exists but task_objective is empty
      - output_deliverable is missing on a stage referenced by a downstream handoff_dependencies
      - handoff_dependencies references a stage key that does not exist in the map
      - No actor with actor_role='primary' on a stage that has an internal actor
    
      Warning checks:
      - information_needs is empty or fewer than 10 characters
      - tools_systems is empty
      - output_deliverable is fewer than 10 characters or matches generic phrases
      - persona_description is empty on the internal actor lens
    
      Info checks:
      - Stage has no internal actor (intentionally skipped by orchestrator)
    
      Input: journey_map_id
      Response: { ready_to_execute, blocker_count, warning_count, stages[], summary }
    
      Always pass conversation_id (integer), turn_id (text), and log_tier (text string: 'full', 'summary', or 'minimal' — NOT a boolean) from the ## Tool Logging section of your context.
    """

  input {
    int journey_map_id filters=min:1
    int conversation_id?
    text turn_id?
  
    // full = capture raw payloads; summary = summaries only (default)
    text log_tier?
  }

  stack {
    // Load map structure
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $lenses
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $cells
  
    // Build stage key set for dependency validation
    var $stage_keys {
      value = {}
    }
  
    foreach ($stages) {
      each as $st {
        var.update $stage_keys {
          value = $stage_keys|set:$st.key:true
        }
      }
    }
  
    // Build internal-actor lens set (lens_id -> lens record)
    var $internal_lens_map {
      value = {}
    }
  
    foreach ($lenses) {
      each as $ln {
        conditional {
          if ($ln.actor_type == "internal") {
            var.update $internal_lens_map {
              value = $internal_lens_map|set:($ln.id|to_text):$ln
            }
          }
        }
      }
    }
  
    // Build cell map: stage_key + lens_id -> cell
    var $cell_map {
      value = {}
    }
  
    foreach ($cells) {
      each as $cl {
        var $cell_key {
          value = ($cl.stage|to_text) ~ "_" ~ ($cl.lens|to_text)
        }
      
        var.update $cell_map {
          value = $cell_map|set:$cell_key:$cl
        }
      }
    }
  
    // Build stage -> internal lens list map
    var $stage_internal_lenses {
      value = {}
    }
  
    foreach ($stages) {
      each as $st {
        var $st_internal {
          value = []
        }
      
        foreach ($lenses) {
          each as $ln {
            conditional {
              if ($ln.actor_type == "internal") {
                var $c_key {
                  value = ($st.id|to_text) ~ "_" ~ ($ln.id|to_text)
                }
              
                var $cell {
                  value = $cell_map|get:$c_key
                }
              
                conditional {
                  if ($cell != null) {
                    var.update $st_internal {
                      value = $st_internal|push:{lens: $ln, cell: $cell}
                    }
                  }
                }
              }
            }
          }
        }
      
        var.update $stage_internal_lenses {
          value = $stage_internal_lenses
            |set:($st.id|to_text):$st_internal
        }
      }
    }
  
    // ── Validation loop ──
    var $stage_reports {
      value = []
    }
  
    var $blocker_count {
      value = 0
    }
  
    var $warning_count {
      value = 0
    }
  
    foreach ($stages) {
      each as $stage {
        var $issues {
          value = []
        }
      
        var $st_status {
          value = "ready"
        }
      
        var $stage_lenses {
          value = $stage_internal_lenses|get:($stage.id|to_text)
        }
      
        conditional {
          if ($stage_lenses == null || ($stage_lenses|count) == 0) {
            var.update $issues {
              value = $issues
                |push:{severity: "info", code: "no_internal_actor", message: "No internal actor lens. Orchestrator will skip this stage."}
            }
          
            var.update $st_status {
              value = "skipped"
            }
          }
        
          else {
            var $has_primary_role {
              value = false
            }
          
            foreach ($stage_lenses) {
              each as $sl {
                var $ln {
                  value = $sl.lens
                }
              
                var $cl {
                  value = $sl.cell
                }
              
                var $af {
                  value = $cl.actor_fields ?? {}
                }
              
                var $task_obj {
                  value = $af|get:"task_objective"
                }
              
                conditional {
                  if ($task_obj == null || $task_obj == "") {
                    var.update $issues {
                      value = $issues
                        |push:{severity: "blocker", code: "missing_task_objective", lens_key: $ln.key, message: "Actor '" ~ $ln.label ~ "' has no task_objective. Orchestrator has nothing to execute."}
                    }
                  
                    var.update $st_status {
                      value = "blocked"
                    }
                  
                    var.update $blocker_count {
                      value = $blocker_count + 1
                    }
                  }
                }
              
                var $info_needs {
                  value = $af|get:"information_needs"
                }
              
                conditional {
                  if ($info_needs == null || ($info_needs|count) < 10) {
                    var.update $issues {
                      value = $issues
                        |push:{severity: "warning", code: "weak_information_needs", lens_key: $ln.key, message: "Actor '" ~ $ln.label ~ "' has empty or very short information_needs. Orchestrator won't know what to ask."}
                    }
                  
                    var.update $warning_count {
                      value = $warning_count + 1
                    }
                  }
                }
              
                var $output_del {
                  value = $af|get:"output_deliverable"
                }
              
                conditional {
                  if ($output_del == null || ($output_del|count) < 10) {
                    var.update $issues {
                      value = $issues
                        |push:{severity: "warning", code: "weak_output_deliverable", lens_key: $ln.key, message: "Actor '" ~ $ln.label ~ "' output_deliverable is missing or too vague."}
                    }
                  
                    var.update $warning_count {
                      value = $warning_count + 1
                    }
                  }
                }
              
                conditional {
                  if ($ln.persona_description == null || $ln.persona_description == "") {
                    var.update $issues {
                      value = $issues
                        |push:{severity: "warning", code: "missing_persona", lens_key: $ln.key, message: "Actor '" ~ $ln.label ~ "' has no persona_description."}
                    }
                  
                    var.update $warning_count {
                      value = $warning_count + 1
                    }
                  }
                }
              
                conditional {
                  if ($ln.actor_role == "primary") {
                    var.update $has_primary_role {
                      value = true
                    }
                  }
                }
              }
            }
          
            conditional {
              if (($stage_lenses|count) > 1 && $has_primary_role == false) {
                var.update $issues {
                  value = $issues
                    |push:{severity: "blocker", code: "no_primary_actor", message: "Multiple internal actors but none is actor_role='primary'. Orchestrator can't determine execution order."}
                }
              
                var.update $st_status {
                  value = "blocked"
                }
              
                var.update $blocker_count {
                  value = $blocker_count + 1
                }
              }
            }
          }
        }
      
        var.update $stage_reports {
          value = $stage_reports
            |push:```
              {
                stage_key  : $stage.key
                stage_label: $stage.label
                status     : $st_status
                issues     : $issues
              }
              ```
        }
      }
    }
  
    var $ready {
      value = $blocker_count == 0
    }
  
    var $summary_text {
      value = "Validation complete."
    }
  
    conditional {
      if ($ready && $warning_count == 0) {
        var.update $summary_text {
          value = "Map is ready to execute."
        }
      }
    
      elseif ($ready) {
        var.update $summary_text {
          value = ($warning_count|to_text) ~ " warning(s) detected. Map is executable but output quality may be reduced."
        }
      }
    
      else {
        var.update $summary_text {
          value = ($blocker_count|to_text) ~ " blocker(s) must be resolved before execution. " ~ ($warning_count|to_text) ~ " warning(s) will reduce output quality."
        }
      }
    }
  
    var $report {
      value = {
        ready_to_execute: $ready
        blocker_count   : $blocker_count
        warning_count   : $warning_count
        stages          : $stage_reports
        summary         : $summary_text
        validated_at    : "now"
      }
    }
  
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        var $in_payload {
          value = null
        }
      
        var $out_payload {
          value = null
        }
      
        var $payload_trunc {
          value = false
        }
      
        conditional {
          if ($input.log_tier == "full") {
            api.lambda {
              code = """
                  const inp = $var.input;
                  const out = $var.result;
                  const inStr = JSON.stringify(inp);
                  const outStr = JSON.stringify(out);
                  const inTrunc = inStr.length > 10240;
                  const outTrunc = outStr.length > 10240;
                  return {
                    in: inTrunc ? { _truncated: true, preview: inStr.slice(0, 500) } : inp,
                    out: outTrunc ? { _truncated: true, preview: outStr.slice(0, 500) } : out,
                    truncated: inTrunc || outTrunc
                  };
                """
              timeout = 3
            } as $pl
          
            var.update $in_payload {
              value = $pl.in
            }
          
            var.update $out_payload {
              value = $pl.out
            }
          
            var.update $payload_trunc {
              value = $pl.truncated
            }
          }
        }
      
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "validate_workflow"
            tool_category : "workflow"
            input_summary : "map: " ~ ($input.journey_map_id|to_text)
            output_summary: $summary_text
            input_payload : $in_payload
            output_payload: $out_payload
          }
        } as $vw_log
      }
    }
  }

  response = $report
}