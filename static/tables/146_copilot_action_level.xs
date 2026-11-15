// COP-2 story 01 (2026-11-15) — the owner's chosen approval level for one action type in one
// business (journey architecture). Absence of a row means the type's default (decision D-8),
// which lives in copilot/action_types — the ONE catalogue. journey_architecture_id 0 = maps that
// are not in any business; those follow the defaults like a business with no rows.
//
// Written only by POST copilot/level_set, which requires a signed-in person (never an AI
// identity) and refuses locked types. Unique (journey_architecture_id, action_type): one level
// per type per business, enforced by the database.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key. Rows are edited in place (the level history is in event_log).
table copilot_action_level {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int account_id? {
      table = "account"
      description = "The account the business belongs to."
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business. 0 = maps outside any business."
    }

    text action_type? filters=trim {
      description = "A key from copilot/action_types, e.g. customer_message."
    }

    enum level? {
      values = ["own", "tell", "wait"]
      description = "own = runs on its own; tell = runs, then tells you; wait = waits for you."
    }

    int limit_amount? {
      description = "For money types: under this amount it runs at 'tell' instead of waiting. 0 = always wait."
    }

    int updated_by_user_id? {
      table = "user"
      description = "The person who last set it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_architecture_id", op: "asc"}, {name: "action_type", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
