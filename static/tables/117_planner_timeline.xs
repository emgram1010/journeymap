// PLN-1 (US-PLN-1-04) — One agent's plan for one day.
//
// Deliberately has NO `assignee` and NO `name` column: both are derived
// (the agent's name, and the date) rather than stored, which is the
// normalization this epic exists to apply.
table planner_timeline {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int workspace_id? {
      table = "planner_workspace"
    }

    int agent_id? {
      table = "planner_agent"
      description = "One timeline per agent per day — see the unique index."
    }

    date planned_date?

    text start_time? filters=trim {
      description = "HH:MM, 24-hour. The API defaults it to 08:00 and validates the format (PLN-6)."
    }

    // KNOWN DEVIATION: US-PLN-1-04 asks for default "draft", and this
    // column has no default — see the same note in 118_planner_task.xs.
    // PLN-6 always writes "draft" explicitly on create.
    enum status? {
      values = ["draft", "published"]
      description = "RESERVED. PLN-6 keeps this read-only; only LIVE-1's publish endpoint moves it to published. P3A-1: a published timeline cannot be deleted."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "agent_id", op: "asc"}, {name: "planned_date", op: "asc"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}, {name: "planned_date", op: "asc"}]}
  ]
}
