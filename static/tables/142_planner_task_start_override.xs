// SCHED-2 (US-SCHED-2-01) — A scheduled task's manual start-time
// override. One row per planner_task that has one; no row = no
// override = exactly today's computed behaviour (timeline start_time
// + cumulative durations of everything scheduled before it, PLN-7).
//
// WHY A SIDE TABLE, NOT A COLUMN ON `planner_task`: planner_task
// carries `trim` on title, notes and tweak_reason. updateTableSchema
// silently drops a table's trim validators (CLAUDE.md, confirmed on
// user/event_log, journey_stage/journey_lens, and work_item_time_window
// used the same reasoning). A side table touches nothing that exists.
//
// HH:MM ONLY, NOT A DATE: this never moves a task to a different day,
// only to a different time within the day it is already scheduled on.
// Moving days is still drag-to-day on the board, unchanged.
//
// Delete = delete this row; the task is never touched, and reverts to
// the computed time.
table planner_task_start_override {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int planner_task_id? {
      table = "planner_task"
      description = "The scheduled slot. Unique: one override per slot in V1."
    }

    text start_time? filters=trim {
      description = "HH:MM, 00:00-23:59 (API-enforced, E-SCHED-009)."
    }

    text reason? filters=trim {
      description = "Why the time was overridden. Max 200."
    }

    int updated_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "planner_task_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by", op: "asc"}]}
  ]
}
