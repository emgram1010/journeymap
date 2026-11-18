// COP-9 stories 01/02/04 (2026-11-17) — one item in the copilot's SKILL LIBRARY ("how I work"):
// a skill, an exception (a "when X, do Y instead" branch on one skill), a lesson, or a link
// between two skills. Lives in the account's copilot home (copilot_home); each item also has a
// draft map there (journey_map_id) so it shows in "how I work" like any other map.
//
// `body` is the text the copilot actually follows. It is loaded into every chat and scheduled
// run (copilot/skill_library) unless the item is retired, switched off for the business
// (copilot_skill_off), or scoped elsewhere. Every change writes a full copy to
// copilot_skill_version first, so one click puts any earlier version back.
//
// Written ONLY by copilot/skill_write (hard limits E-COP-081..084 sit there, on the server).
// Never deleted by the copilot: it retires. Edited in place; the history is the version table.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key (journey_map_id); S7 enums for kind, status, scope_type.
table copilot_skill {
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

    int home_architecture_id? {
      table = "journey_architecture"
      description = "The copilot's own business (copilot_home) this item lives in."
    }

    int journey_map_id? {
      table = "journey_map"
      description = "The draft map in 'how I work' that shows this item. Unique."
    }

    enum kind? {
      values = ["skill", "exception", "lesson", "link"]
    }

    enum status? {
      values = ["trial", "trusted", "retired"]
      description = "trial = new, used and marked; trusted = proven; retired = never loaded."
    }

    text title? filters=trim

    text body? filters=trim {
      description = "What the copilot follows: steps, inputs, what done looks like."
    }

    text condition_text? filters=trim {
      description = "Exceptions only: WHEN it applies. Required for an exception (E-COP-084)."
    }

    int parent_skill_id? {
      description = "Exception: the skill it branches. Link: the skill it starts from. (copilot_skill id)"
    }

    int link_to_skill_id? {
      description = "Link only: the skill it points to. (copilot_skill id)"
    }

    enum scope_type? {
      values = ["all", "business", "map", "work_kind"]
      description = "Where it applies. all = every business in the account."
    }

    int scope_ref_id? {
      description = "business = journey_architecture id; map = journey_map id; else 0."
    }

    text scope_text? filters=trim {
      description = "work_kind only: the kind of work, in plain words."
    }

    int version_no? {
      description = "The current version (copilot_skill_version.version_no)."
    }

    int created_by_user_id? {
      table = "user"
    }

    int updated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "status", op: "asc"}]}
    {type: "btree", field: [{name: "home_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "parent_skill_id", op: "asc"}]}
    {type: "btree", field: [{name: "link_to_skill_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
