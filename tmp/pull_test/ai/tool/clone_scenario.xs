// SCN-MCP-2: MCP tool — deep-clone a journey map into a new scenario within the same architecture.
// Maps to POST /journey_architecture/{id}/scenarios/clone
// Clone order: journey_map → journey_stage → journey_lens → journey_cell
// journey_link and agent_conversation records are intentionally NOT cloned.
tool clone_scenario {
  instructions = "Deep-clone an existing journey map into a new scenario within the same architecture. Returns the new map id — pass it directly to fill_cells or scaffold_map to make targeted modifications. journey_link records and AI conversation history are NOT cloned — the scenario starts clean. Always pass a descriptive title — the backend fallback is a generic string."

  input {
    int journey_architecture_id filters=min:1
    int source_map_id filters=min:1
    text title? filters=trim
  }

  stack {
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch
  
    precondition ($arch != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.source_map_id
    } as $source
  
    precondition ($source != null) {
      error_type = "notfound"
      error = "Source journey map not found"
    }
  
    precondition ($source.journey_architecture == $input.journey_architecture_id) {
      error_type = "accessdenied"
      error = "Source map does not belong to this architecture"
    }
  
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
  
    // 1 — Clone the map record
    db.add journey_map {
      data = {
        created_at          : "now"
        updated_at          : "now"
        last_interaction_at : "now"
        title               : $new_title
        status              : "draft"
        journey_architecture: $input.journey_architecture_id
        account_id          : $arch.account_id
        cloned_from_map_id  : $input.source_map_id
      }
    } as $new_map
  
    // 2 — Clone stages
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
            stage_goal   : $stage.stage_goal
          }
        } as $_s
      }
    }
  
    // 3 — Clone lenses
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
            display_order       : $lens.display_order
            actor_type          : $lens.actor_type
            template_key        : $lens.template_key
            role_prompt         : $lens.role_prompt
            persona_description : $lens.persona_description
            primary_goal        : $lens.primary_goal
            standing_constraints: $lens.standing_constraints
          }
        } as $_l
      }
    }
  
    // 4 — Clone cells (remap stage/lens IDs via key lookup)
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.source_map_id
      return = {type: "list"}
    } as $source_cells
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $new_map.id
      return = {type: "list"}
    } as $new_stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $new_map.id
      return = {type: "list"}
    } as $new_lenses
  
    foreach ($source_cells) {
      each as $cell {
        var $matched_stage_id {
          value = null
        }
      
        foreach ($new_stages) {
          each as $ns {
            conditional {
              if ($ns.key == $cell.stage_key) {
                var.update $matched_stage_id {
                  value = $ns.id
                }
              }
            }
          }
        }
      
        var $matched_lens_id {
          value = null
        }
      
        foreach ($new_lenses) {
          each as $nl {
            conditional {
              if ($nl.key == $cell.lens_key) {
                var.update $matched_lens_id {
                  value = $nl.id
                }
              }
            }
          }
        }
      
        conditional {
          if ($matched_stage_id != null && $matched_lens_id != null) {
            db.add journey_cell {
              data = {
                created_at  : "now"
                updated_at  : "now"
                journey_map : $new_map.id
                stage       : $matched_stage_id
                lens        : $matched_lens_id
                content     : $cell.content
                status      : $cell.status
                is_locked   : false
                actor_fields: $cell.actor_fields
              }
            } as $_c
          }
        }
      }
    }
  }

  response = {
    id                  : $new_map.id
    title               : $new_map.title
    status              : $new_map.status
    cloned_from_map_id  : $new_map.cloned_from_map_id
    journey_architecture: $new_map.journey_architecture
    created_at          : $new_map.created_at
  }

  guid = "1FP0jFNc7G1gIp-RJwp95JFt1x8"
}