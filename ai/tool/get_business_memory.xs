// COP-4 stories 01/04/06 — everything the copilot has been told or has recorded about THIS
// business: its goals, its notes, and the labels of its maps. Read-only.
tool get_business_memory {
  instructions = "Read what you know about this business: its goals (and whether the owner confirmed them), the notes you saved, and how each map is labelled (insight/runnable, researched/tested, sources). Call this at the start of a conversation and before planning."

  input {
    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "get_business_memory", kind: "read"}
    } as $cop1_gate

    // COP-4: these tools work inside ONE business — the conversation's pinned business.
    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    db.query copilot_goal {
      where = $db.copilot_goal.journey_architecture_id == $pin && $db.copilot_goal.account_id == $cop1_gate.account_id
      sort = {created_at: "desc"}
      return = {type: "list"}
      output = ["id", "goal_text", "target", "target_date", "status"]
    } as $goals

    db.query copilot_note {
      where = $db.copilot_note.journey_architecture_id == $pin && $db.copilot_note.account_id == $cop1_gate.account_id
      sort = {created_at: "asc"}
      return = {type: "list"}
      output = ["id", "note"]
    } as $notes

    db.query copilot_map_profile {
      where = $db.copilot_map_profile.journey_architecture_id == $pin && $db.copilot_map_profile.account_id == $cop1_gate.account_id
      return = {type: "list"}
      output = ["journey_map_id", "kind", "made_by", "tested_since", "research_note"]
    } as $profiles
  }

  response = {journey_architecture_id: $pin, goals: $goals, notes: $notes, map_labels: $profiles}
}
