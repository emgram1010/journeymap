// Load a specific conversation session with its full message history.
// Validates the conversation belongs to the given journey map.
//
// US-SEC-1-04 (2026-10-18) — needed no login. A conversation is the
// founder or their team talking to the AI about their own business:
// the interview answers, the figures, the problems. All of it was
// readable by anyone who guessed two integers.
//
// THE "DOES THE MAP EXIST" READ IS NOW THE OWNERSHIP CHECK. This
// endpoint already fetched the map just to 404 on a bad id;
// `journey/assert_map_owner` does that same read and then proves the
// caller's account owns it, so the check costs nothing extra and the
// rule lives in one place for all eight row-touching endpoints in this
// group. A refusal logs `rejected` with E-GOV-001 (GOV-1).
query "journey_map/{journey_map_id}/conversation/{conversation_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int conversation_id? filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor
  
    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $input.journey_map_id
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "get_conversation"
      }
    } as $guard
  
    db.get agent_conversation {
      field_name = "id"
      field_value = $input.conversation_id
    } as $conversation
  
    precondition ($conversation != null) {
      error_type = "notfound"
      error = "Conversation not found"
    }
  
    precondition ($conversation.journey_map == $input.journey_map_id) {
      error_type = "inputerror"
      error = "Conversation does not belong to this journey map"
    }
  
    db.query agent_message {
      where = $db.agent_message.conversation == $conversation.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $messages
  }

  response = {conversation: $conversation, messages: $messages}
}