// COP-9 story 04 (2026-11-17) — every change to a skill-library item, as a FULL copy of the item
// after the change (`content`), with who changed it (copilot or owner), why, and the run or chat
// it came from. Undo copies an earlier version's content back and writes a NEW version (change
// "undo"), so nothing is ever lost.
//
// Unique (skill_id, version_no): two writers racing on the same item cannot both claim the same
// number — the second insert fails at the database and its transaction rolls back (a transaction
// alone does not serialize overlapping requests here — CLAUDE.md, endpoint 610).
//
// Append-only history (src/ops/historyTables.ts): never edited, never deleted.
//
// GOV-1: S1 primary key; S2 created_at only (written once); S3 references declared and indexed;
// S6 unique natural key; S7 enums for change and changed_by.
table copilot_skill_version {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int skill_id? {
      table = "copilot_skill"
    }

    int account_id? {
      table = "account"
    }

    int version_no?

    enum change? {
      values = ["create", "edit", "retire", "undo"]
    }

    enum changed_by? {
      values = ["copilot", "owner"]
    }

    int changed_by_user_id? {
      table = "user"
    }

    text reason? filters=trim {
      description = "Why, in plain words."
    }

    json content? {
      description = "The whole item after this change: title, body, condition, scope, status, links."
    }

    int copilot_run_id? {
      table = "copilot_run"
      description = "The scheduled run it came from. 0 = a chat or the owner."
    }

    int conversation_id? {
      table = "agent_conversation"
      description = "The copilot chat it came from. 0 = a run or the owner."
    }

    int undo_of_version_no? {
      description = "Undo only: the version whose content was put back."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "skill_id", op: "asc"}, {name: "version_no", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "changed_by_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "copilot_run_id", op: "asc"}]}
    {type: "btree", field: [{name: "conversation_id", op: "asc"}]}
  ]
}
