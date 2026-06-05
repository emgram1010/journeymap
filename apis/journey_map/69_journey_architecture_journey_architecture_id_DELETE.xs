// Delete a Journey Architecture and all child records (authenticated, owner-scoped).
// Cascade order:
//   agent_message → agent_conversation → journey_cell → journey_lens → journey_stage → journey_map → journey_architecture
query "journey_architecture/{journey_architecture_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
  }

  stack {
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Delete all journey_link records for this architecture first (avoids orphans)
    db.query journey_link {
      where = $db.journey_link.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $links
  
    foreach ($links) {
      each as $link {
        db.del journey_link {
          field_name = "id"
          field_value = $link.id
        }
      }
    }
  
    // Load all journey maps belonging to this architecture
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $maps
  
    // Cascade delete each map and its children
    foreach ($maps) {
      each as $map {
        // Delete agent messages via conversations for this map
        db.query agent_conversation {
          where = $db.agent_conversation.journey_map == $map.id
          return = {type: "list"}
        } as $conversations
      
        foreach ($conversations) {
          each as $conv {
            db.query agent_message {
              where = $db.agent_message.conversation == $conv.id
              return = {type: "list"}
            } as $messages
          
            foreach ($messages) {
              each as $msg {
                db.del agent_message {
                  field_name = "id"
                  field_value = $msg.id
                }
              }
            }
          
            db.del agent_conversation {
              field_name = "id"
              field_value = $conv.id
            }
          }
        }
      
        // Delete cells
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $map.id
          return = {type: "list"}
        } as $cells
      
        foreach ($cells) {
          each as $cell {
            db.del journey_cell {
              field_name = "id"
              field_value = $cell.id
            }
          }
        }
      
        // Delete lenses
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $map.id
          return = {type: "list"}
        } as $lenses
      
        foreach ($lenses) {
          each as $lens {
            db.del journey_lens {
              field_name = "id"
              field_value = $lens.id
            }
          }
        }
      
        // Delete stages
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $map.id
          return = {type: "list"}
        } as $stages
      
        foreach ($stages) {
          each as $stage {
            db.del journey_stage {
              field_name = "id"
              field_value = $stage.id
            }
          }
        }
      
        // Delete the journey map itself
        db.del journey_map {
          field_name = "id"
          field_value = $map.id
        }
      }
    }
  
    // Delete the architecture
    db.del journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    }
  }

  response = {deleted: true, id: $input.journey_architecture_id}
}