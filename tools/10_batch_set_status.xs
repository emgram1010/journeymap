// Changes status and/or lock state on multiple cells in one call.
// Supports explicit target lists or filter-based matching.
tool batch_set_status {
  instructions = """
      Use this tool to change status and/or lock state on multiple cells at once.
      Instead of calling set_cell_status N times, apply changes in bulk.
    
      Targeting: Provide a JSON array of targets, each with { stage_key, lens_key }.
      Alternatively, provide a filter object to match cells by criteria:
      - filter.stage_key: Match cells in this stage only.
      - filter.lens_key: Match cells in this lens only.
      - filter.status: Match cells with this status (open/draft/confirmed).
      - filter.change_source: Match cells with this source (user/ai).
    
      Set: Provide the changes to apply:
      - status: New status (open/draft/confirmed). Omit to leave unchanged.
      - is_locked: New lock state (true/false). Omit to leave unchanged.
    
      Examples:
      - 'Confirm all draft cells': filter={status:'draft'}, set={status:'confirmed'}
      - 'Lock all confirmed cells': filter={status:'confirmed'}, set={is_locked:true}
      - 'Confirm stage 3': filter={stage_key:'s3'}, set={status:'confirmed'}
    
      Response shape:
      {
        applied_count: int,
        applied: [ { stage_key, lens_key, cell_id, new_status, new_is_locked } ],
        skipped_count: int,
        skipped: [ { stage_key, lens_key, reason } ]
      }
    """

  input {
    // The ID of the journey map.
    int journey_map_id filters=min:1
  
    // Explicit targets: [{ stage_key, lens_key }]. Use this OR filter, not both.
    json targets?
  
    // Filter-based targeting: { stage_key?, lens_key?, status?, change_source? }
    json filter?
  
    // Changes to apply: { status?, is_locked? }
    json set
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
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
  
    precondition ($input.targets != null || $input.filter != null) {
      error_type = "inputerror"
      error = "Provide either targets (array) or filter (object) to select cells."
    }
  
    // Load all stages and lenses for lookup
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses
  
    var $stage_id_by_key {
      value = {}
    }
  
    var $stage_key_by_id {
      value = {}
    }
  
    foreach ($stages) {
      each as $s {
        var.update $stage_id_by_key {
          value = $stage_id_by_key|set:$s.key:$s.id
        }
      
        var.update $stage_key_by_id {
          value = $stage_key_by_id|set:($s.id|to_text):$s.key
        }
      }
    }
  
    var $lens_id_by_key {
      value = {}
    }
  
    var $lens_key_by_id {
      value = {}
    }
  
    foreach ($lenses) {
      each as $l {
        var.update $lens_id_by_key {
          value = $lens_id_by_key|set:$l.key:$l.id
        }
      
        var.update $lens_key_by_id {
          value = $lens_key_by_id|set:($l.id|to_text):$l.key
        }
      }
    }
  
    // Load all cells for this map
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $all_cells
  
    var $applied {
      value = []
    }
  
    var $skipped {
      value = []
    }
  
    var $applied_count {
      value = 0
    }
  
    var $skipped_count {
      value = 0
    }
  
    // ── Build set of target cells ──
    // If explicit targets, resolve each to cell IDs
    // If filter, iterate all cells and check criteria
    foreach ($all_cells) {
      each as $c {
        var $s_key {
          value = $stage_key_by_id|get:($c.stage|to_text)
        }
      
        var $l_key {
          value = $lens_key_by_id|get:($c.lens|to_text)
        }
      
        var $should_apply {
          value = false
        }
      
        conditional {
          if ($input.targets != null) {
            // Check if this cell matches any explicit target
            foreach ($input.targets) {
              each as $t {
                conditional {
                  if ($t.stage_key == $s_key && $t.lens_key == $l_key) {
                    var.update $should_apply {
                      value = true
                    }
                  }
                }
              }
            }
          }
        
          else {
            // Filter mode: check all criteria
            var.update $should_apply {
              value = true
            }
          
            conditional {
              if ($input.filter.stage_key != null && $s_key != $input.filter.stage_key) {
                var.update $should_apply {
                  value = false
                }
              }
            }
          
            conditional {
              if ($input.filter.lens_key != null && $l_key != $input.filter.lens_key) {
                var.update $should_apply {
                  value = false
                }
              }
            }
          
            conditional {
              if ($input.filter.status != null && $c.status != $input.filter.status) {
                var.update $should_apply {
                  value = false
                }
              }
            }
          
            conditional {
              if ($input.filter.change_source != null && $c.change_source != $input.filter.change_source) {
                var.update $should_apply {
                  value = false
                }
              }
            }
          }
        }
      
        // ── Apply or skip ──
        conditional {
          if ($should_apply) {
            // Build patch data
            var $patch_data {
              value = {updated_at: "now", last_updated_at: "now"}
            }
          
            conditional {
              if ($input.set.status != null) {
                var.update $patch_data {
                  value = $patch_data|set:"status":$input.set.status
                }
              }
            }
          
            conditional {
              if ($input.set.is_locked != null) {
                var.update $patch_data {
                  value = $patch_data
                    |set:"is_locked":$input.set.is_locked
                }
              }
            }
          
            db.patch journey_cell {
              field_name = "id"
              field_value = $c.id
              data = $patch_data
            } as $updated_cell
          
            array.push $applied {
              value = {
                stage_key    : $s_key
                lens_key     : $l_key
                cell_id      : $updated_cell.id
                new_status   : $updated_cell.status
                new_is_locked: $updated_cell.is_locked
              }
            }
          
            var.update $applied_count {
              value = $applied_count + 1
            }
          }
        }
      }
    }
  
    // Touch journey map timestamp once
    conditional {
      if ($applied_count > 0) {
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $map_touch
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "batch_set_status"
            tool_category : "status"
            input_summary : $applied_count ~ " cells targeted"
            output_summary: $applied_count ~ " applied, " ~ $skipped_count ~ " skipped"
          }
        } as $tool_log
      }
    }
  }

  response = {
    applied_count: $applied_count
    applied      : $applied
    skipped_count: $skipped_count
    skipped      : $skipped
  }
}