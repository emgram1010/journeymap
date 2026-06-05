// List all conversation sessions for a journey map, ordered by last_message_at desc,
// with a message_count per thread. Returns an empty list when none exist.
query "journey_map/{journey_map_id}/conversations" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.query agent_conversation {
      where = $db.agent_conversation.journey_map == $input.journey_map_id
      sort = {last_message_at: "desc"}
      return = {type: "list"}
    } as $conversations
  
    var $result {
      value = []
    }
  
    foreach ($conversations) {
      each as $conv {
        db.query agent_message {
          where = $db.agent_message.conversation == $conv.id
          return = {type: "list"}
        } as $conv_messages
      
        array.push $result {
          value = {
            id             : $conv.id
            journey_map    : $conv.journey_map
            title          : $conv.title
            mode           : $conv.mode
            last_message_at: $conv.last_message_at
            created_at     : $conv.created_at
            message_count  : $conv_messages|count
          }
        }
      }
    }
  }

  response = $result
}