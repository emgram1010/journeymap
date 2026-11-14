// SCN-MCP-1: MCP tool — list all journey map scenarios within a Journey Architecture.
// Maps to GET /journey_architecture/{id}/scenarios
tool list_scenarios {
  instructions = "List all journey map scenarios within a Journey Architecture. Pass journey_architecture_id. Returns all maps (draft and active) ordered by updated_at DESC. Returns [] when none exist — not an error. Always call this before clone_scenario to find the correct source_map_id."

  input {
    int journey_architecture_id filters=min:1

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "list_scenarios", kind: "read"}
    } as $cop1_gate

    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch
  
    precondition ($arch != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $input.journey_architecture_id
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $maps
  
    var $results {
      value = []
    }
  
    foreach ($maps) {
      each as $map {
        var $owner_name {
          value = "Unknown"
        }
      
        conditional {
          if ($map.owner_user != null) {
            db.get user {
              field_name = "id"
              field_value = $map.owner_user
            } as $owner
          
            conditional {
              if ($owner != null && $owner.name != null && $owner.name != "") {
                var.update $owner_name {
                  value = $owner.name
                }
              }
            }
          
            conditional {
              if ($owner != null && ($owner.name == null || $owner.name == "") && $owner.email != null) {
                var.update $owner_name {
                  value = $owner.email
                }
              }
            }
          }
        }
      
        array.push $results {
          value = {
            id                : $map.id
            title             : $map.title
            status            : $map.status
            intent            : $map.intent
            owner_name        : $owner_name
            created_at        : $map.created_at
            updated_at        : $map.updated_at
            cloned_from_map_id: $map.cloned_from_map_id
          }
        }
      }
    }
  }

  response = {
    journey_architecture_id: $input.journey_architecture_id
    count                  : $results|count
    scenarios              : $results
  }

  guid = "AzXjUkel1F0INf7GKrZgS22vPKI"
}