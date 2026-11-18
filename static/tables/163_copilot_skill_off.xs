// COP-9 stories 01/08 (2026-11-17) — a skill-library item switched OFF for ONE business, without
// retiring or deleting it. copilot/skill_library skips an item for a business when a row here says
// is_off = true; every other business in its scope still loads it. Written only by a signed-in
// person (POST copilot/skill_switch), never by the copilot.
//
// Unique (skill_id, journey_architecture_id): one switch per item per business. Edited in place
// (switching back on keeps the row); each switch is also in event_log.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key.
table copilot_skill_off {
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

    int skill_id? {
      table = "copilot_skill"
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business it is switched off for."
    }

    bool is_off?

    int updated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "skill_id", op: "asc"}, {name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
