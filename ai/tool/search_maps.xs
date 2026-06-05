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
  }

  stack {
    // Load all active maps
    db.query journey_map {
      where = $db.journey_map.status == "active"
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $active_maps
  
    var $query_lower {
      value = ($input.query ?? "")|lowercase
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
              value = ($m.ai_summary ?? "")|lowercase
            }
          
            var $tags_lower {
              value = `($m.tags|json_encode ?? "")|lowercase`
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