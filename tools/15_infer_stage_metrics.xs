// Infers metrics field values for a metrics-lens cell from existing data and optional notes.
// Returns suggested values only — does NOT write to the cell. Agent must confirm with user first.
tool infer_stage_metrics {
  instructions = """
      Use this tool to infer metric values for a cell that belongs to a metrics lens row.
      It reads the current actor_fields for the cell, computes stage_health from available
      numeric fields, and returns suggestions for any null fields based on the notes you provide.
    
      This tool is READ-ONLY. It does NOT write to the cell. After confirming suggestions
      with the user, call update_actor_cell_fields to persist the values.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_key: The key of the target stage
      - lens_key: The key of the target metrics lens
      - notes: (optional) Qualitative description of this stage from the user. Used to infer
               field values when they are currently null.
      - conversation_id: (optional) for tool trace logging
      - turn_id: (optional) for tool trace logging
    
      Response shape:
      {
        cell_found: true/false,
        current_fields: { csat_score, completion_rate, drop_off_rate, avg_time_to_complete,
                          error_rate, sla_compliance_rate, volume_frequency, stage_health },
        computed_stage_health: number | null,
        health_label: "healthy" | "at_risk" | "critical" | null,
        notes_received: string | null
      }
    """

  input {
    int journey_map_id filters=min:1
    int conversation_id?
    text turn_id?
    text stage_key filters=trim
    text lens_key filters=trim
    text notes?
  }

  stack {
    // Resolve stage
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
      return = {type: "single"}
    } as $stage
  
    // Resolve lens
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
      return = {type: "single"}
    } as $lens
  
    var $result {
      value = {
        cell_found           : false
        current_fields       : null
        computed_stage_health: null
        health_label         : null
        notes_received       : null
      }
    }
  
    conditional {
      if ($stage != null && $lens != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
          return = {type: "single"}
        } as $cell
      
        conditional {
          if ($cell != null) {
            var $af {
              value = $cell.actor_fields
            }
          
            // Compute stage_health from available numeric fields
            var $score_sum {
              value = 0
            }
          
            var $score_count {
              value = 0
            }
          
            // csat_score: scale 1-10 -> 0-100 for averaging
            var $v_csat {
              value = $af|get:"csat_score"
            }
          
            conditional {
              if ($v_csat != null) {
                var.update $score_sum {
                  value = $score_sum + ($v_csat * 10)
                }
              
                var.update $score_count {
                  value = $score_count + 1
                }
              }
            }
          
            // completion_rate: higher is better
            var $v_cr {
              value = $af|get:"completion_rate"
            }
          
            conditional {
              if ($v_cr != null) {
                var.update $score_sum {
                  value = $score_sum + $v_cr
                }
              
                var.update $score_count {
                  value = $score_count + 1
                }
              }
            }
          
            // drop_off_rate: lower is better -> invert
            var $v_dor {
              value = $af|get:"drop_off_rate"
            }
          
            conditional {
              if ($v_dor != null) {
                var.update $score_sum {
                  value = $score_sum + (100 - $v_dor)
                }
              
                var.update $score_count {
                  value = $score_count + 1
                }
              }
            }
          
            // error_rate: lower is better -> invert
            var $v_er {
              value = $af|get:"error_rate"
            }
          
            conditional {
              if ($v_er != null) {
                var.update $score_sum {
                  value = $score_sum + (100 - $v_er)
                }
              
                var.update $score_count {
                  value = $score_count + 1
                }
              }
            }
          
            // sla_compliance_rate: higher is better
            var $v_sla {
              value = $af|get:"sla_compliance_rate"
            }
          
            conditional {
              if ($v_sla != null) {
                var.update $score_sum {
                  value = $score_sum + $v_sla
                }
              
                var.update $score_count {
                  value = $score_count + 1
                }
              }
            }
          
            var $computed_health {
              value = null
            }
          
            conditional {
              if ($score_count > 0) {
                var.update $computed_health {
                  value = ($score_sum / $score_count / 10)|round:1
                }
              }
            }
          
            var $health_label {
              value = null
            }
          
            conditional {
              if ($computed_health != null && $computed_health >= 8) {
                var.update $health_label {
                  value = "healthy"
                }
              }
            }
          
            conditional {
              if ($computed_health != null && $computed_health >= 5 && $computed_health < 8) {
                var.update $health_label {
                  value = "at_risk"
                }
              }
            }
          
            conditional {
              if ($computed_health != null && $computed_health < 5) {
                var.update $health_label {
                  value = "critical"
                }
              }
            }
          
            var.update $result {
              value = {
                cell_found           : true
                current_fields       : $af
                computed_stage_health: $computed_health
                health_label         : $health_label
                notes_received       : $input.notes
              }
            }
          }
        }
      }
    }
  }

  response = $result
}