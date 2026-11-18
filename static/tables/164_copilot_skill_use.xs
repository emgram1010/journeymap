// COP-9 story 01 (2026-11-17) — which skill (and which exception, if one fired) the copilot used,
// in which chat or scheduled run, and whether it was on trial at the time. Written by the copilot's
// record_skill_used tool. Without this nothing about a skill can be measured: trial results
// (story 05) and Health's "runs with no skill used" both count here.
//
// Append-only history (src/ops/historyTables.ts): written once, never edited or deleted.
//
// GOV-1: S1 primary key; S2 created_at only (written once); S3 references declared and indexed.
table copilot_skill_use {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int skill_id? {
      table = "copilot_skill"
    }

    int exception_skill_id? {
      table = "copilot_skill"
      description = "The exception that fired, if any. 0 = none."
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business the copilot was working on."
    }

    int copilot_run_id? {
      table = "copilot_run"
      description = "The scheduled run. 0 = a chat."
    }

    int conversation_id? {
      table = "agent_conversation"
      description = "The chat. 0 = a scheduled run."
    }

    int skill_version_no? {
      description = "The version of the skill that was loaded."
    }

    bool was_trial? {
      description = "The skill (or exception) was on trial, so this counts toward its trial."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "skill_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "exception_skill_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "copilot_run_id", op: "asc"}]}
    {type: "btree", field: [{name: "conversation_id", op: "asc"}]}
  ]
}
