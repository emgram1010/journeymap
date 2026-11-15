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

    // COP-3 story 02: a conversation pinned to one business works inside it; a new business is
    // made by a person (or from a conversation that is not pinned).
    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin == 0) {
      error_type = "accessdenied"
      error = "This conversation works inside one business, so it can't create a new one. Ask a person to create it. (E-COP-037)"
    }

    precondition ($input.title != null && $input.title != "") {
      error_type = "inputerror"
      error = "title is required"
    }
  
    // COP-1: a workspace belongs to whoever made it. When the caller is known, the account
    // and owner come from the caller and the account_id input is ignored.
    var $stamp_account {
      value = $input.account_id
    }

    var $stamp_owner {
      value = 0
    }

    conditional {
      if ($cop1_gate.user_id != 0) {
        var.update $stamp_account {
          value = $cop1_gate.account_id
        }

        var.update $stamp_owner {
          value = $cop1_gate.user_id
        }
      }
    }

    db.add journey_architecture {
      enforce_hidden_fields = false
      data = {
        created_at : "now"
        updated_at : "now"
        title      : $input.title
        description: $input.description
        status     : "draft"
        account_id : $stamp_account
        owner_user : $stamp_owner
      }
    } as $architecture
  }

  response = $architecture
  guid = "IL00CreateWorkspaceTool000001"
}