// TW-1 (US-TW-1-01) — A job's time window: when this piece of work is
// allowed to happen. One row per job that has one; no row = no window.
//
// WHY A SIDE TABLE, NOT COLUMNS ON `work_item`: changes to existing
// tables are additive-only, and `updateTableSchema` silently drops the
// trim validators on any table that has them (CLAUDE.md, GOV-1/STAGE-1
// precedent) — work_item has `title` with trim. Not `attributes` either:
// anything the system computes with is a column (PRD invariant 3), and
// db.patch on a json column merges.
//
// DATE + HH:MM, NOT AN EPOCH TIMESTAMP: the planner already speaks
// plan-local `planned_date` + `start_time` with no timezone. A window may
// cross midnight; the only rule is end after start (API-enforced).
//
// `constraint_type` IS RESERVED FOR V2 (soft/hard). Created now so V2 is
// a UI change and a guard, not a migration. V1 only ever writes `soft`.
//
// Delete = delete this row; the job is never touched. A cancelled job
// keeps its window as history and refuses edits (E-TW-005).
table work_item_time_window {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int work_item_id? {
      table = "work_item"
      description = "The job. Unique: one window per job in V1."
    }

    date start_date?

    text start_time? filters=trim {
      description = "HH:MM, 00:00-23:59 (API-enforced, E-TW-001)."
    }

    date end_date?

    text end_time? filters=trim {
      description = "HH:MM. end_date + end_time must be after the start (E-TW-002)."
    }

    text note? filters=trim {
      description = "Why the window exists. Max 200 (E-TW-006)."
    }

    enum constraint_type?=soft {
      values = ["soft", "hard"]
      description = "Reserved for V2. V1 writes only soft and the UI does not show it."
    }

    int updated_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by", op: "asc"}]}
  ]
}
