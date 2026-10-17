// PLN-1 (US-PLN-1-05) — A unit of planned work, either sitting on a day's
// timeline or waiting in the backlog.
//
// Deliberately has NO `planned_start` column: a task's start time is
// derived by walking the timeline's start_time plus the durations ahead of
// it, so a stored copy could only ever disagree with the order.
//
// Amended in this first push by phase-4's P3A-1 (US-P3A-1-01): `title`
// becomes nullable at schema level (a task linked to a job takes the job's
// title) and `tweak_reason` is added.
//
// `(timeline_id, seq)` is intentionally NOT unique: a reorder rewrites
// several rows and would transiently collide. The resequence function
// (PLN-7) is what guarantees the sequence is dense and unique.
table planner_task {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int workspace_id? {
      table = "planner_workspace"
    }

    int timeline_id? {
      table = "planner_timeline"
      description = "0 = backlog (not scheduled onto any day). An int column cannot hold a real null here, so 0 is the documented 'unscheduled' value."
    }

    int assignee_agent_id? {
      table = "planner_agent"
      description = "Optional override of the timeline's agent. 0 = inherit from the timeline."
    }

    text title? filters=trim {
      description = "P3A-1: nullable at schema level. The API requires it when the task is not linked to a job; a linked task takes its title from the job (JOB-1)."
    }

    int seq?=0 {
      description = "Position within a timeline, or order within the backlog. Rewritten in bulk by the resequence function (PLN-7)."
    }

    int duration_minutes?=30 {
      description = "Must be > 0. API-enforced (PLN-7)."
    }

    text notes? filters=trim

    // KNOWN DEVIATION: US-PLN-1-05 asks for default "planned", and this
    // column has no default — a direct insert leaves it "", which is not
    // even a member of the enum. Adding a default after the fact needs
    // either updateTableSchema (which silently drops this table's four
    // trim validators — see CLAUDE.md) or a table recreate, so it is left
    // for a dashboard edit. PLN-7 always writes status explicitly, so no
    // row created through the API can land without one.
    enum status? {
      values = ["planned", "needs_info"]
    }

    text needs_info_reason? filters=trim

    text tweak_reason? filters=trim {
      description = "P3A-1: why this task's duration was changed for this job, kept so a tweak can be explained later."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "timeline_id", op: "asc"}, {name: "seq", op: "asc"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}, {name: "timeline_id", op: "asc"}]}
    {type: "btree", field: [{name: "assignee_agent_id", op: "asc"}]}
  ]
}
