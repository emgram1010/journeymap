// THE ONE PLACE A ROW IS ADDED TO A MAP. Appends or inserts at a position,
// scaffolds one cell per existing column, and hands the final order to
// journey/apply_lens_order.
//
// ORD-2 US-ORD-2-02. Lifted out of endpoint 49 (journey_lens/add) so the
// matrix buttons and the AI tools run the same code. The AI's add_lens already
// worked, but it carried its own copy of the actor templates and that copy had
// no financial or metrics case at all.
//
// AUTHORISATION IS THE CALLER'S JOB — see journey/insert_stage. Endpoint 49
// keeps its ownership precondition and runs it before calling this.
//
// after_lens_id IS REQUIRED, and -1 means append, for the same reason as
// insert_stage: an omitted optional int is 0, and 0 legitimately means "insert
// first", so only the caller can tell them apart (CLAUDE.md).
function "journey/insert_lens" {
  input {
    int journey_map_id filters=min:1

    // -1 = append to the end. 0 = insert first. An id = insert after that row.
    int after_lens_id

    text label? filters=trim

    // One of: customer, internal, engineering, ai_agent, handoff, vendor,
    // financial, metrics. Empty creates a plain row with no template.
    // Validated by journey/actor_template, which refuses anything else.
    text actor_type? filters=trim|lower

    // Explicit overrides. Empty means "use the actor type's own template".
    text template_key? filters=trim
    text role_prompt? filters=trim

    text persona_description? filters=trim
    text primary_goal? filters=trim
    text standing_constraints? filters=trim
    int agent_map_id?

    // Logging only.
    int user_id?
    int account_id?
    text step? filters=trim
  }

  stack {
    var $cells {
      value = []
    }

    var $log_step {
      value = "insert_lens"
    }

    conditional {
      if ($input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_stages

    precondition (($existing_stages|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one stage before adding a lens"
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.id == $input.after_lens_id
      return = {type: "count"}
    } as $anchor_found

    var $anchor_bad {
      value = ($input.after_lens_id > 0) && ($anchor_found == 0)
    }

    conditional {
      if ($anchor_bad) {
        function.run "ops/log_event" {
          input = {
            feature    : "ORD-2"
            step       : $log_step
            outcome    : "rejected"
            severity   : "info"
            user_id    : $input.user_id
            account_id : $journey_map.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            error_code : "E-ORD-002"
            message    : "Insert refused: the lens to insert after is not in this map."
          }
        } as $_anchor_logged
      }
    }

    precondition ($anchor_bad == false) {
      error_type = "inputerror"
      error = "The row you tried to insert next to isn't in this map any more, so nothing was added. Refresh and try again. (E-ORD-002)"
    }

    // The one copy of the actor templates. Refuses an actor type it does not
    // know (E-ORD-004) rather than quietly creating a row with no fields,
    // which is what the AI's own copy used to do for financial and metrics.
    function.run "journey/actor_template" {
      input = {
        actor_type: $input.actor_type
      }
    } as $tpl

    var $effective_template_key {
      value = $tpl.template_key
    }

    conditional {
      if ($input.template_key != "") {
        var.update $effective_template_key {
          value = $input.template_key
        }
      }
    }

    var $effective_role_prompt {
      value = $tpl.role_prompt
    }

    conditional {
      if ($input.role_prompt != "") {
        var.update $effective_role_prompt {
          value = $input.role_prompt
        }
      }
    }

    function.run "journey/next_lens_key" {
      input = {journey_map_id: $input.journey_map_id}
    } as $mint

    var $next_lens_order {
      value = $mint.display_order
    }

    var $lens_label {
      value = "New Lens %d"|sprintf:$next_lens_order
    }

    conditional {
      if ($input.label != "") {
        var.update $lens_label {
          value = $input.label
        }
      }
    }

    db.add journey_lens {
      enforce_hidden_fields = false
      data = {
        created_at          : "now"
        updated_at          : "now"
        journey_map         : $input.journey_map_id
        key                 : $mint.key
        label               : $lens_label
        display_order       : $next_lens_order
        actor_type          : $input.actor_type
        template_key        : $effective_template_key
        role_prompt         : $effective_role_prompt
        persona_description : $input.persona_description
        primary_goal        : $input.primary_goal
        standing_constraints: $input.standing_constraints
        agent_map_id        : $input.agent_map_id
      }
    } as $journey_lens

    foreach ($existing_stages) {
      each as $stage {
        db.add journey_cell {
          enforce_hidden_fields = false
          data = {
            created_at  : "now"
            updated_at  : "now"
            journey_map : $input.journey_map_id
            stage       : $stage.id
            lens        : $journey_lens.id
            content     : ""
            status      : "open"
            is_locked   : false
            actor_fields: $tpl.actor_fields
          }
        } as $cell

        array.push $cells {
          value = $cell
        }
      }
    }

    var $placed_count {
      value = 0
    }

    conditional {
      if ($input.after_lens_id >= 0) {
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id
          sort = {display_order: "asc", id: "asc"}
          return = {type: "list"}
        } as $ordered_rows

        var $placed_ids {
          value = []
        }

        conditional {
          if ($input.after_lens_id == 0) {
            array.push $placed_ids {
              value = $journey_lens.id
            }
          }
        }

        foreach ($ordered_rows) {
          each as $or {
            conditional {
              if ($or.id != $journey_lens.id) {
                array.push $placed_ids {
                  value = $or.id
                }

                conditional {
                  if ($or.id == $input.after_lens_id) {
                    array.push $placed_ids {
                      value = $journey_lens.id
                    }
                  }
                }
              }
            }
          }
        }

        function.run "journey/apply_lens_order" {
          input = {
            journey_map_id: $input.journey_map_id
            lens_ids      : $placed_ids
            user_id       : $input.user_id
            account_id    : $journey_map.account_id
            step          : $log_step
          }
        } as $placed

        var.update $placed_count {
          value = $placed.count
        }
      }
    }

    db.get journey_lens {
      field_name = "id"
      field_value = $journey_lens.id
    } as $placed_row

    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch
  }

  response = {
    lens                  : $placed_row
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
    reordered_count       : $placed_count
  }
}
