// Deep-clone a journey map into the same Journey Architecture as a new scenario.
// Clone order: journey_map → journey_stage → journey_lens → journey_cell.
// Stage and lens IDs are remapped via key lookup so cells land in the correct grid position.
// journey_link and agent_conversation records are intentionally NOT cloned — clean slate.
query "journey_architecture/{journey_architecture_id}/scenarios/clone" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    int source_map_id?
    text title? filters=trim
  }

  stack {
    // 1 — Verify architecture and ownership
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch
  
    precondition ($arch != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($arch.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // 2 — Verify source map exists and belongs to this architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.source_map_id
    } as $source
  
    precondition ($source != null) {
      error_type = "notfound"
      error = "Source scenario not found"
    }
  
    precondition ($source.journey_architecture == $input.journey_architecture_id) {
      error_type = "accessdenied"
      error = "Source scenario does not belong to this architecture"
    }
  
    // 3 — Determine title for the clone.
    // Title is always composed on the frontend (xs + operator is numeric-only in API context).
    // Fallback used only when no title is sent (e.g. direct API calls).
    var $new_title {
      value = "Copy of Scenario"
    }
  
    conditional {
      if ($input.title != null && $input.title != "") {
        var.update $new_title {
          value = $input.title
        }
      }
    }
  
    // 4 — Create the new map record (settings reset to null — clean slate)
    db.add journey_map {
      data = {
        created_at          : "now"
        updated_at          : "now"
        last_interaction_at : "now"
        title               : $new_title
        status              : "draft"
        owner_user          : $auth.id
        account_id          : $arch.account_id
        journey_architecture: $input.journey_architecture_id
        cloned_from_map_id  : $input.source_map_id
      }
    } as $new_map
  
    // 5 — Clone stages (preserve key, label, display_order)
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.source_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $source_stages
  
    foreach ($source_stages) {
      each as $stage {
        db.add journey_stage {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $new_map.id
            key          : $stage.key
            label        : $stage.label
            display_order: $stage.display_order
          }
        } as $_stage_added
      }
    }
  
    // 6 — Clone lenses (preserve all actor and persona fields)
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.source_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $source_lenses
  
    foreach ($source_lenses) {
      each as $lens {
        db.add journey_lens {
          data = {
            created_at          : "now"
            updated_at          : "now"
            journey_map         : $new_map.id
            key                 : $lens.key
            label               : $lens.label
            description         : $lens.description
            display_order       : $lens.display_order
            actor_type          : $lens.actor_type
            template_key        : $lens.template_key
            role_prompt         : $lens.role_prompt
            persona_description : $lens.persona_description
            primary_goal        : $lens.primary_goal
            standing_constraints: $lens.standing_constraints
          }
        } as $_lens_added
      }
    }
  
    // 7 — Clone cells
    // Stage and lens IDs differ between source and clone. We resolve the new IDs by
    // fetching the source stage/lens key, then querying the matching new stage/lens by key.
    // journey_links and agent_conversations are intentionally excluded.
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.source_map_id
      return = {type: "list"}
    } as $source_cells
  
    foreach ($source_cells) {
      each as $cell {
        var $new_stage_id {
          value = null
        }
      
        var $new_lens_id {
          value = null
        }
      
        // Resolve new stage ID via key match
        conditional {
          if ($cell.stage != null) {
            db.get journey_stage {
              field_name = "id"
              field_value = $cell.stage
            } as $orig_stage
          
            conditional {
              if ($orig_stage != null) {
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $new_map.id && $db.journey_stage.key == $orig_stage.key
                  return = {type: "single"}
                } as $mapped_stage
              
                conditional {
                  if ($mapped_stage != null) {
                    var.update $new_stage_id {
                      value = $mapped_stage.id
                    }
                  }
                }
              }
            }
          }
        }
      
        // Resolve new lens ID via key match
        conditional {
          if ($cell.lens != null) {
            db.get journey_lens {
              field_name = "id"
              field_value = $cell.lens
            } as $orig_lens
          
            conditional {
              if ($orig_lens != null) {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $new_map.id && $db.journey_lens.key == $orig_lens.key
                  return = {type: "single"}
                } as $mapped_lens
              
                conditional {
                  if ($mapped_lens != null) {
                    var.update $new_lens_id {
                      value = $mapped_lens.id
                    }
                  }
                }
              }
            }
          }
        }
      
        db.add journey_cell {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $new_map.id
            stage        : $new_stage_id
            lens         : $new_lens_id
            content      : $cell.content
            status       : $cell.status
            actor_fields : $cell.actor_fields
            change_source: $cell.change_source
            is_locked    : false
          }
        } as $_cell_added
      }
    }
  
    // 8 — Resolve owner name for response
    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $owner
  
    var $owner_name {
      value = "Unknown"
    }
  
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

  response = {
    id                : $new_map.id
    title             : $new_map.title
    owner_name        : $owner_name
    created_at        : $new_map.created_at
    updated_at        : $new_map.updated_at
    cloned_from_map_id: $new_map.cloned_from_map_id
  }
}