// Versioned compiled JSON representation of the full automation decision graph for a journey map.
// Includes the map's own stage configs + all linked map configs (exception, anti, sub-journey).
// Built by the compile step on every publish. Consumed by external tools (n8n, Make.com).
// One record per journey_map — upserted on each publish, version increments monotonically.
// v1: initial schema
table automation_snapshot {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last compile.
    timestamp compiled_at?
  
    // The journey map this snapshot represents.
    int journey_map? {
      table = "journey_map"
    }
  
    // The architecture this map belongs to (denormalised for fast lookup).
    int journey_architecture? {
      table = "journey_architecture"
    }
  
    // Monotonically incrementing compile version.
    // Starts at 1, increments on every publish that changes config.
    int version?
  
    // The full compiled decision graph.
    // Shape: {
    //   map_id, version, compiled_at,
    //   stages: [ { key, label, trigger, action, exception_condition, links: [ { link_type, condition, target_map_id, target_map_label, target_map_stages } ] } ],
    // }
    // target_map_stages is recursively nested (max 3 levels deep).
    // Stages without links have links: [].
    json graph?
  
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
        {name: "version", op: "desc"}
      ]
    }
    {
      type : "btree"
      field: [{name: "journey_architecture", op: "asc"}]
    }
    {type: "btree", field: [{name: "owner_user", op: "asc"}]}
  ]

  guid = "aNpKw7hYtRmsCeDjUbV4xFoLqGI"
}