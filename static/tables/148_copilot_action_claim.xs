// COP-2 story 02 (2026-11-15) — the race guard for copilot_action. Deciding an action and
// running an approved one each insert ONE row here; the unique index on
// (copilot_action_id, kind) makes a second insert fail at the database. A transaction does NOT
// serialize two overlapping requests in this engine (CLAUDE.md, endpoint 610); a unique index does.
//
// kind "decide": the first Approve / Edit / Reject wins; a double click gets E-COP-021.
// kind "execute": an approved action runs once; a second re-call gets E-COP-021.
//
// Append-only history (src/ops/historyTables.ts).
//
// GOV-1: S1 primary key; S2 created_at only; S3 references declared and indexed; S6 unique key.
table copilot_action_claim {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int copilot_action_id? {
      table = "copilot_action"
    }

    enum kind? {
      values = ["decide", "execute"]
    }

    int user_id? {
      table = "user"
      description = "Who claimed it: the deciding person, or the AI identity running it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "copilot_action_id", op: "asc"}, {name: "kind", op: "asc"}]}
    {type: "btree", field: [{name: "user_id", op: "asc"}]}
  ]
}
