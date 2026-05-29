// IL-00-06: MCP tool — list journey maps for the authenticated scope.
// Optional filters: architecture_id, intent, status.
tool list_maps {
  instructions = "List journey maps. Optionally filter by architecture_id, intent (sop|automation|hybrid), or status (draft|active|archived). Returns an array of { id, title, intent, status, last_interaction_at }."

  input {
    int architecture_id?
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }
  
    enum status? {
      values = ["draft", "active", "archived"]
    }
  }

  stack {
    // Load all maps — filter in-memory for flexibility
    db.query journey_map {
      sort = {last_interaction_at: "desc"}
      return = {type: "list"}
    } as $all_maps
  
    var $results {
      value = []
    }
  
    foreach ($all_maps) {
      each as $m {
        var $pass {
          value = true
        }
      
        conditional {
          if ($input.architecture_id != null && $m.journey_architecture != $input.architecture_id) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($input.intent != null && $m.intent != $input.intent) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($input.status != null && $m.status != $input.status) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($pass) {
            array.push $results {
              value = {
                id                 : $m.id
                title              : $m.title
                intent             : $m.intent
                status             : $m.status
                last_interaction_at: $m.last_interaction_at
              }
            }
          }
        }
      }
    }
  }

  response = {count: $results|count, results: $results}
  guid = "IL00ListMapsTool00000000001"
}