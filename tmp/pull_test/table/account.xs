// Stores information about accounts that users belong to
table account {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // The name of the company.
    text name? filters=trim
  
    // A brief description of the company.
    text description? filters=trim
  
    text location? filters=trim
  
    // Freeform context fed to the AI agent on every conversation for this account.
    // Should describe industry, customer types, internal team names, and terminology.
    text ai_context? filters=trim
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
  ]

  tags = ["xano:quick-start"]
  guid = "937pCNnXtKtr85V4TklxowLOIKE"
}