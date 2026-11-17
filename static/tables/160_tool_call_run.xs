// COP-8 story 03 (2026-11-16, R15) — ties one AI tool call (a tool_call_log row) to the scheduled
// copilot run it was made in, and the business the run was pinned to. Written by journey/tool_gate
// right after the audit row, only for a call whose ticket is in copilot_run_ticket. A side table,
// not a column on tool_call_log (text validators — CLAUDE.md). A failure to write it never blocks
// or changes the call; the gate logs E-COP-076 instead. Holds ids only — never a ticket or input.
// Unique tool_call_log_id: an audit row can be linked once. A run's refused_count is counted here.
//
// Append-only history (src/ops/historyTables.ts), like tool_call_log itself.
//
// GOV-1: S1 primary key; S2 created_at only (written once); S3 references declared and indexed;
// S6 unique natural key.
table tool_call_run {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int tool_call_log_id? {
      table = "tool_call_log"
      description = "The audit row of the call. Unique."
    }

    int copilot_run_id? {
      table = "copilot_run"
      description = "The scheduled run the call was made in."
    }

    int pin_architecture_id? {
      table = "journey_architecture"
      description = "The business the run's ticket was pinned to."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "tool_call_log_id", op: "asc"}]}
    {type: "btree", field: [{name: "copilot_run_id", op: "asc"}]}
    {type: "btree", field: [{name: "pin_architecture_id", op: "asc"}]}
  ]
}
