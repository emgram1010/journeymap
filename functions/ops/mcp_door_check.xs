// SEC-3 story 06 - is the AI tool door still shut? Calls the public tool address the way a stranger would (no token): tools/list must list nothing and tools/call get_map must be refused. Writes ONE event: success (shut), E-SEC-021 failure (OPEN - a tool was listed or a map came back) or E-SEC-022 failure (could not tell - the address did not answer as expected). Run nightly by task ops_mcp_door_check; can also be run by hand. Never sends a token, reads nothing private (a refused call returns no map).
function "ops/mcp_door_check" {
  input {
  }

  stack {
    var $url {
      value = "https://xdjc-i7zz-jhm2.n7e.xano.io/x2/mcp/ju0Zh1JM/mcp/stream"
    }

    var $list_raw {
      value = ""
    }

    var $call_raw {
      value = ""
    }

    var $list_status {
      value = 0
    }

    var $call_status {
      value = 0
    }

    try_catch {
      try {
        api.request {
          url = $url
          method = "POST"
          params = {jsonrpc: "2.0", id: 1, method: "tools/list", params: {}}
          headers = []|push:"Content-Type: application/json"|push:"Accept: application/json, text/event-stream"
        } as $list

        api.request {
          url = $url
          method = "POST"
          params = {jsonrpc: "2.0", id: 2, method: "tools/call", params: {name: "get_map", arguments: {journey_map_id: 226}}}
          headers = []|push:"Content-Type: application/json"|push:"Accept: application/json, text/event-stream"
        } as $call

        var.update $list_status {
          value = $list.response.status ?? 0
        }

        var.update $call_status {
          value = $call.response.status ?? 0
        }

        var.update $list_raw {
          value = ($list.response.result ?? "")|to_text
        }

        var.update $call_raw {
          value = ($call.response.result ?? "")|to_text
        }
      }

      catch {
        var.update $list_status {
          value = 0
        }
      }
    }

    // A listed tool always carries an inputSchema; a refused call always carries "error".
    var $tool_listed {
      value = $list_raw|contains:"inputSchema"
    }

    var $list_empty {
      value = $list_raw|contains:"\"tools\":[]"
    }

    var $call_refused {
      value = $call_raw|contains:"\"error\""
    }

    var $state {
      value = "unclear"
    }

    conditional {
      if ($tool_listed == true || ($call_status == 200 && $call_raw != "" && $call_refused == false)) {
        var.update $state {
          value = "open"
        }
      }

      elseif ($list_status == 200 && $list_empty == true && $call_refused == true) {
        var.update $state {
          value = "shut"
        }
      }
    }

    conditional {
      if ($state == "shut") {
        function.run "ops/log_event" {
          input = {feature: "SEC-3", step: "mcp_door_check", outcome: "success", severity: "info", user_id: 0, account_id: 0, entity_type: "mcp_server", entity_id: 8, correlation_id: "", error_code: "", message: "Nightly check: the AI tool address lists no tools and refuses calls without a sign-in.", metadata: {list_status: $list_status, call_status: $call_status}}
        } as $_ok
      }

      elseif ($state == "open") {
        function.run "ops/log_event" {
          input = {feature: "SEC-3", step: "mcp_door_check", outcome: "failure", severity: "error", user_id: 0, account_id: 0, entity_type: "mcp_server", entity_id: 8, correlation_id: "", error_code: "E-SEC-021", message: "Nightly check: the AI tool address answered WITHOUT a sign-in. The Auth Gate may be switched off.", metadata: {list_status: $list_status, call_status: $call_status, tool_listed: $tool_listed}}
        } as $_open
      }

      else {
        function.run "ops/log_event" {
          input = {feature: "SEC-3", step: "mcp_door_check", outcome: "failure", severity: "warn", user_id: 0, account_id: 0, entity_type: "mcp_server", entity_id: 8, correlation_id: "", error_code: "E-SEC-022", message: "Nightly check: the AI tool address did not answer as expected, so it could not be confirmed shut.", metadata: {list_status: $list_status, call_status: $call_status}}
        } as $_unclear
      }
    }
  }

  response = {state: $state, list_status: $list_status, call_status: $call_status}
}
