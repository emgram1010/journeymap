// Defines distinct stages within a journey map.
table journey_stage {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey stage.
    date updated_at?
  
    // Reference to the journey map this stage belongs to.
    int journey_map? {
      table = "journey_map"
    }
  
    // Unique identifier key for the stage within its journey map.
    text key? filters=trim
  
    // Display label for the journey stage.
    text label? filters=trim
  
    // The order in which the stage should be displayed.
    int display_order?

    // Exit condition / definition of done for this stage (one-liner).
    text stage_goal? filters=trim

    // Lens key identifying the actor accountable for this stage's outcome.
    text primary_actor_lens? filters=trim
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
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
  guid = "oyjLsxiEMzYhPbqaduXT2ZxfTcI"
}