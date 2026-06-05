// IL-00-06: MCP tool — list journey maps for the authenticated scope.
// Optional filters: architecture_id, intent, status.
tool list_maps {
  instructions = "List journey maps. Optionally filter by architecture_id, intent (sop|automation|hybrid), status (draft|active|archived), or map_level (architecture|actor-journey|atomic). Returns an array of { id, title, intent, status, map_level, last_interaction_at }."

  input {
    int architecture_id?
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }
  
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    // LA-4: filter by Intelligence Layer map level.
    // Use map_level='atomic' to find L3 maps valid for leakage analysis.
    enum map_level? {
      values = ["architecture", "actor-journey", "atomic"]
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
          if ($input.map_level != null && $m.map_level != $input.map_level) {
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
                map_level          : $m.map_level
                last_interaction_at: $m.last_interaction_at
              }
            }
          }
        }
      }
    }
  }

  response = {count: $results|count, results: $results}
}