// IL-04-01: Execution health aggregation for a journey map.
// Aggregates all workflow_execution records for the map and computes per-stage health metrics.
// Returns: per-stage failure_rate, avg_completion_time, common_failure_reasons[].
// Source: workflow_execution.stage_outputs across all runs for this map.
query "journey_map/{journey_map_id}/execution_health" verb=GET {
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
  
    // Load stages for label/key mapping
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    // Load all executions for this map (completed + failed)
    db.query workflow_execution {
      where = $db.workflow_execution.journey_map == $input.journey_map_id
      sort = {created_at: "desc"}
      return = {type: "list"}
    } as $all_executions
  
    var $total_runs {
      value = $all_executions|count
    }
  
    var $completed_runs {
      value = 0
    }
  
    var $failed_runs {
      value = 0
    }
  
    // Count completed/failed runs
    foreach ($all_executions) {
      each as $ex {
        conditional {
          if ($ex.status == "completed") {
            var.update $completed_runs {
              value = $completed_runs + 1
            }
          }
        
          elseif ($ex.status == "failed") {
            var.update $failed_runs {
              value = $failed_runs + 1
            }
          }
        }
      }
    }
  
    // Build per-stage health using api.lambda for JSON aggregation
    api.lambda {
      code = """
          const execs = $var.all_executions || [];
          const stages = $var.stages || [];
          const stageHealth = {};
        
          // Init per-stage buckets
          stages.forEach(s => {
            stageHealth[s.key] = {
              stage_key: s.key,
              stage_label: s.label,
              total_attempts: 0,
              completed_attempts: 0,
              failed_attempts: 0,
              failure_rate: 0,
              failure_reasons: []
            };
          });
        
          // Aggregate from stage_outputs across all executions
          execs.forEach(ex => {
            const outputs = ex.stage_outputs || {};
            stages.forEach(s => {
              if (outputs[s.key] !== undefined) {
                stageHealth[s.key].total_attempts++;
                const out = outputs[s.key];
                if (out && out.output) {
                  stageHealth[s.key].completed_attempts++;
                } else {
                  stageHealth[s.key].failed_attempts++;
                }
              }
            });
            // Collect failure_reason if run failed
            if (ex.status === 'failed' && ex.failure_reason && ex.current_stage_key) {
              const sk = ex.current_stage_key;
              if (stageHealth[sk]) {
                stageHealth[sk].failure_reasons.push(ex.failure_reason);
              }
            }
          });
        
          // Compute rates and deduplicate failure reasons
          return Object.values(stageHealth).map(sh => {
            const total = sh.total_attempts;
            const failed = sh.failed_attempts;
            sh.failure_rate = total > 0 ? Math.round((failed / total) * 100) / 100 : 0;
            sh.common_failure_reasons = [...new Set(sh.failure_reasons)].slice(0, 5);
            delete sh.failure_reasons;
            return sh;
          });
        """
      timeout = 5
    } as $stage_health
  }

  response = {
    journey_map_id: $input.journey_map_id
    total_runs    : $total_runs
    completed_runs: $completed_runs
    failed_runs   : $failed_runs
    stage_health  : $stage_health
  }
}