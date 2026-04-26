// Stores content for each cell within a journey map (intersection of stage and lens).
table journey_cell {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey cell.
    date updated_at?
  
    // Reference to the journey map this cell belongs to.
    int journey_map? {
      table = "journey_map"
    }
  
    // Reference to the journey stage this cell is in.
    int stage? {
      table = "journey_stage"
    }
  
    // Reference to the journey lens this cell is under.
    int lens? {
      table = "journey_lens"
    }
  
    // The textual content of the cell (optional).
    text content? filters=trim
  
    // The current status of the cell's content.
    enum status? {
      values = ["open", "draft", "confirmed"]
    }
  
    // Indicates if the cell is locked for editing.
    bool is_locked?
  
    // Source of the last change to the cell's content.
    enum change_source? {
      values = ["user", "ai"]
    }
  
    // Timestamp of the last content update for the cell (optional).
    date last_updated_at?
  
    // Stores structured actor-specific sub-fields for this cell. The JSON keys vary by actor type (e.g., entry_trigger, emotions, information_needs for a customer actor cell).
    json actor_fields?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "stage", op: "asc"}
        {name: "lens", op: "asc"}
        {name: "updated_at", op: "desc"}
        {name: "last_updated_at", op: "desc"}
      ]
    }
  ]
}