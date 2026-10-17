// STAGE-1 (US-STAGE-1-06) — Whether a lens does planned work. An
// explicit journey_lens_planned_work row always wins; otherwise the
// default comes from actor_type: yes for internal/ai_agent, no for
// everything else (customer, vendor, financial, etc.).
function "does_planned_work" {
  description = "Resolves the does_planned_work switch for one lens, explicit override first, then the actor_type default."

  input {
    int journey_lens_id filters=min:1
    text actor_type? filters=trim
  }

  stack {
    var $result {
      value = ($input.actor_type == "internal" || $input.actor_type == "ai_agent")
    }

    db.query journey_lens_planned_work {
      where = $db.journey_lens_planned_work.journey_lens == $input.journey_lens_id
      return = {type: "list"}
    } as $overrides

    foreach ($overrides) {
      each as $row {
        var.update $result {
          value = $row.does_planned_work
        }
      }
    }
  }

  response = {does_planned_work: $result}
}
