// Stores machine-executable automation config per journey stage.
// Sits alongside the human-readable actor_fields text — machines read this, humans read actor_fields.
// One record per stage per automation intent. Status moves draft → confirmed → disabled.
// v1: initial schema
table stage_automation_config {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update.
    timestamp updated_at?
  
    // The journey map this config belongs to.
    int journey_map? {
      table = "journey_map"
    }
  
    // The specific stage this config drives.
    int journey_stage? {
      table = "journey_stage"
    }
  
    // What fires this stage's automation.
    // webhook = inbound HTTP call from external system
    // inbound_status = a status field change in an integrated tool (e.g. Jobber job status)
    // schedule = time-based trigger (future)
    // manual = user-initiated
    enum trigger_type? {
      values = ["webhook", "inbound_status", "schedule", "manual"]
    }
  
    // Provider-specific trigger configuration.
    // Shape: { provider, event, filter, field_map }
    // Example: { "provider": "jobber", "event": "job.status_changed", "filter": { "status": "dispatched" } }
    json trigger_config?
  
    // What this stage's automation does when triggered.
    enum action_type? {
      values = ["sms", "email", "http_post", "jobber_update", "slack", "none"]
    }
  
    // Provider-specific action configuration.
    // Shape: { provider, template_id, recipient_field, field_map }
    // Example: { "provider": "twilio", "template_id": "tmpl_dispatch", "recipient_field": "client.mobile" }
    json action_config?
  
    // Structured condition that fires the linked exception/sub/anti map.
    // Shape: { field, op, value } — op values: eq, neq, gt, lt, contains, is_null
    // Null when this stage has no exception branch.
    json exception_condition?
  
    // The map to switch to when exception_condition is met.
    // Null for happy-path-only stages.
    int linked_map_id? {
      table = "journey_map"
    }
  
    // The type of link to the linked map.
    // Matches journey_link.link_type values.
    enum linked_map_link_type? {
      values = ["exception", "anti_journey", "sub_journey"]
    }
  
    // Config lifecycle:
    // draft    = AI proposed, awaiting user confirmation
    // confirmed = user reviewed and approved
    // disabled = excluded from snapshot compilation
    enum status? {
      values = ["draft", "confirmed", "disabled"]
    }
  
    // Inherited from journey_map.owner_user — never set by client.
    int owner_user? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "status", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "journey_stage", op: "asc"}]}
    {type: "btree", field: [{name: "owner_user", op: "asc"}]}
  ]
}