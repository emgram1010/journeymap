// SCN-MCP-2: MCP tool — deep-clone a journey map into a new scenario within the same architecture.
// Maps to POST /journey_architecture/{id}/scenarios/clone
// Clone order: journey_map → journey_stage → journey_lens → journey_cell
//              → journey_stage_owner → journey_lens_planned_work
// journey_link and agent_conversation records are intentionally NOT cloned.
//
// FIXED 2026-10-14 (stabilisation pass). Two problems, both found because
// CLAUDE.md requires testing migrations on a CLONE of map 178 and this tool
// was the only way to make one:
//
//  1. It crashed with "Unable to locate var: cell.stage_key". The cell loop
//     matched `$cell.stage_key` / `$cell.lens_key` against the new map's
//     keys, but a journey_cell row has no such columns — it has `stage` and
//     `lens`, which are integer ids. The remap now goes id → key (in the
//     SOURCE map) → id (in the NEW map), which is what was intended.
//
//  2. Worse than the crash, because it was silent: the clone dropped every
//     field added since this tool was written — cell durations (TIME-1),
//     stage ownership and the planned-work switch (STAGE-1), lens cost
//     rates, and the stage's primary_actor_lens. A clone missing those
//     reads as "no owner, no duration" and would have made PUB-1's gate and
//     AUTH-1's readiness look broken on a clone when they were fine. A
//     faithful clone matters more here than a fast one.
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
      enforce_hidden_fields = false
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
          enforce_hidden_fields = false
          data = {
            created_at        : "now"
            updated_at        : "now"
            journey_map       : $new_map.id
            key               : $stage.key
            label             : $stage.label
            display_order     : $stage.display_order
            stage_goal        : $stage.stage_goal
            primary_actor_lens: $stage.primary_actor_lens
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
          enforce_hidden_fields = false
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
            cost_rate_value     : $lens.cost_rate_value
            cost_rate_unit      : $lens.cost_rate_unit
          }
        } as $_l
      }
    }

    // 4 — Build the id↔key lookups the remap needs.
    // Keys are stable across a clone (they are copied verbatim above), which
    // is what makes them the safe join between the two maps' id spaces.
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $new_map.id
      return = {type: "list"}
    } as $new_stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $new_map.id
      return = {type: "list"}
    } as $new_lenses

    var $source_stage_key_by_id {
      value = {}
    }

    foreach ($source_stages) {
      each as $ss {
        var $ss_id_text {
          value = $ss.id|to_text
        }

        var.update $source_stage_key_by_id {
          value = $source_stage_key_by_id|set:$ss_id_text:$ss.key
        }
      }
    }

    var $source_lens_key_by_id {
      value = {}
    }

    foreach ($source_lenses) {
      each as $sl {
        var $sl_id_text {
          value = $sl.id|to_text
        }

        var.update $source_lens_key_by_id {
          value = $source_lens_key_by_id|set:$sl_id_text:$sl.key
        }
      }
    }

    var $new_stage_id_by_key {
      value = {}
    }

    foreach ($new_stages) {
      each as $ns {
        var $ns_key {
          value = $ns.key
        }

        var.update $new_stage_id_by_key {
          value = $new_stage_id_by_key|set:$ns_key:$ns.id
        }
      }
    }

    var $new_lens_id_by_key {
      value = {}
    }

    foreach ($new_lenses) {
      each as $nl {
        var $nl_key {
          value = $nl.key
        }

        var.update $new_lens_id_by_key {
          value = $new_lens_id_by_key|set:$nl_key:$nl.id
        }
      }
    }

    // 5 — Clone cells, remapping stage/lens ids through their keys
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.source_map_id
      return = {type: "list"}
    } as $source_cells

    foreach ($source_cells) {
      each as $cell {
        var $cell_stage_id_text {
          value = $cell.stage|to_text
        }

        var $cell_lens_id_text {
          value = $cell.lens|to_text
        }

        var $cell_stage_key {
          value = $source_stage_key_by_id|get:$cell_stage_id_text:null
        }

        var $cell_lens_key {
          value = $source_lens_key_by_id|get:$cell_lens_id_text:null
        }

        var $matched_stage_id {
          value = null
        }

        var $matched_lens_id {
          value = null
        }

        conditional {
          if ($cell_stage_key != null) {
            var.update $matched_stage_id {
              value = $new_stage_id_by_key|get:$cell_stage_key:null
            }
          }
        }

        conditional {
          if ($cell_lens_key != null) {
            var.update $matched_lens_id {
              value = $new_lens_id_by_key|get:$cell_lens_key:null
            }
          }
        }

        conditional {
          if ($matched_stage_id != null && $matched_lens_id != null) {
            db.add journey_cell {
              enforce_hidden_fields = false
              data = {
                created_at         : "now"
                updated_at         : "now"
                journey_map        : $new_map.id
                stage              : $matched_stage_id
                lens               : $matched_lens_id
                content            : $cell.content
                status             : $cell.status
                is_locked          : false
                actor_fields       : $cell.actor_fields
                time_duration_value: $cell.time_duration_value
                time_duration_unit : $cell.time_duration_unit
                planned_duration   : $cell.planned_duration
                actual_duration    : $cell.actual_duration
              }
            } as $_c
          }
        }
      }
    }

    // 6 — Clone stage ownership (STAGE-1). journey_stage_owner has no
    // journey_map column, so it is read whole and matched by stage id.
    db.query journey_stage_owner {
      return = {type: "list"}
    } as $all_owner_rows

    foreach ($source_stages) {
      each as $owned_stage {
        var $owner_lens_id {
          value = null
        }

        foreach ($all_owner_rows) {
          each as $owner_row {
            conditional {
              if ($owner_row.journey_stage == $owned_stage.id) {
                var.update $owner_lens_id {
                  value = $owner_row.owner_lens_id
                }
              }
            }
          }
        }

        conditional {
          if ($owner_lens_id != null) {
            var $owner_lens_id_text {
              value = $owner_lens_id|to_text
            }

            var $owner_key {
              value = $source_lens_key_by_id|get:$owner_lens_id_text:null
            }

            var $owned_stage_key {
              value = $owned_stage.key
            }

            var $new_owned_stage_id {
              value = $new_stage_id_by_key|get:$owned_stage_key:null
            }

            var $new_owner_lens_id {
              value = null
            }

            conditional {
              if ($owner_key != null) {
                var.update $new_owner_lens_id {
                  value = $new_lens_id_by_key|get:$owner_key:null
                }
              }
            }

            conditional {
              if ($new_owned_stage_id != null && $new_owner_lens_id != null) {
                db.add journey_stage_owner {
                  enforce_hidden_fields = false
                  data = {
                    created_at   : "now"
                    updated_at   : "now"
                    journey_stage: $new_owned_stage_id
                    owner_lens_id: $new_owner_lens_id
                  }
                } as $_o
              }
            }
          }
        }
      }
    }

    // 7 — Clone explicit does_planned_work overrides (STAGE-1). Only rows
    // that exist are copied: a missing row means "use the actor_type
    // default", which the clone inherits for free.
    db.query journey_lens_planned_work {
      return = {type: "list"}
    } as $all_planned_work_rows

    foreach ($source_lenses) {
      each as $pw_lens {
        var $has_override {
          value = false
        }

        var $override_value {
          value = false
        }

        foreach ($all_planned_work_rows) {
          each as $pw_row {
            conditional {
              if ($pw_row.journey_lens == $pw_lens.id) {
                var.update $has_override {
                  value = true
                }

                var.update $override_value {
                  value = $pw_row.does_planned_work
                }
              }
            }
          }
        }

        conditional {
          if ($has_override == true) {
            var $pw_lens_key {
              value = $pw_lens.key
            }

            var $new_pw_lens_id {
              value = $new_lens_id_by_key|get:$pw_lens_key:null
            }

            conditional {
              if ($new_pw_lens_id != null) {
                db.add journey_lens_planned_work {
                  enforce_hidden_fields = false
                  data = {
                    created_at       : "now"
                    updated_at       : "now"
                    journey_lens     : $new_pw_lens_id
                    does_planned_work: $override_value
                  }
                } as $_pw
              }
            }
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
