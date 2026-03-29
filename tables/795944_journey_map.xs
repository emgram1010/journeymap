// Stores high-level information about each customer journey map.
table journey_map {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey map.
    date updated_at?
  
    // The title of the journey map.
    text title? filters=trim
  
    // The current status of the journey map.
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    // Reference to the user who owns this journey map (optional).
    int owner_user? {
      table = "user"
    }
  
    // Reference to the account this journey map belongs to (optional).
    int account_id? {
      table = "account"
    }
  
    // Timestamp of the last interaction on the journey map (optional).
    date last_interaction_at?
  
    // JSON object for journey map settings (optional).
    json settings?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "gin", field: [{name: "xdo", op: "jsonb_path_op"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "owner_user", op: "asc"}
        {name: "account_id", op: "asc"}
        {name: "updated_at", op: "desc"}
        {name: "last_interaction_at", op: "desc"}
      ]
    }
  ]
}