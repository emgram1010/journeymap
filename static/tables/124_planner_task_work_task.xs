// SCHED-1 (US-SCHED-1-01) — Which scheduled slot covers which job
// step.
//
// A JOIN TABLE, NOT A COLUMN, and that is deliberate. Today one
// scheduled item covers exactly one work task, so a column on
// `planner_task` would do. But blocks are coming (US-SCHED-1-02,
// deferred): one slot covering several consecutive steps of a job.
// Keeping the relationship many-to-one from the start means blocks
// arrive without a migration.
//
// `work_task_id` IS UNIQUE — a step is scheduled at most once. Two
// slots claiming the same step would give a performer the same work
// twice and make the variance figures meaningless. This is the
// constraint that makes E-SCHED-001 reliable rather than a race.
//
// `position` orders the steps inside a block. With one step per slot
// it is always 1; it exists now so the ordering is not retrofitted.
//
// Append-only link table (GOV-1 S10): `created_at`, no `updated_at`.
// A link is created or removed, never edited.
//
// Live id 124 (the epic reserved 88; Xano assigns its own ids).
table planner_task_work_task {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int planner_task_id? {
      table = "planner_task"
    }

    int work_task_id? {
      table = "work_task"
      description = "Unique — a work task may be scheduled at most once (E-SCHED-001)."
    }

    int position?=1 {
      description = "Order within a block. Always 1 while one slot covers one step."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "planner_task_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "work_task_id", op: "asc"}]}
  ]
}
