// Applies a complete structural blueprint to a journey map in one call.
// Supports bulk rename, add, and remove operations for both stages and lenses.
// Replaces 6-8 individual mutate_structure calls at session start.
//
// ORD-2 (US-ORD-2-05). Rewritten, not patched. Three of this tool's six
// operation blocks called api.call with an empty path in an empty API group,
// so stage add, stage remove and lens remove reported success and did nothing.
//
// Fixing that call alone would NOT have been enough. Every block was built as
//
//     foreach (ops) { if (op.action == X) { query -> as $t
//                                           if ($t != null) { WRITE } } }
//
// and the inner condition reads a variable written earlier in the SAME
// iteration — the shape CLAUDE.md proves silently discards every write in the
// branch. The renames, which do run real db.edit calls, were sitting in that
// same shape. So each block is now two passes:
//
//   Pass A  resolve each operation to a plain row of facts (its id, its label,
//           whether an optional field was supplied). Only the loop item is
//           ever tested.
//   Pass B  act on that resolved list. Every condition reads a field of the
//           LOOP ITEM, which is the pattern proven to work.
//
// The ~300 lines of per-actor-type role prompts and actor_fields scaffolds
// that used to live in the lens-add block are gone: journey/insert_lens gets
// them from journey/actor_template, the one copy.
tool scaffold_structure {
  instructions = """
      Use this tool at the START of a build session to reshape the entire map structure in one call.
      Instead of calling mutate_structure 6-8 times for individual renames/adds/removes, collect
      ALL structural changes and apply them here.

      Input:
      - journey_map_id: The ID of the journey map
      - stage_operations: JSON array of { action, key?, label, stage_goal?, primary_actor_lens? }
        - action: 'rename' (requires key + label), 'add' (requires label), 'remove' (requires key)
        - stage_goal (rename/add, optional): one-sentence exit condition / definition of done for the stage.
        - primary_actor_lens (rename/add, optional): lens key of the actor accountable for this stage's outcome (e.g. "lens-3").
        - On a rename, an optional field you LEAVE OUT is left alone. It is no longer overwritten or an error.
      - lens_operations: JSON array of { action, key?, label, actor_type? }
        - action: 'rename' (requires key + label), 'add' (requires label), 'remove' (requires key)
        - actor_type (add only, optional): one of customer, internal, engineering, ai_agent, handoff, vendor, financial, metrics. When provided the lens is created with the matching template_key, role_prompt, and cells are pre-scaffolded with actor_fields. An actor type outside that list is refused (and, like any failed step, undoes the whole call), not guessed.

      Operations execute in order: removes first, then renames, then adds.
      This ensures stable keys are preserved during renames and new items don't conflict.

      Adds always append to the end. To place a column or row at a position, use
      mutate_structure with after_stage_key / after_lens_key.

      ALL OR NOTHING. If any key is not in the map, the whole call is refused before
      anything changes and the message names the keys. If any step fails while applying
      (for example a remove that live work depends on), every change in the call is
      undone and the message names the step. Read the map first so you use keys it has.
      errors[] is kept for compatibility and is always empty on success.

      Response shape:
      {
        success: boolean,
        stages_renamed: int, stages_added: int, stages_removed: int,
        lenses_renamed: int, lenses_added: int, lenses_removed: int,
        cells_created: int, cells_deleted: int,
        final_stage_count: int, final_lens_count: int,
        errors: [ { action, key?, label?, error } ]
      }
    """

  input {
    // The ID of the journey map to restructure.
    int journey_map_id filters=min:1

    // Array of stage operations: [{ action, key?, label, stage_goal?, primary_actor_lens? }]
    json stage_operations?

    // Array of lens operations: [{ action, key?, label, actor_type? }]
    json lens_operations?

    // Optional: for tool trace logging (transparency layer).
    int conversation_id?

    text turn_id?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "scaffold_structure", kind: "write"}
    } as $cop1_gate

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    var $stages_renamed {
      value = 0
    }

    var $stages_added {
      value = 0
    }

    var $stages_removed {
      value = 0
    }

    var $lenses_renamed {
      value = 0
    }

    var $lenses_added {
      value = 0
    }

    var $lenses_removed {
      value = 0
    }

    var $cells_created {
      value = 0
    }

    var $cells_deleted {
      value = 0
    }

    var $errors {
      value = []
    }

    // ── ALL-OR-NOTHING (founder decision, 2026-11-14) ─────────────────────────────────
    // "Undo everything: the map is never left half-changed." Two phases:
    //   1. RESOLVE every key first, with no writes. Any key that is not in the map refuses the
    //      whole call (E-COP-014) and names the keys, before anything is touched.
    //   2. APPLY every operation inside ONE db.transaction. If any step fails (a remove that live
    //      work depends on, an unknown actor type, anything) the whole change rolls back and the
    //      call is refused (E-COP-015), naming the step. Proven live first: the helpers' own inner
    //      transactions (journey/remove_stage, remove_lens) roll back with the outer one.
    // errors[] is kept in the response for old callers and is now always empty.
    // Order is unchanged: stage removes, renames, adds; then lens removes, renames, adds.

    // An omitted json input may arrive as "" rather than null, and `!=` is loose, so this catches
    // both; `??` would not catch "".
    var $stage_ops {
      value = []
    }

    conditional {
      if ($input.stage_operations != null) {
        var.update $stage_ops {
          value = $input.stage_operations
        }
      }
    }

    var $lens_ops {
      value = []
    }

    conditional {
      if ($input.lens_operations != null) {
        var.update $lens_ops {
          value = $input.lens_operations
        }
      }
    }

    // ── Phase 1: resolve (read-only) ──
    var $stage_removals {
      value = []
    }

    var $stage_renames {
      value = []
    }

    var $lens_removals {
      value = []
    }

    var $lens_renames {
      value = []
    }

    // Every unresolved key, from all four lists. Each condition reads the loop item only.
    var $missing_count {
      value = 0
    }

    var $missing_keys {
      value = ""
    }

    foreach ($stage_ops) {
      each as $op {
        conditional {
          if ($op.action == "remove") {
            var $op_key_st_rm {
              value = $op|get:"key":""
            }

            db.query journey_stage {
              where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $op_key_st_rm
              return = {type: "single"}
            } as $rm_hit

            array.push $stage_removals {
              value = {key: ($op|get:"key":""), id: ($rm_hit|get:"id":0)}
            }
          }

          elseif ($op.action == "rename") {
            var $op_key_st_rn {
              value = $op|get:"key":""
            }

            db.query journey_stage {
              where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $op_key_st_rn
              return = {type: "single"}
            } as $rn_hit

            // has_goal / has_actor are captured as plain fields so phase 2 can branch on the loop
            // item. An optional field the caller left out is left alone.
            array.push $stage_renames {
              value = {
                key      : ($op|get:"key":"")
                id       : ($rn_hit|get:"id":0)
                label    : ($op|get:"label":"")
                goal     : ($op|get:"stage_goal":"")
                has_goal : ($op|has:"stage_goal")
                actor    : ($op|get:"primary_actor_lens":"")
                has_actor: ($op|has:"primary_actor_lens")
              }
            }
          }
        }
      }
    }

    foreach ($stage_removals) {
      each as $r {
        conditional {
          if ($r.id == 0) {
            var.update $missing_count {
              value = $missing_count + 1
            }

            var.update $missing_keys {
              value = $missing_keys ~ " stage " ~ $r.key ~ " (remove);"
            }
          }
        }
      }
    }

    foreach ($stage_renames) {
      each as $r {
        conditional {
          if ($r.id == 0) {
            var.update $missing_count {
              value = $missing_count + 1
            }

            var.update $missing_keys {
              value = $missing_keys ~ " stage " ~ $r.key ~ " (rename);"
            }
          }
        }
      }
    }

    foreach ($lens_ops) {
      each as $op {
        conditional {
          if ($op.action == "remove") {
            var $op_key_ln_rm {
              value = $op|get:"key":""
            }

            db.query journey_lens {
              where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $op_key_ln_rm
              return = {type: "single"}
            } as $lrm_hit

            array.push $lens_removals {
              value = {key: ($op|get:"key":""), id: ($lrm_hit|get:"id":0)}
            }
          }

          elseif ($op.action == "rename") {
            var $op_key_ln_rn {
              value = $op|get:"key":""
            }

            db.query journey_lens {
              where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $op_key_ln_rn
              return = {type: "single"}
            } as $lrn_hit

            array.push $lens_renames {
              value = {key: ($op|get:"key":""), id: ($lrn_hit|get:"id":0), label: ($op|get:"label":"")}
            }
          }
        }
      }
    }

    foreach ($lens_removals) {
      each as $r {
        conditional {
          if ($r.id == 0) {
            var.update $missing_count {
              value = $missing_count + 1
            }

            var.update $missing_keys {
              value = $missing_keys ~ " lens " ~ $r.key ~ " (remove);"
            }
          }
        }
      }
    }

    foreach ($lens_renames) {
      each as $r {
        conditional {
          if ($r.id == 0) {
            var.update $missing_count {
              value = $missing_count + 1
            }

            var.update $missing_keys {
              value = $missing_keys ~ " lens " ~ $r.key ~ " (rename);"
            }
          }
        }
      }
    }

    var $missing_msg {
      value = "Nothing was changed. These keys are not in this map:" ~ $missing_keys ~ " Read the map first and use the keys it has. (E-COP-014)"
    }

    conditional {
      if ($missing_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-1"
            step       : "scaffold_structure"
            outcome    : "rejected"
            severity   : "info"
            error_code : "E-COP-014"
            message    : "Bulk map change refused before any write: unknown keys."
            user_id    : $cop1_gate.user_id
            account_id : $cop1_gate.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            metadata   : {missing_count: $missing_count}
          }
        } as $_missing_logged
      }
    }

    precondition ($missing_count == 0) {
      error_type = "inputerror"
      error = $missing_msg
    }

    // ── Phase 2: apply, all inside one transaction ──
    var $tx_failed {
      value = false
    }

    var $failed_step {
      value = ""
    }

    try_catch {
      try {
        group {
          stack {
            db.transaction {
              stack {
                foreach ($stage_removals) {
                  each as $rm {
                    var.update $failed_step {
                      value = "remove stage " ~ $rm.key
                    }

                    function.run "journey/remove_stage" {
                      input = {
                        journey_stage_id: $rm.id
                        step            : "ai_scaffold_remove_stage"
                      }
                    } as $rm_result

                    var.update $stages_removed {
                      value = $stages_removed + 1
                    }

                    var.update $cells_deleted {
                      value = $cells_deleted + $rm_result.deleted_cell_count
                    }
                  }
                }

                foreach ($stage_renames) {
                  each as $rn {
                    var.update $failed_step {
                      value = "rename stage " ~ $rn.key
                    }

                    db.patch journey_stage {
                      field_name = "id"
                      field_value = $rn.id
                      data = {label: $rn.label, updated_at: "now"}
                    } as $rn_label_done

                    var.update $stages_renamed {
                      value = $stages_renamed + 1
                    }

                    conditional {
                      if ($rn.has_goal == true) {
                        db.patch journey_stage {
                          field_name = "id"
                          field_value = $rn.id
                          data = {stage_goal: $rn.goal, updated_at: "now"}
                        } as $rn_goal_done
                      }
                    }

                    conditional {
                      if ($rn.has_actor == true) {
                        db.patch journey_stage {
                          field_name = "id"
                          field_value = $rn.id
                          data = {primary_actor_lens: $rn.actor, updated_at: "now"}
                        } as $rn_actor_done
                      }
                    }
                  }
                }

                foreach ($stage_ops) {
                  each as $op {
                    conditional {
                      if ($op.action == "add") {
                        var.update $failed_step {
                          value = "add stage " ~ ($op|get:"label":"")
                        }

                        function.run "journey/insert_stage" {
                          input = {
                            journey_map_id    : $input.journey_map_id
                            after_stage_id    : -1
                            label             : ($op|get:"label":"")
                            stage_goal        : ($op|get:"stage_goal":"")
                            primary_actor_lens: ($op|get:"primary_actor_lens":"")
                            step              : "ai_scaffold_add_stage"
                          }
                        } as $add_stage_result

                        var.update $stages_added {
                          value = $stages_added + 1
                        }

                        var.update $cells_created {
                          value = $cells_created + ($add_stage_result.cells|count)
                        }
                      }
                    }
                  }
                }

                foreach ($lens_removals) {
                  each as $lrm {
                    var.update $failed_step {
                      value = "remove lens " ~ $lrm.key
                    }

                    function.run "journey/remove_lens" {
                      input = {
                        journey_lens_id: $lrm.id
                        step           : "ai_scaffold_remove_lens"
                      }
                    } as $lrm_result

                    var.update $lenses_removed {
                      value = $lenses_removed + 1
                    }

                    var.update $cells_deleted {
                      value = $cells_deleted + $lrm_result.deleted_cell_count
                    }
                  }
                }

                foreach ($lens_renames) {
                  each as $lrn {
                    var.update $failed_step {
                      value = "rename lens " ~ $lrn.key
                    }

                    db.patch journey_lens {
                      field_name = "id"
                      field_value = $lrn.id
                      data = {label: $lrn.label, updated_at: "now"}
                    } as $lrn_done

                    var.update $lenses_renamed {
                      value = $lenses_renamed + 1
                    }
                  }
                }

                foreach ($lens_ops) {
                  each as $op {
                    conditional {
                      if ($op.action == "add") {
                        var.update $failed_step {
                          value = "add lens " ~ ($op|get:"label":"")
                        }

                        function.run "journey/insert_lens" {
                          input = {
                            journey_map_id: $input.journey_map_id
                            after_lens_id : -1
                            label         : ($op|get:"label":"")
                            actor_type    : ($op|get:"actor_type":"")
                            step          : "ai_scaffold_add_lens"
                          }
                        } as $add_lens_result

                        var.update $lenses_added {
                          value = $lenses_added + 1
                        }

                        var.update $cells_created {
                          value = $cells_created + ($add_lens_result.cells|count)
                        }
                      }
                    }
                  }
                }

                var.update $failed_step {
                  value = "save the map"
                }

                db.patch journey_map {
                  field_name = "id"
                  field_value = $input.journey_map_id
                  data = {updated_at: "now", last_interaction_at: "now"}
                } as $map_touch
              }
            }
          }
        }
      }

      catch {
        var.update $tx_failed {
          value = true
        }
      }
    }

    var $failed_msg {
      value = "Nothing was changed: the step to " ~ $failed_step ~ " could not be applied, so the whole change was undone. Check that step (a remove is refused while live work depends on it) and try again. (E-COP-015)"
    }

    conditional {
      if ($tx_failed == true) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-1"
            step       : "scaffold_structure"
            outcome    : "failure"
            severity   : "warn"
            error_code : "E-COP-015"
            message    : "Bulk map change rolled back; nothing was saved."
            user_id    : $cop1_gate.user_id
            account_id : $cop1_gate.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            metadata   : {failed_step: $failed_step}
          }
        } as $_failed_logged
      }
    }

    precondition ($tx_failed == false) {
      error_type = "inputerror"
      error = $failed_msg
    }

    // ── Final counts ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $final_stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $final_lenses

    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          enforce_hidden_fields = false
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "scaffold_structure"
            tool_category : "structure"
            input_summary : $stages_renamed ~ " renamed, " ~ $stages_added ~ " added, " ~ $stages_removed ~ " removed stages"
            output_summary: ($final_stages|count) ~ " stages, " ~ ($final_lenses|count) ~ " lenses final"
          }
        } as $tool_log
      }
    }
  }

  response = {
    success          : true
    stages_renamed   : $stages_renamed
    stages_added     : $stages_added
    stages_removed   : $stages_removed
    lenses_renamed   : $lenses_renamed
    lenses_added     : $lenses_added
    lenses_removed   : $lenses_removed
    cells_created    : $cells_created
    cells_deleted    : $cells_deleted
    final_stage_count: $final_stages|count
    final_lens_count : $final_lenses|count
    stages           : $final_stages
    lenses           : $final_lenses
    errors           : $errors
  }

  guid = "DAqeKjJsXv8qump_B7THhNN1qoQ"
}
