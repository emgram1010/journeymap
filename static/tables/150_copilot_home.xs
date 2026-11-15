// COP-3 story 01 (2026-11-15) — the copilot's own "how I work" business: one journey architecture
// per account that holds the copilot's working methods as maps (how to research, how to build maps,
// how to learn, how to ask for approval). Decision D-2: one copy per account, never shared across
// accounts. A side table, not a column on journey_architecture (text validators — CLAUDE.md).
// Unique account_id (one home per account) and unique journey_architecture_id.
//
// GOV-1: S1 primary key; S2 created_at only (written once); S3 references declared and indexed;
// S6 unique natural keys.
table copilot_home {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The architecture that is the copilot's own home."
    }

    int created_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
  ]
}
