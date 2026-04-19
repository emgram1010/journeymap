// Stores directed connections between Journey Maps within a Journey Architecture.
// A link goes from a specific source cell (stage × lens intersection) in one map
// to a target map, with a typed relationship.
// Uniqueness: (source_cell, target_map) must be unique — one cell can only link
// to a given target map once. Edit the link_type/label to change the relationship.
// v1: initial schema
table journey_link {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update.
    date updated_at?
  
    // Parent architecture — all linked maps must belong to this architecture.
    int journey_architecture? {
      table = "journey_architecture"
    }
  
    // The map where the breakpoint originates.
    int source_map? {
      table = "journey_map"
    }
  
    // The specific cell (stage × lens intersection) that is the link anchor.
    // Required — cell-level precision only.
    int source_cell? {
      table = "journey_cell"
    }
  
    // The map being linked to.
    int target_map? {
      table = "journey_map"
    }
  
    // The type of relationship this link represents.
    enum link_type? {
      values = ["exception", "anti_journey", "sub_journey"]
    }
  
    // Optional short label shown on the graph edge.
    text label? filters=trim
  
    // Inherited from the parent architecture — never set by client.
    int owner_user? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "gin", field: [{name: "xdo", op: "jsonb_path_op"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "journey_architecture", op: "asc"}
        {name: "source_map", op: "asc"}
      ]
    }
    {
      type : "btree"
      field: [
        {name: "journey_architecture", op: "asc"}
        {name: "target_map", op: "asc"}
      ]
    }
    {
      type : "btree"
      field: [
        {name: "source_cell", op: "asc"}
        {name: "target_map", op: "asc"}
      ]
    }
  ]
}