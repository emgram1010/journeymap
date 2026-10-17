// JOB-1 (US-JOB-1-01) — One step of one job.
//
// A task is a POINTER AND A STATUS, nothing more. `stage_key` and
// `lens_key` identify a cell in the job's pinned version; the task
// text, done-when, owner row and expected minutes are all read from
// there at read time. There is deliberately no text column here — a
// copy would drift from the version it came from, and then nobody
// would know which one was true.
//
// `status` changes ONLY through LOG-1's engine, from the fixed list
// in the architecture rules. Nothing else writes it.
//
// The unique key is (work_item_id, stage_key, lens_key): one job gets
// exactly one task per cell of its version. A duplicate would mean
// the same step of the same job tracked twice, with two different
// answers about whether it was done.
//
// Live id 123 (the epic reserved 87; Xano assigns its own ids).
table work_task {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int work_item_id? {
      table = "work_item"
    }

    text stage_key? filters=trim {
      description = "Identifies a stage in the job's PINNED version, not a row in journey_stage."
    }

    text lens_key? filters=trim {
      description = "Identifies a row in the job's PINNED version, not a row in journey_lens."
    }

    enum status?=not_started {
      values = ["not_started", "in_progress", "blocked", "done", "skipped"]
      description = "The fixed status list. Written only by LOG-1's engine."
    }

    timestamp started_at?

    timestamp completed_at?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "work_item_id", op: "asc"}, {name: "stage_key", op: "asc"}, {name: "lens_key", op: "asc"}]}
  ]
}
