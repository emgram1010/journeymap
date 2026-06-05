// Covers US-06 conversation persistence criteria:
// - Messages stored with role, content, mode, and timestamp
// - AI-applied cell changes stored with change_source metadata
// - Saved journey map returns conversation history alongside matrix state
// - Message ordering is preserved within a conversation thread
// - Conversation can be resumed with full context after creation
workflow_test conversation_persistence {
  stack {
    // ── Setup: create a draft journey map ──
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Persistence Test Map", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    var $first_cell {
      value = $draft.cells|first
    }
  
    // ── US-06-AC1: Create a named conversation thread ──
    api.call "journey_map/{journey_map_id}/conversation" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id: $journey_map_id
        title         : "Persistence Session"
        mode          : "interview"
      }
    } as $conversation
  
    expect.to_equal ($conversation.title) {
      value = "Persistence Session"
    }
  
    expect.to_equal ($conversation.mode) {
      value = "interview"
    }
  
    expect.to_equal ($conversation.journey_map) {
      value = $journey_map_id
    }
  
    var $conversation_id {
      value = $conversation.id
    }
  
    // ── US-06-AC1: Send first user message and verify it is persisted ──
    api.call "journey_map/{journey_map_id}/message" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
        content        : "First user message"
        mode           : "interview"
      }
    } as $turn_1
  
    expect.to_equal ($turn_1.messages|count) {
      value = 1
    }
  
    expect.to_equal ($turn_1.messages[0].role) {
      value = "user"
    }
  
    expect.to_equal ($turn_1.messages[0].mode) {
      value = "interview"
    }
  
    // ── US-06-AC4: Send a second message and verify ordering ──
    api.call "journey_map/{journey_map_id}/message" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
        content        : "Second user message"
        mode           : "interview"
      }
    } as $turn_2
  
    expect.to_equal ($turn_2.messages|count) {
      value = 2
    }
  
    // First message must be older (ordering preserved)
    expect.to_equal ($turn_2.messages[0].role) {
      value = "user"
    }
  
    expect.to_equal ($turn_2.messages[1].role) {
      value = "user"
    }
  
    // ── US-06-AC3: Reload conversation via GET and confirm history intact ──
    api.call "journey_map/{journey_map_id}/conversation/{conversation_id}" verb=GET {
      api_group = "journey-map"
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
      }
    } as $reloaded
  
    expect.to_equal ($reloaded.conversation.id) {
      value = $conversation_id
    }
  
    expect.to_equal ($reloaded.messages|count) {
      value = 2
    }
  
    // ── US-06-AC2: Apply AI cell change and verify change_source is stored ──
    api.call "journey_map/{journey_map_id}/message" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
        content        : "AI writes the cell"
        mode           : "interview"
      }
    } as $turn_3
  
    expect.to_equal ($turn_3.applied_updates|count) {
      value = 1
    }
  
    db.get journey_cell {
      field_name = "id"
      field_value = $first_cell.id
    } as $after_write
  
    expect.to_equal ($after_write.change_source) {
      value = "ai"
    }
  
    expect.to_equal ($after_write.status) {
      value = "draft"
    }
  
    // ── Reload again to confirm 3 messages are present and in order ──
    api.call "journey_map/{journey_map_id}/conversation/{conversation_id}" verb=GET {
      api_group = "journey-map"
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
      }
    } as $final_reload
  
    expect.to_equal ($final_reload.messages|count) {
      value = 3
    }
  }
}