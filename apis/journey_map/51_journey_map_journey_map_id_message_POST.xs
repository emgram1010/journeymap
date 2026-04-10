// Append a persisted expert/assistant exchange and safely persist interview-mode AI updates.
query "journey_map/{journey_map_id}/message" verb=POST {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    int conversation_id?
    text content? filters=trim
    text assistant_reply? filters=trim
    enum mode? {
      values = ["interview", "chat"]
    }
  }

  stack {
    var $conversation {
      value = null
    }
  
    var $proposed_updates {
      value = []
    }
  
    var $applied_updates {
      value = []
    }
  
    var $skipped_updates {
      value = []
    }
  
    var $proposal_cell {
      value = null
    }
  
    var $proposal_stage {
      value = null
    }
  
    var $proposal_lens {
      value = null
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($input.content != null && $input.content != "") {
      error_type = "inputerror"
      error = "Message content is required"
    }
  
    precondition ($input.mode != null) {
      error_type = "inputerror"
      error = "Message mode is required"
    }
  
    conditional {
      if ($input.conversation_id != null) {
        db.get agent_conversation {
          field_name = "id"
          field_value = $input.conversation_id
        } as $requested_conversation
      
        precondition ($requested_conversation != null && $requested_conversation.journey_map == $input.journey_map_id) {
          error_type = "inputerror"
          error = "Conversation does not belong to this journey map"
        }
      
        var.update $conversation {
          value = $requested_conversation
        }
      }
    
      else {
        db.query agent_conversation {
          where = $db.agent_conversation.journey_map == $input.journey_map_id
          sort = {last_message_at: "desc"}
          return = {type: "list"}
        } as $existing_conversations
      
        conditional {
          if (($existing_conversations|count) > 0) {
            var.update $conversation {
              value = $existing_conversations|first
            }
          }
        }
      }
    }
  
    conditional {
      if ($conversation == null) {
        db.add agent_conversation {
          data = {
            created_at     : "now"
            journey_map    : $input.journey_map_id
            title          : "Journey Map Conversation"
            mode           : $input.mode
            last_message_at: "now"
          }
        } as $created_conversation
      
        var.update $conversation {
          value = $created_conversation
        }
      }
    }
  
    db.add agent_message {
      data = {
        created_at  : "now"
        conversation: $conversation.id
        role        : "user"
        mode        : $input.mode
        content     : []|push:({}|set:"type":"text"|set:"text":$input.content)
      }
    } as $user_message
  
    conditional {
      if ($input.assistant_reply != null && $input.assistant_reply != "") {
        db.add agent_message {
          data = {
            created_at  : "now"
            conversation: $conversation.id
            role        : "assistant"
            mode        : $input.mode
            content     : []|push:({}|set:"type":"text"|set:"text":$input.assistant_reply)
          }
        } as $assistant_message
      }
    }
  
    conditional {
      if ($input.mode == "interview") {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.status != "confirmed"
          sort = {id: "asc"}
          return = {type: "list"}
        } as $candidate_cells
      
        conditional {
          if (($candidate_cells|count) > 0) {
            var.update $proposal_cell {
              value = $candidate_cells|first
            }
          
            db.get journey_stage {
              field_name = "id"
              field_value = $proposal_cell.stage
            } as $matched_stage
          
            db.get journey_lens {
              field_name = "id"
              field_value = $proposal_cell.lens
            } as $matched_lens
          
            var.update $proposal_stage {
              value = $matched_stage
            }
          
            var.update $proposal_lens {
              value = $matched_lens
            }
          
            // Stale-target guard: skip if the cell's stage or lens was deleted.
            // Otherwise check locked status, then apply the update.
            conditional {
              if ($matched_stage == null || $matched_lens == null) {
                array.push $skipped_updates {
                  value = {
                    journey_cell_id: $proposal_cell.id
                    journey_map_id : $proposal_cell.journey_map
                    stage_id       : $proposal_cell.stage
                    stage_key      : null
                    stage_label    : null
                    lens_id        : $proposal_cell.lens
                    lens_key       : null
                    lens_label     : null
                    content        : $input.content
                    status         : "draft"
                    change_source  : "ai"
                    is_locked      : false
                    skipped        : true
                    skip_reason    : "stale_target"
                  }
                }
              }
            
              else {
                conditional {
                  if ($proposal_cell.is_locked) {
                    array.push $skipped_updates {
                      value = {
                        journey_cell_id: $proposal_cell.id
                        journey_map_id : $proposal_cell.journey_map
                        stage_id       : $proposal_cell.stage
                        stage_key      : $proposal_stage.key
                        stage_label    : $proposal_stage.label
                        lens_id        : $proposal_cell.lens
                        lens_key       : $proposal_lens.key
                        lens_label     : $proposal_lens.label
                        content        : $input.content
                        status         : "draft"
                        change_source  : "ai"
                        is_locked      : true
                        skipped        : true
                        skip_reason    : "locked"
                      }
                    }
                  }
                
                  else {
                    db.patch journey_cell {
                      field_name = "id"
                      field_value = $proposal_cell.id
                      data = {
                        content        : $input.content
                        status         : "draft"
                        change_source  : "ai"
                        updated_at     : "now"
                        last_updated_at: "now"
                      }
                    } as $ai_updated_cell
                  
                    precondition ($ai_updated_cell != null) {
                      error = "Failed to apply AI journey cell update"
                    }
                  
                    array.push $proposed_updates {
                      value = {
                        journey_cell_id: $ai_updated_cell.id
                        journey_map_id : $ai_updated_cell.journey_map
                        stage_id       : $ai_updated_cell.stage
                        stage_key      : $proposal_stage.key
                        stage_label    : $proposal_stage.label
                        lens_id        : $ai_updated_cell.lens
                        lens_key       : $proposal_lens.key
                        lens_label     : $proposal_lens.label
                        content        : $ai_updated_cell.content
                        status         : $ai_updated_cell.status
                        change_source  : $ai_updated_cell.change_source
                        is_locked      : $ai_updated_cell.is_locked
                      }
                    }
                  
                    array.push $applied_updates {
                      value = {
                        journey_cell_id: $ai_updated_cell.id
                        journey_map_id : $ai_updated_cell.journey_map
                        stage_id       : $ai_updated_cell.stage
                        stage_key      : $proposal_stage.key
                        stage_label    : $proposal_stage.label
                        lens_id        : $ai_updated_cell.lens
                        lens_key       : $proposal_lens.key
                        lens_label     : $proposal_lens.label
                        content        : $ai_updated_cell.content
                        status         : $ai_updated_cell.status
                        change_source  : $ai_updated_cell.change_source
                        is_locked      : $ai_updated_cell.is_locked
                        updated_at     : $ai_updated_cell.updated_at
                        last_updated_at: $ai_updated_cell.last_updated_at
                        skipped        : false
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  
    db.patch agent_conversation {
      field_name = "id"
      field_value = $conversation.id
      data = {mode: $input.mode, last_message_at: "now"}
    } as $conversation_touch
  
    precondition ($conversation_touch != null) {
      error = "Failed to update conversation"
    }
  
    db.get agent_conversation {
      field_name = "id"
      field_value = $conversation.id
    } as $conversation_record
  
    db.query agent_message {
      where = $db.agent_message.conversation == $conversation.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $messages
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch
  }

  response = {
    conversation          : $conversation_record
    messages              : $messages
    proposed_updates      : $proposed_updates
    applied_updates       : $applied_updates
    skipped_updates       : $skipped_updates
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}