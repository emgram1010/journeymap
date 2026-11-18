// COP-11 (2026-11-18) — the lock and the kind of work for ONE item in the copilot's skill library
// ("How I work"). A 1:1 side table: copilot_skill has trim-filtered text columns, and
// updateTableSchema silently drops validators, so a new optional field goes beside it (house rule,
// same shape as journey_stage_owner). No row = not locked, kind of work "general".
//
// Written ONLY by copilot/skill_write (kind of work, and the owner's automatic lock) and by
// POST copilot/skill_lock (a signed-in admin, never an AI identity). No AI tool touches it.
// Rows are never deleted: unlocking keeps the row with is_locked = false. Every lock change is
// also a version in copilot_skill_version.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key (skill_id); S7 enum for work_kind.
table copilot_skill_meta {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int skill_id? {
      table = "copilot_skill"
    }

    int account_id? {
      table = "account"
    }

    bool is_locked? {
      description = "Locked = the copilot follows it but can only suggest a change (E-COP-089)."
    }

    int locked_by_user_id? {
      table = "user"
      description = "The person who last locked or unlocked it. Never the copilot user."
    }

    timestamp locked_at?

    enum work_kind? {
      values = ["map_building", "planning", "doing_work", "research", "general"]
      description = "The job this item is for, so each AI can load only what helps it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "skill_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "locked_by_user_id", op: "asc"}]}
  ]
}
