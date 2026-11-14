// COP-1 (2026-11-14) — a run ticket: proof of who an in-app agent is working for.
// A tool run by an agent inside Emgram is told nothing about the signed-in person (proven
// live). So the endpoint that starts the agent writes one row here and hands the agent the
// random `ticket` to pass to every tool; the tool looks it up (usr/tool_caller). The model
// cannot forge one, and a ticket only grants what its own user may reach.
// Short-lived. Rows are not history: expired ones may be cleared.
table tool_run_ticket {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    text ticket? filters=trim {
      description = "Random id (uuid). Unique. Never logged."
    }

    int user_id? {
      table = "user"
      description = "The signed-in person the agent is working for."
    }

    int account_id? {
      description = "That person's account when the ticket was made."
    }

    int journey_map_id? {
      description = "The map this turn is about. 0 = not tied to one map."
    }

    int journey_architecture_id? {
      description = "The business (architecture) this turn is pinned to. 0 = not pinned."
    }

    timestamp expires_at? {
      description = "Epoch ms. After this the ticket is refused."
    }

    text source? filters=trim {
      description = "Which endpoint made it, e.g. 'ai_message'."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "ticket", op: "asc"}]}
    {type: "btree", field: [{name: "user_id", op: "asc"}]}
    {type: "btree", field: [{name: "expires_at", op: "asc"}]}
  ]
}
