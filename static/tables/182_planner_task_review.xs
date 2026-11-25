// REPEAT-1 (US-REPEAT-1-04 writes it, US-REPEAT-1-05 shows and clears it) — "needs review" on a scheduled slot: one row per slot a person should look at, with the reason. No row = nothing to review. A side table, not a status: planner_task.status's needs_info means something else, and changing that table would drop its trim validators. Unique on the slot; clearing keeps the row as history. reason_code is text so later epics can add reasons (copied | person_left_off | new_step today). Deleted with its slot; source_workspace_id is a plain int.
// Pushed 2026-11-25 with the founder's yes: live table id 182 (new table; no existing table changed).
table planner_task_review {
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

    int workspace_id? {
      table = "planner_workspace"
    }

    int planner_task_id? {
      table = "planner_task"
      description = "The slot. Unique: one mark per slot."
    }

    text reason_code? {
      description = "copied | person_left_off | new_step (validated by the writer)."
    }

    text reason_text? {
      description = "Plain words shown on the slot, e.g. 'copied from Week 12'."
    }

    int source_workspace_id? {
      description = "The plan the slot was copied from. Plain int on purpose."
    }

    timestamp cleared_at? {
      description = "0 / empty = still needs review."
    }

    int cleared_by? {
      table = "user"
    }

    text cleared_how? {
      description = "one | day | publish | moved (story 05)."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "planner_task_id", op: "asc"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "cleared_by", op: "asc"}]}
  ]
}
