// US-WS-01: Web search via Tavily API. Gives agents live internet access.
tool web_search {
  instructions = """
      Use this tool to search the live internet for current information.
    
      Call this tool when you need:
      - Company background, news, or recent events (e.g. "Americold recent news")
      - Prospect or person information (e.g. "Ram Prasath Mani Americold")
      - Industry context, market trends, or competitor data
      - Any fact that may have changed recently or that the user hasn't provided
    
      Use search_depth = "basic" for quick fact checks (default).
      Use search_depth = "advanced" for thorough company or prospect research.
    
      Input:
      - query: What to search for (be specific — include names, company, context)
      - search_depth: "basic" (fast, 5 results) or "advanced" (thorough, up to 10 results)
    
      Response shape:
      {
        query: string,
        count: int,
        results: [ { title, url, content, score } ]
      }
    
      Use the returned content to enrich your responses and cell writes.
      Always cite the source URL when using search results in your reply.
    """

  input {
    text query filters=trim
    text search_depth?
    int conversation_id?
    text turn_id?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "web_search", kind: "read"}
    } as $cop1_gate

    precondition ($input.query != null && $input.query != "") {
      error_type = "inputerror"
      error = "Search query is required"
    }
  
    var $depth {
      value = "basic"
    }
  
    conditional {
      if ($input.search_depth == "advanced") {
        var.update $depth {
          value = "advanced"
        }
      }
    }
  
    var $max_results {
      value = 5
    }
  
    conditional {
      if ($depth == "advanced") {
        var.update $max_results {
          value = 10
        }
      }
    }
  
    var $api_key {
      value = $env.TAVILY_API_KEY
    }
  
    precondition ($api_key != null && $api_key != "") {
      error_type = "inputerror"
      error = "TAVILY_API_KEY environment variable is not set"
    }
  
    var $auth_header {
      value = "Authorization: Bearer " ~ $api_key
    }
  
    api.request {
      url = "https://api.tavily.com/search"
      method = "POST"
      params = {}
        |set:"query":$input.query
        |set:"search_depth":$depth
        |set:"max_results":$max_results
      headers = []
        |push:$auth_header
        |push:"Content-Type: application/json"
    } as $tavily_response
  
    // COP-4 (2026-11-15): api.request wraps the reply as {response: {result: <body>, status}}. This
    // read $tavily_response.results (always missing), so every search returned 0 results — found
    // when the copilot's research said "web search did not return results".
    var $tavily_status {
      value = $tavily_response|get:"response"|get:"status":0
    }

    var $raw_results {
      value = ($tavily_response|get:"response"|get:"result"|get:"results":[]) ?? []
    }

    // Keep each result short (title, link, ~600 characters): agents pass these through their whole
    // conversation, and full page extracts made research runs too heavy (found live: a 502).
    var $results {
      value = []
    }

    foreach ($raw_results) {
      each as $r {
        array.push $results {
          value = {title: ($r.title ?? ""), url: ($r.url ?? ""), content: (($r.content ?? "")|substr:0:600)}
        }
      }
    }
  
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id
            turn_id       : $input.turn_id
            tool_name     : "web_search"
            tool_category : "external"
            input_summary : "Query: " ~ $input.query
            output_summary: ($results|count|to_text) ~ " results"
          }
        }
      }
    }
  }

  response = {
    query  : $input.query
    count  : $results|count
    status : $tavily_status
    results: $results
  }

  guid = "wS22TavilyWebSearch001emgram"
}