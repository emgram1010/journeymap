// EXC-1 (US-EXC-1-02) — One row per exception spawn: work left the
// happy path on a parent job's step and became a CHILD JOB on the map
// the parent's exception link points to.
//
// WHY A TABLE, NOT `work_item.attributes` (D-11, confirmed by the
// founder 2026-10-26): attributes is flat key/value by JOB-1's rules;
// this is a relationship with history (which step, why, which counts
// moved, who) and reporting needs (Health: open children by stage,
// reason and linked map).
//
// APPEND-ONLY. Never deleted — same stance as activity_log; it is on
// historyTables.ts's list, so a delete anywhere in code fails the build
// (FT-EXC-1-G05). The ONE edit ever made: `parent_blocked` set to true,
// once, by endpoint 610 right after LOG-1's engine accepted the optional
// block (it cannot be known before the insert).
// Both jobs are cancel-never-delete already; this row is what lets
// Health say "this child's parent was cancelled" (D-7: cancelling a
// parent never cancels its children).
//
// `stage_key` / `lens_key` are COPIED from the parent task at spawn
// time on purpose: they must survive later edits to the live map.
//
// `link_type` accepts only `exception` in the MVP (D-6). The enum is
// kept so `sub_journey` / `anti_journey` can be allowed later without
// a schema change.
//
// `reason_code` is EX-5's one list, the same four values as
// activity_log.reason_code — never a second vocabulary.
//
// `moved_lines` is written ONCE, on db.add. db.patch on a json column
// MERGES (CLAUDE.md) — if this is ever rewritten, use the two-step
// null-then-value patch.
//
// GOV-1 standards: S1 primary key; S2 created_at (no updated_at — the
// row never changes); S3 declared + indexed references; S6 unique
// child_work_item_id (one record per child), and unique
// (parent_work_item_id, parent_seq): the race guard for two sends at once.
table work_item_exception {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
      description = "Tenancy (GOV-1 S4). Always the parent job's account."
    }

    int parent_work_item_id? {
      table = "work_item"
      description = "The job the work left."
    }

    int parent_work_task_id? {
      table = "work_task"
      description = "The step the exception was raised on."
    }

    int child_work_item_id? {
      table = "work_item"
      description = "The child job created on the linked map. Unique: one record per child."
    }

    text stage_key? filters=trim {
      description = "Copied from the parent task at spawn time."
    }

    text lens_key? filters=trim {
      description = "Copied from the parent task at spawn time."
    }

    enum link_type?=exception {
      values = ["exception", "sub_journey", "anti_journey"]
      description = "MVP writes only `exception` (D-6)."
    }

    int target_map_id? {
      table = "journey_map"
      description = "The linked map."
    }

    int target_version_id? {
      table = "journey_map_version"
      description = "The linked map's latest published version at spawn time (D-2); the child is pinned to it."
    }

    enum reason_code?=other {
      values = ["waiting_on_someone", "missing_information", "something_went_wrong", "other"]
      description = "EX-5's one list, same as activity_log.reason_code."
    }

    text note? filters=trim {
      description = "0-500 chars, no HTML (API-enforced, E-EXC-011)."
    }

    json moved_lines? {
      description = "[{item_type_id, item_key, quantity}] - [] for a whole-job exception. Written once."
    }

    bool parent_blocked?=false {
      description = "Whether the parent step was also blocked (through LOG-1's engine)."
    }

    enum source?=manual {
      values = ["manual", "ai", "system"]
      description = "PRD EX-9 hook: ai/system callers later."
    }

    int created_by? {
      table = "user"
      description = "0 for ai/system."
    }

    int parent_seq? {
      description = "Nth exception on this parent (1, 2, 3...). Unique with parent_work_item_id: two simultaneous sends compute the same N and the database refuses the second. Rows made before this column were backfilled to -id."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "child_work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "parent_work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "parent_work_task_id", op: "asc"}]}
    {
      type : "btree"
      field: [
        {name: "account_id", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
    {type: "btree", field: [{name: "target_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "target_version_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by", op: "asc"}]}
    {
      type : "btree|unique"
      field: [
        {name: "parent_work_item_id", op: "asc"}
        {name: "parent_seq", op: "asc"}
      ]
    }
  ]
}
