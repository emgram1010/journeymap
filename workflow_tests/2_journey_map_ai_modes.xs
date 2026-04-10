// Covers chat non-mutation, locked-cell skipping, and interview-mode AI updates.
// Verifies chat mode does not mutate cells, locked cells are skipped, and interview mode applies AI updates to unlocked cells.
workflow_test journey_map_ai_modes {
  stack {
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Workflow AI Test", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    var $first_cell {
      value = $draft.cells|first
    }
  
    api.call "journey_map/{journey_map_id}/message" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id: $journey_map_id
        content       : "Chat should not change cells"
        mode          : "chat"
      }
    } as $chat_message
  
    expect.to_equal ($chat_message.proposed_updates|count) {
      value = 0
    }
  
    expect.to_equal ($chat_message.applied_updates|count) {
      value = 0
    }
  
    expect.to_equal ($chat_message.skipped_updates|count) {
      value = 0
    }
  
    expect.to_equal ($chat_message.messages|count) {
      value = 1
    }
  
    expect.to_equal ($chat_message.conversation.mode) {
      value = "chat"
    }
  
    db.get journey_cell {
      field_name = "id"
      field_value = $first_cell.id
    } as $after_chat
  
    expect.to_equal ($after_chat.content) {
      value = ""
    }
  
    expect.to_equal ($after_chat.status) {
      value = "open"
    }
  
    expect.to_be_false ($after_chat.is_locked)
    api.call "journey_cell/update/{journey_cell_id}" verb=PATCH {
      api_group = "journey-map"
      input = {journey_cell_id: $first_cell.id, is_locked: true}
    } as $lock_cell
  
    expect.to_be_true ($lock_cell.is_locked)
    api.call "journey_map/{journey_map_id}/message" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id: $journey_map_id
        content       : "AI should skip locked cell"
        mode          : "interview"
      }
    } as $locked_interview
  
    var $locked_skip {
      value = $locked_interview.skipped_updates|first
    }
  
    expect.to_equal ($locked_interview.proposed_updates|count) {
      value = 0
    }
  
    expect.to_equal ($locked_interview.applied_updates|count) {
      value = 0
    }
  
    expect.to_equal ($locked_interview.skipped_updates|count) {
      value = 1
    }
  
    expect.to_equal ($locked_skip.journey_cell_id) {
      value = $first_cell.id
    }
  
    expect.to_equal ($locked_skip.skip_reason) {
      value = "locked"
    }
  
    db.get journey_cell {
      field_name = "id"
      field_value = $first_cell.id
    } as $after_locked_interview
  
    expect.to_equal ($after_locked_interview.content) {
      value = ""
    }
  
    expect.to_equal ($after_locked_interview.status) {
      value = "open"
    }
  
    expect.to_be_true ($after_locked_interview.is_locked)
    api.call "journey_cell/update/{journey_cell_id}" verb=PATCH {
      api_group = "journey-map"
      input = {journey_cell_id: $first_cell.id, is_locked: false}
    } as $unlock_cell
  
    expect.to_be_false ($unlock_cell.is_locked)
    api.call "journey_map/{journey_map_id}/message" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id: $journey_map_id
        content       : "AI generated insight"
        mode          : "interview"
      }
    } as $applied_interview
  
    var $applied_update {
      value = $applied_interview.applied_updates|first
    }
  
    expect.to_equal ($applied_interview.proposed_updates|count) {
      value = 1
    }
  
    expect.to_equal ($applied_interview.applied_updates|count) {
      value = 1
    }
  
    expect.to_equal ($applied_interview.skipped_updates|count) {
      value = 0
    }
  
    expect.to_equal ($applied_update.journey_cell_id) {
      value = $first_cell.id
    }
  
    expect.to_equal ($applied_update.content) {
      value = "AI generated insight"
    }
  
    expect.to_equal ($applied_update.status) {
      value = "draft"
    }
  
    expect.to_equal ($applied_update.change_source) {
      value = "ai"
    }
  
    expect.to_equal ($applied_interview.conversation.mode) {
      value = "interview"
    }
  
    db.get journey_cell {
      field_name = "id"
      field_value = $first_cell.id
    } as $after_ai_apply
  
    expect.to_equal ($after_ai_apply.content) {
      value = "AI generated insight"
    }
  
    expect.to_equal ($after_ai_apply.status) {
      value = "draft"
    }
  
    expect.to_equal ($after_ai_apply.change_source) {
      value = "ai"
    }
  
    expect.to_be_false ($after_ai_apply.is_locked)
  }
}