// Add a journey lens and scaffold matching cells for all stages in the map.
//
// ORD-2 (US-ORD-2-04): the work moved to journey/insert_lens, and the ~250
// lines of per-actor-type role prompts and field scaffolds that used to live
// here moved to journey/actor_template. This endpoint's copy was the most
// complete of the four, so it is the one the shared function reproduces.
//
// What stays here is what a function cannot do: prove the caller owns the map,
// and decide whether an insert position was actually SENT (an omitted optional
// int is 0, which is also "insert first", so presence comes from the raw body
// — CLAUDE.md). The function receives an explicit -1, 0 or an id.
query "journey_lens/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim

    enum actor_type? {
      values = ["customer", "internal", "engineering", "ai_agent", "handoff", "vendor", "financial", "metrics"]
    }

    text template_key? filters=trim
    text role_prompt? filters=trim
    text persona_description? filters=trim
    text primary_goal? filters=trim
    text standing_constraints? filters=trim

    int agent_map_id?

    // ORD-1: insert after this lens id; 0 = insert first; omit = append.
    int after_lens_id?
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

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $after_lens_id {
      value = -1
    }

    conditional {
      if ($raw_input|has:"after_lens_id") {
        var.update $after_lens_id {
          value = ($raw_input|get:"after_lens_id":0)|to_int
        }
      }
    }

    function.run "journey/insert_lens" {
      input = {
        journey_map_id      : $input.journey_map_id
        after_lens_id       : $after_lens_id
        label               : $input.label
        actor_type          : $input.actor_type
        template_key        : $input.template_key
        role_prompt         : $input.role_prompt
        persona_description : $input.persona_description
        primary_goal        : $input.primary_goal
        standing_constraints: $input.standing_constraints
        agent_map_id        : $input.agent_map_id
        user_id             : $auth.id
        account_id          : $journey_map.account_id
        step                : "insert_lens"
      }
    } as $added
  }

  response = {
    lens                  : $added.lens
    cells                 : $added.cells
    journey_map_updated_at: $added.journey_map_updated_at
  }
}
