// REPEAT-1 (US-REPEAT-1-04 writes it, US-REPEAT-1-05 shows and clears it) — "needs review" on a
// scheduled slot: one row per slot a person should look at, with the reason. No row = nothing to
// review. DRAFT: not pushed yet; the id 182 is a guess until Xano assigns it.
//
// WHY A SIDE TABLE, NOT A STATUS: `planner_task.status` already has `needs_info`, which means
// something else (the job is missing information), and adding a value to that column means
// changing a table whose trim validators `updateTableSchema` silently drops (CLAUDE.md). Same
// side-table move as planner_task_start_override.
//
// UNIQUE ON THE SLOT: a slot has at most one mark. Clearing keeps the row (cleared_at /
// cleared_by / cleared_how) as history; a later reason (AVAIL-1 time off, MATCH-1 a lapsed
// qualification) re-raises the same row, so there is still one per slot.
//
// `reason_code` IS TEXT, NOT AN ENUM, on purpose: later epics add reasons, and extending an enum
// later means updateTableSchema on this table. The writer validates the code; today:
// copied | person_left_off | new_step.
//
// DELETE BEHAVIOUR: deleted with its slot (planner/delete_task, story 05). It never blocks a slot
// delete. `source_workspace_id` is a plain int, like plan_repeat's, so it never blocks the source.
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
