// IL-00-01: MCP tool — create a Journey Architecture (workspace).
// Maps to POST /journey_architecture
tool create_workspace {
  instructions = "Create a new journey architecture workspace. Pass title (required), description (optional), and account_id (optional). Returns the created architecture record with its id."

  input {
    text title filters=trim
    text description? filters=trim
    int account_id?
  }

  stack {
    precondition ($input.title != null && $input.title != "") {
      error_type = "inputerror"
      error = "title is required"
    }
  
    db.add journey_architecture {
      enforce_hidden_fields = false
      data = {
        created_at : "now"
        updated_at : "now"
        title      : $input.title
        description: $input.description
        status     : "draft"
        account_id : $input.account_id
      }
    } as $architecture
  }

  response = $architecture
  guid = "IL00CreateWorkspaceTool000001"
}