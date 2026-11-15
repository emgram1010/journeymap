// IL-00-08: MCP tool — search published journey maps by natural language query.
// Searches ai_summary and tags fields. Returns ranked results.
// Maps to the GET /journey_map/search endpoint built in Epic IL-1.
tool search_maps {
  instructions = "Search published journey maps by natural language query. Pass query (text), and optionally intent (sop|automation|hybrid) or tags (JSON array of strings). Returns a ranked list of { map_id, title, ai_summary, intent, tags } matching the query."

  input {
    text query? filters=trim
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }
  
    json tags?
  
    // LA-4: filter by Intelligence Layer map level.
    // Use map_level='atomic' to find L3 maps valid for leakage analysis.
    enum map_level? {
      values = ["architecture", "actor-journey", "atomic"]
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "search_maps", kind: "read"}
    } as $cop1_gate

    // COP-1: a known caller sees only their own account's maps (journey/visible_map_ids, the
    // same rule the screens use). An unknown caller is only possible while the gate is in
    // report mode, and then the list is unchanged.
    var $caller_account {
      value = $cop1_gate.account_id
    }

    // COP-1 review (2026-11-14): never "see all". A caller with no account sees nothing
    // (journey/visible_map_ids), even if they hold the Intelligent Layer.
    var $see_all {
      value = false
    }

    function.run "journey/visible_map_ids" {
      input = {caller_account_id: $caller_account}
    } as $visible

    var $visible_ids {
      value = $visible.map_ids
    }

    // Load the caller's active maps
    db.query journey_map {
      where = $db.journey_map.status == "active" && (($see_all == true) || ($db.journey_map.id in $visible_ids))
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $active_maps
  
    var $query_lower {
      value = ($input.query ?? "")|lower
    }
  
    var $results {
      value = []
    }
  
    foreach ($active_maps) {
      each as $m {
        // Intent filter
        var $intent_ok {
          value = true
        }
      
        conditional {
          if ($input.intent != null && $m.intent != $input.intent) {
            var.update $intent_ok {
              value = false
            }
          }
        }
      
        // Map level filter (LA-4)
        conditional {
          if ($input.map_level != null && $m.map_level != $input.map_level) {
            var.update $intent_ok {
              value = false
            }
          }
        }
      
        conditional {
          if ($intent_ok) {
            var $summary_lower {
              value = ($m.ai_summary ?? "")|lower
            }
          
            var $tags_lower {
              value = `($m.tags|json_encode ?? "")|lower`
            }
          
            var $match {
              value = false
            }
          
            conditional {
              if ($input.query == null || $input.query == "") {
                var.update $match {
                  value = true
                }
              }
            
              elseif ($summary_lower|contains:$query_lower) {
                var.update $match {
                  value = true
                }
              }
            
              elseif ($tags_lower|contains:$query_lower) {
                var.update $match {
                  value = true
                }
              }
            }
          
            conditional {
              if ($match) {
                array.push $results {
                  value = {
                    map_id    : $m.id
                    title     : $m.title
                    ai_summary: $m.ai_summary
                    intent    : $m.intent
                    tags      : $m.tags
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    query  : $input.query
    count  : $results|count
    results: $results
  }

  guid = "oj72jI3GgUZtnM_JGNEPPn6Opw8"
}