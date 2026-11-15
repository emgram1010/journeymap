// COP-4 story 06 (2026-11-15) — short facts and preferences the copilot was told about one
// business ("we never book on Sundays"). Shown to the owner in "What the copilot knows", who can
// edit or remove them (removal is logged). Read into every copilot chat for THAT business only;
// a note from business A is never used in business B. Never holds secrets or logins.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed.
table copilot_note {
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
    }

    text note? filters=trim

    int created_by_user_id? {
      table = "user"
      description = "The copilot or the person who wrote it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
  ]
}
