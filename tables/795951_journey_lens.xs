// Represents different perspectives or 'lenses' for viewing a journey map.
table journey_lens {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey lens.
    date updated_at?
  
    // Reference to the journey map this lens belongs to.
    int journey_map? {
      table = "journey_map"
    }
  
    // Unique identifier key for the lens within its journey map.
    text key? filters=trim
  
    // Display label for the journey lens.
    text label? filters=trim
  
    // The order in which the lens should be displayed.
    int display_order?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "gin", field: [{name: "xdo", op: "jsonb_path_op"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "updated_at", op: "desc"}
      ]
    }
    {
      type : "btree|unique"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "key", op: "asc"}
        {name: "display_order", op: "asc"}
      ]
    }
  ]
}