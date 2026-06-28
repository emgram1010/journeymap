// RES-3-03 — Scheduled prune for agent_turn_log.
// Reads retention_policy(table_name="agent_turn_log") for the window and safety cap.
// Daily at 03:00 UTC: delete agent_turn_log rows older than the configured retention window (see retention_policy table). Capped per run by max_rows_per_run.
task prune_agent_turn_log {
  stack {
    db.query retention_policy {
      where = $db.retention_policy.table_name == "agent_turn_log" && $db.retention_policy.enabled == true
      return = {type: "single"}
    } as $policy
  
    conditional {
      if ($policy == null) {
        debug.log {
          value = "prune_agent_turn_log: no enabled retention_policy row; skipping"
        }
      }
    
      else {
        var $cutoff {
          value = now
            |transform_timestamp:$policy.retention_days ~ " days ago":"UTC"
        }
      
        var $cap {
          value = $policy.max_rows_per_run ?? 10000
        }
      
        db.query agent_turn_log {
          where = $db.agent_turn_log.created_at < $cutoff
          sort = {created_at: "asc"}
          return = {type: "list", paging: {page: 1, per_page: $cap}}
        } as $expired
      
        var $deleted {
          value = 0
        }
      
        foreach ($expired) {
          each as $row {
            db.del agent_turn_log {
              field_name = "id"
              field_value = $row.id
            }
          
            var.update $deleted {
              value = $deleted + 1
            }
          }
        }
      
        db.patch retention_policy {
          field_name = "id"
          field_value = $policy.id
          data = {last_pruned_at: "now", last_rows_deleted: $deleted}
        } as $_p
      
        debug.log {
          value = "prune_agent_turn_log: deleted " ~ ($deleted|to_text) ~ " rows older than " ~ ($policy.retention_days|to_text) ~ " days"
        }
      }
    }
  }

  schedule = [{starts_on: 2026-06-21 03:00:00+0000, freq: 86400}]
}