// Auth Gate — MCP Server Trigger for journey_map
// Fires on every client connection.
// Rejects connections without a valid Xano auth token.
// Use a long-lived API token (generated via POST /automation_api_token/generate)
// in the URL: https://xdjc-i7zz-jhm2.n7e.xano.io/x2/mcp/ju0Zh1JM/{token}/sse
mcp_server_trigger "Auth Gate" {
  mcp_server = "journey_map"

  input {
    object toolset {
      schema {
        int id
        text name
        text instructions
      }
    }
  
    object[] tools {
      schema {
        int id
        text name
        text instructions
      }
    }
  }

  stack {
    var $toolset {
      value = $input.toolset
    }
  
    var $tools {
      value = $input.tools
    }
  
    // Reject unauthenticated connections — requires a valid Xano auth token in the URL
    precondition ($auth.id != null) {
      error_type = "accessdenied"
      error = "Unauthorized: a valid auth token is required to connect to this MCP server"
    }
  }

  response = {toolset: $var.toolset, tools: $tools}
  actions = {connection: true}
  guid = "9qtF87h__16U3AplEbkQXnDSn7Y"
}