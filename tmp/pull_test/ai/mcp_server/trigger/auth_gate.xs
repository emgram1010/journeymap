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
  }

  response = {toolset: $var.toolset, tools: $tools}
  actions = {connection: true}
  guid = "9qtF87h__16U3AplEbkQXnDSn7Y"
}