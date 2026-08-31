// Registers an external automation tool instance (n8n, Make.com) against a journey architecture.
// Emgram pushes compiled snapshots to registered connections on every map publish.
// One connection per tool instance. Multiple connections per architecture are supported.
// v1: initial schema
table automation_connection {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update.
    timestamp updated_at?
  
    // The architecture this connection receives snapshots for.
    int journey_architecture? {
      table = "journey_architecture"
    }
  
    // Which automation platform this connection points to.
    enum provider? {
      values = ["n8n", "make", "zapier", "custom"]
    }
  
    // User-assigned label for this connection.
    // Example: "Marcus's n8n", "Production Make scenario"
    text label? filters=trim
  
    // The webhook URL Emgram POSTs to when a snapshot is published.
    // Receives: { event: "snapshot_updated", map_id, version, snapshot }
    text webhook_url? filters=trim
  
    // Connection health:
    // active  = last push succeeded
    // paused  = user-disabled; pushes skipped
    // error   = last push failed; stores last_error_message
    enum status? {
      values = ["active", "paused", "error"]
    }
  
    // Short message from the last failed push attempt.
    // Cleared on next successful push.
    text last_error_message? filters=trim
  
    // Timestamp of the most recent successful push.
    timestamp last_pushed_at?
  
    // Inherited from the parent architecture's owner — never set by client.
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
        {name: "journey_architecture", op: "asc"}
        {name: "status", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "owner_user", op: "asc"}]}
  ]
}