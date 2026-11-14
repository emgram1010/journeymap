// Auth Gate — MCP Server Trigger for journey_map. SEC-3, 2026-11-14.
// Fires on every client connection. No valid token = NO TOOLS. A valid token must belong to a
// person who is switched on and holds the Intelligent Layer (usr/mcp_caller). Fails closed:
// anything other than a clear yes returns an empty tool list, so nothing can be listed or run.
// Token: `Authorization: Bearer <token>` header, or `?token=<token>` on the address.
// NEVER comment this check out to "test public access" — that left every account's maps open
// to the internet from 2026-06-18 to 2026-11-14.
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
  
    object[] prompts {
      schema {
        int id
        text name
        text description
      }
    }
  
    object[] resources {
      schema {
        int id
        text name
        text description
        text uri
      }
    }
  
    json? auth
  }

  stack {
    var $tools_out {
      value = []
    }

    var $toolset_out {
      value = $input.toolset|set:"instructions":"Sign in to use these tools. Add a valid Emgram token to the connection. (E-SEC-020)"
    }

    var $authz {
      value = ""
    }

    var $uri {
      value = ""
    }

    var $allowed {
      value = false
    }

    try_catch {
      try {
        var $hdrs {
          value = $env.$http_headers ?? {}
        }

        var.update $authz {
          value = $hdrs|get:"Authorization":""
        }

        var.update $uri {
          value = $env.$request_uri ?? ""
        }

        function.run "usr/mcp_caller" {
          input = {
            authorization: $authz
            uri          : $uri
          }
        } as $who

        var.update $allowed {
          value = $who.allowed == true
        }
      }

      catch {
        var.update $allowed {
          value = false
        }
      }
    }

    conditional {
      if ($allowed == true) {
        var.update $tools_out {
          value = $input.tools
        }

        var.update $toolset_out {
          value = $input.toolset
        }
      }
    }
  }

  response = {toolset: $toolset_out, tools: $tools_out}
  actions = {connection: true}
}