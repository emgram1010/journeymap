// IL-00-03: MCP tool — scaffold a journey map's structure.
// Delegates to the existing scaffold_structure tool.
// Maps to existing AI tool scaffold_structure.
tool scaffold_map {
  instructions = "Apply a structural blueprint to a journey map in one call. Pass journey_map_id, stage_operations (array of {action, key?, label, stage_goal?, primary_actor_lens?, position?}), and lens_operations (array of {action, key?, label, actor_type?}). Actions: 'rename', 'add', 'remove'. For rename, stage_goal (exit condition one-liner) and primary_actor_lens (lens key that owns the stage, e.g. lens-3) are optional extras. Returns counts of stages/lenses added/renamed/removed and cells created."

  input {
    int journey_map_id filters=min:1
    json stage_operations?
    json lens_operations?
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

    var $stages_added {
      value = 0
    }

    var $stages_removed {
      value = 0
    }

    var $stages_renamed {
      value = 0
    }

    var $lenses_added {
      value = 0
    }

    var $lenses_removed {
      value = 0
    }

    var $lenses_renamed {
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

    // Process stage operations — remove pass first, then rename, then add
    conditional {
      if ($input.stage_operations != null) {

        // Pass 1: remove
        foreach ($input.stage_operations) {
          each as $op {
            conditional {
              if ($op.action == "remove") {
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $op.key
                  return = {type: "single"}
                } as $target_stage

                conditional {
                  if ($target_stage != null) {
                    db.query journey_cell {
                      where = $db.journey_cell.stage == $target_stage.id
                      return = {type: "list"}
                    } as $cells_to_delete

                    foreach ($cells_to_delete) {
                      each as $c {
                        db.del journey_cell {
                          field_name = "id"
                          field_value = $c.id
                        }

                        var.update $cells_deleted {
                          value = $cells_deleted + 1
                        }
                      }
                    }

                    db.del journey_stage {
                      field_name = "id"
                      field_value = $target_stage.id
                    }

                    var.update $stages_removed {
                      value = $stages_removed + 1
                    }
                  }
                }
              }
            }
          }
        }

        // Pass 2: rename
        foreach ($input.stage_operations) {
          each as $op {
            conditional {
              if ($op.action == "rename") {
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $op.key
                  return = {type: "single"}
                } as $rename_stage

                conditional {
                  if ($rename_stage != null) {
                    db.patch journey_stage {
                      field_name = "id"
                      field_value = $rename_stage.id
                      data = {label: $op.label, stage_goal: $op.stage_goal, primary_actor_lens: $op.primary_actor_lens, updated_at: "now"}
                    } as $updated_stage

                    var.update $stages_renamed {
                      value = $stages_renamed + 1
                    }
                  }

                  else {
                    array.push $errors {
                      value = {action: "rename_stage", key: $op.key, error: "Stage not found"}
                    }
                  }
                }
              }
            }
          }
        }

        // Pass 3: add
        foreach ($input.stage_operations) {
          each as $op {
            conditional {
              if ($op.action == "add") {
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id
                  sort = {display_order: "desc"}
                  return = {type: "list"}
                } as $existing_stages

                var $new_order {
                  value = ($existing_stages|count) + 1
                }

                db.add journey_stage {
                  data = {
                    created_at   : "now"
                    updated_at   : "now"
                    journey_map  : $input.journey_map_id
                    key          : "s" ~ ($new_order|to_text)
                    label        : $op.label
                    display_order: $new_order
                  }
                } as $new_stage

                var.update $stages_added {
                  value = $stages_added + 1
                }
              }
            }
          }
        }
      }
    }

    // Process lens operations — remove pass first, then rename, then add
    conditional {
      if ($input.lens_operations != null) {

        // Pass 1: remove
        foreach ($input.lens_operations) {
          each as $op {
            conditional {
              if ($op.action == "remove") {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $op.key
                  return = {type: "single"}
                } as $target_lens

                conditional {
                  if ($target_lens != null) {
                    db.query journey_cell {
                      where = $db.journey_cell.lens == $target_lens.id
                      return = {type: "list"}
                    } as $lens_cells

                    foreach ($lens_cells) {
                      each as $lc {
                        db.del journey_cell {
                          field_name = "id"
                          field_value = $lc.id
                        }

                        var.update $cells_deleted {
                          value = $cells_deleted + 1
                        }
                      }
                    }

                    db.del journey_lens {
                      field_name = "id"
                      field_value = $target_lens.id
                    }

                    var.update $lenses_removed {
                      value = $lenses_removed + 1
                    }
                  }
                }
              }
            }
          }
        }

        // Pass 2: rename
        foreach ($input.lens_operations) {
          each as $op {
            conditional {
              if ($op.action == "rename") {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $op.key
                  return = {type: "single"}
                } as $rename_lens

                conditional {
                  if ($rename_lens != null) {
                    db.patch journey_lens {
                      field_name = "id"
                      field_value = $rename_lens.id
                      data = {label: $op.label, updated_at: "now"}
                    } as $updated_lens

                    var.update $lenses_renamed {
                      value = $lenses_renamed + 1
                    }
                  }

                  else {
                    array.push $errors {
                      value = {action: "rename_lens", key: $op.key, error: "Lens not found"}
                    }
                  }
                }
              }
            }
          }
        }

        // Pass 3: add
        foreach ($input.lens_operations) {
          each as $op {
            conditional {
              if ($op.action == "add") {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $input.journey_map_id
                  sort = {display_order: "desc"}
                  return = {type: "list"}
                } as $existing_lenses

                var $new_lens_order {
                  value = ($existing_lenses|count) + 1
                }

                db.add journey_lens {
                  data = {
                    created_at   : "now"
                    updated_at   : "now"
                    journey_map  : $input.journey_map_id
                    key          : "lens-" ~ ($new_lens_order|to_text)
                    label        : $op.label
                    display_order: $new_lens_order
                    actor_type   : $op.actor_type
                  }
                } as $new_lens

                // Create cells for new lens across all existing stages
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id
                  return = {type: "list"}
                } as $all_stages_for_lens

                foreach ($all_stages_for_lens) {
                  each as $stg {
                    db.add journey_cell {
                      data = {
                        created_at : "now"
                        updated_at : "now"
                        journey_map: $input.journey_map_id
                        stage      : $stg.id
                        lens       : $new_lens.id
                        content    : ""
                        status     : "open"
                        is_locked  : false
                      }
                    } as $new_cell

                    var.update $cells_created {
                      value = $cells_created + 1
                    }
                  }
                }

                var.update $lenses_added {
                  value = $lenses_added + 1
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    success        : true
    stages_added   : $stages_added
    stages_removed : $stages_removed
    stages_renamed : $stages_renamed
    lenses_added   : $lenses_added
    lenses_removed : $lenses_removed
    lenses_renamed : $lenses_renamed
    cells_created  : $cells_created
    cells_deleted  : $cells_deleted
    errors         : $errors
  }
  guid = "IL00ScaffoldMapTool000000001"
}