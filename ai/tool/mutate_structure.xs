// Adds, removes, renames, places and reorders stages and lenses in a journey map.
//
// ORD-2: every structural action now runs the same shared journey/* function
// the matrix buttons run, so the AI and the screen cannot disagree. Four of
// these branches used to call api.call with an empty path in an empty API
// group, and so reported success while changing nothing.
tool mutate_structure {
  instructions = """
      Use this tool to reshape the journey map structure when the user describes a workflow
      that doesn't fit the current template.
    
      Supported actions:
      - add_stage: Adds a new stage (column) and scaffolds cells for all existing lenses.
        Pass after_stage_key to place it: the key of the column to insert AFTER, or
        "__first__" for the very front. Omit it to append to the end.
      - remove_stage: Removes a stage and cascades cell deletion. Must keep at least 1 stage.
      - rename_stage: Updates only the display label of a stage. The key remains stable.
      - add_lens: Adds a new lens (row) and scaffolds cells for all existing stages.
        Pass after_lens_key to place it: the key of the row to insert AFTER, or
        "__first__" for the very front. Omit it to append to the bottom.
      - remove_lens: Removes a lens and cascades cell deletion. Must keep at least 1 lens.
      - rename_lens: Updates only the display label of a lens. The key remains stable.
      - reorder_stages: Reorders stages by providing all stage keys in the desired order. No cell content is lost.
      - reorder_lenses: Reorders lenses by providing all lens keys in the desired order. No cell content is lost.
    
      Input:
      - journey_map_id: The ID of the journey map
      - action: One of add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens, reorder_stages, reorder_lenses
      - label: Required for add_* and rename_* actions. The display label.
      - target_key: Required for remove_* and rename_* actions. The key of the stage/lens to target.
      - keys_in_order: Required for reorder_* actions. JSON array of all keys in the desired display order.
      - actor_type (add_lens only, optional): one of customer, internal, engineering, ai_agent, handoff, vendor, financial, metrics. When provided the lens is created with the matching template_key, role_prompt, and cells are pre-scaffolded with actor_fields. An actor type outside that list is refused, not guessed.
      - after_stage_key / after_lens_key (add_stage / add_lens only, optional): the key of the column or row to insert AFTER, or "__first__" for the very front. Omit to append. A key this map does not have is refused and names itself in the message.

      A key you invent will be refused, not silently skipped. Always read the map
      first and use keys it actually has.
    
      Response shape:
      {
        action: string,
        success: boolean,
        result: { ... action-specific result ... },
        error: null | string
      }
    """

  input {
    // The ID of the journey map to modify.
    int journey_map_id filters=min:1
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
  
    // The structural action: add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens, reorder_stages, reorder_lenses.
    text action filters=trim
  
    // The display label for add or rename actions.
    text label? filters=trim
  
    // The key of the stage or lens to remove or rename.
    text target_key? filters=trim
  
    // Ordered array of keys for reorder_stages / reorder_lenses.
    json keys_in_order?
  
    // Actor type for add_lens action (optional): customer, internal,
    // engineering, ai_agent, handoff, vendor, financial, metrics.
    text actor_type? filters=trim

    // ORD-2 (US-ORD-2-06) — where to put a new column or row.
    // Omit to append. Pass the KEY of the column/row to insert AFTER, or the
    // literal "__first__" to put it at the very front. A key this map does
    // not have is refused by name (E-ORD-003), never ignored.
    text after_stage_key? filters=trim
    text after_lens_key? filters=trim
  }

  stack {
    var $result {
      value = {
        action : $input.action
        success: false
        result : null
        error  : null
      }
    }
  
    conditional {
      if ($input.action == "add_stage") {
        precondition ($input.label != "") {
          error_type = "inputerror"
          error = "label is required for add_stage"
        }

        // ORD-2 (US-ORD-2-06) — optional placement. after_stage_key is a
        // KEY, because that is what the AI reasons in and what get_map_state
        // hands it. Empty means append; "__first__" means put it at the very
        // front; anything else must be a real key of this map.
        //
        // A key the AI invented must FAIL BY NAME, not be quietly ignored —
        // the whole point of this epic is that silent no-ops are what broke
        // trust in the first place. One query, read with |get:"id":0 so a
        // miss is 0 rather than a crash, and no conditional reads a variable
        // written inside a loop (CLAUDE.md).
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.after_stage_key
          return = {type: "single"}
        } as $anchor_hit_stage

        var $anchor_id_stage {
          value = $anchor_hit_stage|get:"id":0
        }

        var $anchor_named_stage {
          value = ($input.after_stage_key != "") && ($input.after_stage_key != "__first__")
        }

        var $anchor_miss_msg_stage {
          value = "I could not find a column with the key %s in this map, so nothing was added. Read the map again and use a key it actually has. (E-ORD-003)"|sprintf:$input.after_stage_key
        }

        precondition ($anchor_named_stage == false || $anchor_id_stage > 0) {
          error_type = "inputerror"
          error = $anchor_miss_msg_stage
        }

        var $place_stage {
          value = -1
        }

        conditional {
          if ($input.after_stage_key == "__first__") {
            var.update $place_stage {
              value = 0
            }
          }
        }

        conditional {
          if ($anchor_named_stage == true) {
            var.update $place_stage {
              value = $anchor_id_stage
            }
          }
        }

        // ORD-2 (US-ORD-2-05): this used to be api.call with an empty path in
        // an empty API group. It reported success and changed nothing, every
        // time, since the tool was built. journey/insert_stage is the same
        // code the matrix buttons run.
        function.run "journey/insert_stage" {
          input = {
            journey_map_id: $input.journey_map_id
            after_stage_id: $place_stage
            label         : $input.label
            step          : "ai_add_stage"
          }
        } as $add_stage_result

        var.update $result {
          value = {
            action : "add_stage"
            success: true
            result : $add_stage_result
            error  : null
          }
        }
      }

      elseif ($input.action == "remove_stage") {
        precondition ($input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for remove_stage"
        }

        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.target_key
          return = {type: "single"}
        } as $target_stage

        var $target_stage_id {
          value = $target_stage|get:"id":0
        }

        var $stage_miss_msg {
          value = "I could not find a column with the key %s in this map, so nothing was removed. (E-ORD-003)"|sprintf:$input.target_key
        }

        precondition ($target_stage_id > 0) {
          error_type = "notfound"
          error = $stage_miss_msg
        }

        // ORD-2 (US-ORD-2-05): was an empty api.call — a no-op that reported
        // success. journey/remove_stage deletes each cell by its own id inside
        // a transaction, closes the numbering gap, and refuses if a published
        // plan still points at this key (E-ORD-005).
        function.run "journey/remove_stage" {
          input = {
            journey_stage_id: $target_stage_id
            step            : "ai_remove_stage"
          }
        } as $remove_stage_result

        var.update $result {
          value = {
            action : "remove_stage"
            success: true
            result : $remove_stage_result
            error  : null
          }
        }
      }

      elseif ($input.action == "rename_stage") {
        precondition ($input.target_key != null && $input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for rename_stage"
        }
      
        precondition ($input.label != null && $input.label != "") {
          error_type = "inputerror"
          error = "label is required for rename_stage"
        }
      
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.target_key
          return = {type: "single"}
        } as $rename_stage_target
      
        precondition ($rename_stage_target != null) {
          error_type = "notfound"
          error = "Stage not found with key: " + $input.target_key
        }
      
        db.edit journey_stage {
          field_name = "id"
          field_value = $rename_stage_target.id
          enforce_hidden_fields = false
          data = {label: $input.label, updated_at: "now"}
        } as $rename_stage_result
      
        var.update $result {
          value = {
            action : "rename_stage"
            success: true
            result : $rename_stage_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "add_lens") {
        precondition ($input.label != "") {
          error_type = "inputerror"
          error = "label is required for add_lens"
        }

        // ORD-2 (US-ORD-2-06) — optional placement, same rule as add_stage.
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.after_lens_key
          return = {type: "single"}
        } as $anchor_hit_lens

        var $anchor_id_lens {
          value = $anchor_hit_lens|get:"id":0
        }

        var $anchor_named_lens {
          value = ($input.after_lens_key != "") && ($input.after_lens_key != "__first__")
        }

        var $anchor_miss_msg_lens {
          value = "I could not find a row with the key %s in this map, so nothing was added. Read the map again and use a key it actually has. (E-ORD-003)"|sprintf:$input.after_lens_key
        }

        precondition ($anchor_named_lens == false || $anchor_id_lens > 0) {
          error_type = "inputerror"
          error = $anchor_miss_msg_lens
        }

        var $place_lens {
          value = -1
        }

        conditional {
          if ($input.after_lens_key == "__first__") {
            var.update $place_lens {
              value = 0
            }
          }
        }

        conditional {
          if ($anchor_named_lens == true) {
            var.update $place_lens {
              value = $anchor_id_lens
            }
          }
        }

        // ORD-2 (US-ORD-2-01 / 05): this branch used to carry its own copy of
        // the per-actor-type role prompts and actor_fields scaffolds — a copy
        // that had NO financial and NO metrics case, so asking the AI for a
        // financial row produced a row with no fields and no prompt. The
        // templates now live in journey/actor_template, called by
        // journey/insert_lens, which is also what journey_lens/add runs.
        function.run "journey/insert_lens" {
          input = {
            journey_map_id: $input.journey_map_id
            after_lens_id : $place_lens
            label         : $input.label
            actor_type    : $input.actor_type
            step          : "ai_add_lens"
          }
        } as $add_lens_result

        var.update $result {
          value = {
            action : "add_lens"
            success: true
            result : $add_lens_result
            error  : null
          }
        }
      }

      elseif ($input.action == "remove_lens") {
        precondition ($input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for remove_lens"
        }

        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.target_key
          return = {type: "single"}
        } as $target_lens

        var $target_lens_id {
          value = $target_lens|get:"id":0
        }

        var $lens_miss_msg {
          value = "I could not find a row with the key %s in this map, so nothing was removed. (E-ORD-003)"|sprintf:$input.target_key
        }

        precondition ($target_lens_id > 0) {
          error_type = "notfound"
          error = $lens_miss_msg
        }

        // ORD-2 (US-ORD-2-05): was an empty api.call. journey/remove_lens also
        // clears any stage that named this row as its accountable actor, which
        // nothing used to do.
        function.run "journey/remove_lens" {
          input = {
            journey_lens_id: $target_lens_id
            step           : "ai_remove_lens"
          }
        } as $remove_lens_result

        var.update $result {
          value = {
            action : "remove_lens"
            success: true
            result : $remove_lens_result
            error  : null
          }
        }
      }

      elseif ($input.action == "rename_lens") {
        precondition ($input.target_key != null && $input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for rename_lens"
        }
      
        precondition ($input.label != null && $input.label != "") {
          error_type = "inputerror"
          error = "label is required for rename_lens"
        }
      
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.target_key
          return = {type: "single"}
        } as $rename_lens_target
      
        precondition ($rename_lens_target != null) {
          error_type = "notfound"
          error = "Lens not found with key: " + $input.target_key
        }
      
        db.edit journey_lens {
          field_name = "id"
          field_value = $rename_lens_target.id
          enforce_hidden_fields = false
          data = {label: $input.label, updated_at: "now"}
        } as $rename_lens_result
      
        var.update $result {
          value = {
            action : "rename_lens"
            success: true
            result : $rename_lens_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "reorder_stages") {
        precondition ($input.keys_in_order != null) {
          error_type = "inputerror"
          error = "keys_in_order is required for reorder_stages"
        }

        // ORD-1 (US-ORD-1-06): the AI reorders through the SAME rule as the
        // matrix arrows — journey/apply_stage_order — so the two can never
        // disagree about what a legal order is. Keys are turned into ids
        // one lookup per key, with no conditional in the loop: the old
        // version decided whether to write by testing a var it had just
        // updated in the same iteration, which is the CLAUDE.md pattern
        // where every write in the branch is silently discarded. A key that
        // is not in this map yields id 0, and the shared function then
        // refuses the whole order (E-ORD-001) instead of skipping it.
        var $reorder_ids {
          value = []
        }

        foreach ($input.keys_in_order) {
          each as $key {
            db.query journey_stage {
              where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $key
              return = {type: "single"}
            } as $hit

            array.push $reorder_ids {
              value = $hit|get:"id":0
            }
          }
        }

        function.run "journey/apply_stage_order" {
          input = {
            journey_map_id: $input.journey_map_id
            stage_ids     : $reorder_ids
            step          : "ai_reorder_stages"
          }
        } as $reorder_applied

        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $reorder_map_touch

        var.update $result {
          value = {
            action : "reorder_stages"
            success: true
            result : {items: $reorder_applied.order}
            error  : null
          }
        }
      }

      elseif ($input.action == "reorder_lenses") {
        precondition ($input.keys_in_order != null) {
          error_type = "inputerror"
          error = "keys_in_order is required for reorder_lenses"
        }

        // ORD-1 (US-ORD-1-06): same shared rule as reorder_stages, via
        // journey/apply_lens_order.
        var $reorder_ids {
          value = []
        }

        foreach ($input.keys_in_order) {
          each as $key {
            db.query journey_lens {
              where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $key
              return = {type: "single"}
            } as $hit

            array.push $reorder_ids {
              value = $hit|get:"id":0
            }
          }
        }

        function.run "journey/apply_lens_order" {
          input = {
            journey_map_id: $input.journey_map_id
            lens_ids      : $reorder_ids
            step          : "ai_reorder_lenses"
          }
        } as $reorder_applied

        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $reorder_map_touch

        var.update $result {
          value = {
            action : "reorder_lenses"
            success: true
            result : {items: $reorder_applied.order}
            error  : null
          }
        }
      }

      else {
        var.update $result {
          value = {
            action : $input.action
            success: false
            result : null
            error  : "Unknown action. Use: add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens, reorder_stages, reorder_lenses"
          }
        }
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        var $ms_input_summary {
          value = $input.action
        }
      
        conditional {
          if ($input.label != null) {
            var.update $ms_input_summary {
              value = $ms_input_summary ~ ": " ~ $input.label
            }
          }
        }
      
        conditional {
          if ($input.target_key != null) {
            var.update $ms_input_summary {
              value = $ms_input_summary ~ " (key: " ~ $input.target_key ~ ")"
            }
          }
        }
      
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "mutate_structure"
            tool_category : "structure"
            input_summary : $ms_input_summary
            output_summary: $result.success ? "Success" : "Failed: " ~ $result.error
          }
        } as $tool_log
      }
    }
  }

  response = $result
  guid = "v_CjcVOpEMS-4JZXVT3nSQ9kb0I"
}