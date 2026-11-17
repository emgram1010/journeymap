// COP-8 story 03 (2026-11-16, R15) — ties a run ticket to the scheduled copilot run that minted it.
// copilot/run_for_business writes one row right after usr/mint_tool_ticket, so the gate can tell
// which run a ticketed tool call belongs to (tool_call_run). A side table, not a column on
// tool_run_ticket (text validators — CLAUDE.md). Holds ids only — never the ticket text.
// Unique tool_run_ticket_id: a ticket can be linked to one run only.
//
// Append-only history (src/ops/historyTables.ts). The tool_run_ticket row it points at may be
// cleared once expired; this link stays as the record of which ticket id served which run.
//
// GOV-1: S1 primary key; S2 created_at only (written once); S3 references declared and indexed;
// S6 unique natural key.
table copilot_run_ticket {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int copilot_run_id? {
      table = "copilot_run"
      description = "The scheduled run that minted the ticket."
    }

    int tool_run_ticket_id? {
      table = "tool_run_ticket"
      description = "The run's ticket row (its id, never its text). Unique."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "tool_run_ticket_id", op: "asc"}]}
    {type: "btree", field: [{name: "copilot_run_id", op: "asc"}]}
  ]
}
