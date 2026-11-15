// COP-1 story 01 (2026-11-15) — marks a user row as an AI identity (the account's copilot).
// The copilot is a real `user` in the account so grants, switch-off and the audit trail apply to
// it with no second copy of any rule; this side table says which user it is and holds what only
// an AI has (its daily cap). No column is added to `user` (its text validators — CLAUDE.md).
//
// One copilot per account: `account_id` is unique, so a second create fails at the database,
// not at a pre-check that two parallel requests could both pass. `user_id` is unique too.
// Never deleted while the copilot exists; switch the user off instead.
//
// GOV-1: S1 primary key; S2 created_at + updated_at (the cap can change); S3 references declared
// and indexed; S6 unique natural keys.
table ai_identity {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int user_id? {
      table = "user"
      description = "The user row that IS the copilot."
    }

    int account_id? {
      table = "account"
      description = "The account it works for. Unique: one copilot per account."
    }

    text name? filters=trim {
      description = "Display name, e.g. Copilot."
    }

    int daily_cap?=500 {
      description = "Most AI tool calls it may make per UTC day. At the cap the gate refuses (E-COP-004)."
    }

    int created_by_user_id? {
      table = "user"
      description = "The account admin who created it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "user_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
  ]
}
