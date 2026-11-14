// IL-00-01: MCP tool — create a Journey Architecture (workspace).
// Maps to POST /journey_architecture
tool create_workspace {
  instructions = "Create a new journey architecture workspace. Pass title (required), description (optional), and account_id (optional). Returns the created architecture record with its id."

  input {
    text title filters=trim
    text description? filters=trim
    int account_id?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "create_workspace", kind: "write"}
    } as $cop1_gate

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