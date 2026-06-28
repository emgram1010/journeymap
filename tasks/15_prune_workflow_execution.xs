// RES-3-03 — Scheduled prune for workflow_execution.
// Only TERMINAL statuses (completed/failed/cancelled) are eligible — active
// runs (pending/running/paused) are never pruned regardless of age.
// Daily at 03:00 UTC: delete workflow_execution rows in terminal status older than the configured retention window (see retention_policy table). Active runs are never pruned. Capped per run by max_rows_per_run.
task prune_workflow_execution {
  stack {
    db.query retention_policy {
      where = $db.retention_policy.table_name == "workflow_execution" && $db.retention_policy.enabled == true
      return = {type: "single"}
    } as $policy
  
    conditional {
      if ($policy == null) {
        debug.log {
          value = "prune_workflow_execution: no enabled retention_policy row; skipping"
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
      
        db.query workflow_execution {
          where = $db.workflow_execution.created_at < $cutoff && ($db.workflow_execution.status == "completed" || $db.workflow_execution.status == "failed" || $db.workflow_execution.status == "cancelled")
          sort = {created_at: "asc"}
          return = {type: "list", paging: {page: 1, per_page: $cap}}
        } as $expired
      
        var $deleted {
          value = 0
        }
      
        foreach ($expired) {
          each as $row {
            db.del workflow_execution {
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
          value = "prune_workflow_execution: deleted " ~ ($deleted|to_text) ~ " terminal-status rows older than " ~ ($policy.retention_days|to_text) ~ " days"
        }
      }
    }
  }

  schedule = [{starts_on: 2026-06-21 03:00:00+0000, freq: 86400}]
}