// COP-4 story 01 (2026-11-15) — a goal the owner gave the copilot for one business ("grow to X
// by Y"). Recorded by the copilot as "proposed" (it repeats the goal back); only the owner confirms
// it, or marks it done or dropped. Scoped by business; never shared across businesses.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed.
table copilot_goal {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int account_id? {
      table = "account"
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business the goal is for."
    }

    text goal_text? filters=trim {
      description = "The goal in one line, as the copilot repeated it back."
    }

    text target? filters=trim {
      description = "The number or outcome, as stated (free text, never invented)."
    }

    text target_date? filters=trim {
      description = "The date or horizon, as stated (free text)."
    }

    enum status? {
      values = ["proposed", "confirmed", "done", "dropped"]
    }

    int created_by_user_id? {
      table = "user"
      description = "Who recorded it (the copilot, or a person)."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
  ]
}
