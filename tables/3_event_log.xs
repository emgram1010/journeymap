// Stores logs of user activities and events within the application.
// ── RES-3 Lifecycle classification ───────────────────────────────────────
// Growth class    : HIGH (append-only; every user action + RES-8 telemetry).
// Dominant window : last 7d for ops dashboards; last 30d for audit.
// Old rows read?  : Rarely — compliance/forensics only.
// Retention       : 90 days (configurable via retention_policy table).
// Prune cadence   : daily 03:00 UTC (task: prune_event_log).
table event_log {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Reference to the user who performed the action.
    int user_id? {
      table = "user"
    }
  
    // Reference to the company associated with the user event.
    int account_id? {
      table = "account"
    }
  
    // A description of the action performed by the user (e.g., 'login', 'created_invoice', 'updated_profile').
    text action? filters=trim
  
    // Additional data related to the event, such as resource IDs, old/new values, or other contextual information.
    json metadata?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "account_id", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
  ]

  tags = ["xano:quick-start"]
}