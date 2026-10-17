// STAGE-1 (US-STAGE-1-06) — Set or clear the "does this row do planned
// work?" switch for one lens. A dedicated endpoint, not the generic
// dblink PATCH (33), because does_planned_work is not a journey_lens
// column — it lives in journey_lens_planned_work (see that table's
// header for why) — same convention as journey_lens/rename (46) and
// journey_lens/actor_fields (63).
//
// does_planned_work: true|false sets an explicit override. Passing
// clear: true removes the override so the row falls back to its
// actor_type default (internal/ai_agent = yes, everything else = no).
query "journey_lens/planned_work/{journey_lens_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_lens_id? filters=min:1
    bool does_planned_work?
    bool clear?
  }

  stack {
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $existing_lens

    precondition ($existing_lens != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }

    function.run "set_lens_planned_work" {
      input = {
        journey_lens_id   : $input.journey_lens_id
        does_planned_work : $input.does_planned_work
        clear             : $input.clear
      }
    } as $write_result

    function.run "does_planned_work" {
      input = {
        journey_lens_id: $input.journey_lens_id
        actor_type     : $existing_lens.actor_type
      }
    } as $resolved
  }

  response = {
    journey_lens_id : $input.journey_lens_id
    does_planned_work: $resolved.does_planned_work
  }
}
