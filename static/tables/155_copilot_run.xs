// COP-5 story 05 (2026-11-15) — one row per scheduled copilot run, for one business (or for the
// account when there was nothing to do). The run log AND the "two runs never overlap" guard.
//
// The guard is the UNIQUE index on lock_key, not a transaction (CLAUDE.md: a transaction does not
// serialize two overlapping requests; a unique index does):
//   running  -> lock_key = "run::a<account>::b<business>"  (one per business at a time)
//   finished / failed / skipped / nothing_to_do -> lock_key = a value unique to that row
// A second run for the same business while one is running fails the insert and is recorded as
// "skipped". A run that never finished (crash, timeout) is marked "failed" by the next tick after
// 30 minutes and its lock released, so one dead run can never block the business for good.
//
// Every tick writes at least one row per account that has scheduled runs switched on, even when
// there is nothing to do (the heartbeat incident: a task that writes nothing looks healthy).
//
// `report` is the copilot's own words, shown to the account's people only. The run ticket is
// scrubbed from it. History: never deleted by the app.
//
// GOV-1: S1 primary key; S2 created_at + finished_at; S3 references declared and indexed;
// S6 unique key (lock_key).
table copilot_run {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business the run worked on. 0 = the account had nothing to do."
    }

    int copilot_user_id? {
      table = "user"
      description = "The AI identity that ran."
    }

    enum trigger? {
      values = ["schedule", "manual"]
    }

    enum status? {
      values = ["running", "finished", "nothing_to_do", "skipped", "failed"]
    }

    text lock_key? filters=trim {
      description = "Unique. While running: one value per business. Afterwards: unique to the row."
    }

    timestamp started_at?

    timestamp finished_at?

    text work_date? filters=trim {
      description = "The day whose tasks the run looked at, YYYY-MM-DD."
    }

    int open_task_count? {
      description = "The copilot's open tasks in this business when the run started."
    }

    text work_fingerprint? filters=trim {
      description = "The open tasks and their statuses when the run ended. Same as last time = nothing new."
    }

    int held_count? {
      description = "Actions stored for the owner's approval during the run."
    }

    int told_count? {
      description = "Actions done and listed under 'What the copilot did' during the run."
    }

    int refused_count? {
      description = "Tool calls the gate refused during the run."
    }

    text report? filters=trim {
      description = "What it did, what it held, what failed - in the copilot's words."
    }

    text reason? filters=trim {
      description = "Why it was skipped, failed or had nothing to do, in plain words."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "lock_key", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "journey_architecture_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "copilot_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "status", op: "asc"}, {name: "started_at", op: "asc"}]}
  ]
}
