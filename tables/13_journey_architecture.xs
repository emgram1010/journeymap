// Stores Journey Architecture records — named parent containers that group one or more
// Journey Maps under a single organising unit.
// v1: initial schema
table journey_architecture {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey architecture.
    date updated_at?
  
    // The title of the journey architecture.
    text title? filters=trim
  
    // A description of what this architecture covers.
    text description? filters=trim
  
    // The current status of the journey architecture.
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    // Reference to the user who owns this journey architecture.
    int owner_user? {
      table = "user"
    }
  
    // Reference to the account this journey architecture belongs to.
    int account_id? {
      table = "account"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "owner_user", op: "asc"}
        {name: "account_id", op: "asc"}
        {name: "updated_at", op: "desc"}
      ]
    }
  ]
}