// RES-3-03 — Configurable retention windows for high-volume tables.
// One row per table that has a scheduled prune task. Editing a row
// changes retention behavior without redeploying the prune task itself.
// Rows are seeded manually after first push (see EPIC-RES-3 for defaults).
table retention_policy {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Target table name (e.g. "event_log", "agent_message").
    // Must match the table the paired prune task targets.
    text table_name? filters=trim
  
    // How many days of data to keep. Rows with created_at older than
    // (now - retention_days) are eligible for pruning.
    int retention_days?
  
    // Safety cap: maximum rows deleted in a single prune run.
    // Prevents a runaway scan from hanging the workspace.
    int max_rows_per_run?
  
    // Disable a policy without deleting the row.
    bool enabled?
  
    // Optional human-readable note about why this window was chosen.
    text notes? filters=trim
  
    // Last successful prune timestamp (written by the prune task).
    timestamp last_pruned_at?
  
    // Rows deleted on the last run (written by the prune task).
    int last_rows_deleted?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [{name: "table_name", op: "asc"}]
    }
    {type: "btree", field: [{name: "enabled", op: "asc"}]}
  ]
}