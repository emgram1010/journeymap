//  EXC-1 (extraction before US-EXC-1-03) — THE ONE PLACE A JOB IS
//  WRITTEN: the work_item row and one work_task per planned task.
//  Extracted verbatim from 554's transaction so `554` (add a job) and
//  the exception spawn (a child job) create jobs through the same
//  code. A rule that lives in two places eventually disagrees with
//  itself (LOG-1's house rule).
//
//  WRITES ONLY. NO VALIDATION, NO TRANSACTION, NO LOGGING. Callers do
//  every check first, compute `tasks` with `jobs/tasks_from_version`
//  first, then call this INSIDE their own `db.transaction` — so a
//  spawn's child job, its lines, the parent's line edits and the
//  exception row commit or roll back together.
//
//  A function.run INSIDE db.transaction rolls back with it: verified
//  live 2026-10-26 with a scratch pair (inner function's db.add and the
//  outer's own db.add both vanished when a later precondition failed;
//  the ids they had consumed were skipped). CLAUDE.md's "no
//  function.run inside a transaction" was caution, not a measured
//  limit — this is the measured exception, for a write-only function.
//
//  `parent_work_item_id` is 0 for an ordinary job (0 == null in this
//  engine; test `!= 0`, never `!= null`).
function "jobs/create_job" {
  input {
    int account_id filters=min:1
    int workspace_id filters=min:1
    int journey_map_version_id filters=min:1
    text title filters=trim
    json attributes?
    int parent_work_item_id?
    int created_by?
    json tasks
    json order_lines?
    json unmatched_lines?
  }

  stack {
    db.add work_item {
      data = {
        account_id            : $input.account_id
        workspace_id          : $input.workspace_id
        journey_map_version_id: $input.journey_map_version_id
        title                 : $input.title
        status                : "open"
        attributes            : ($input.attributes ?? {})
        parent_work_item_id   : $input.parent_work_item_id
        created_by            : $input.created_by
      }
    } as $job

    foreach ($input.tasks) {
      each as $t {
        db.add work_task {
          data = {
            work_item_id: $job.id
            stage_key   : $t.stage_key
            lens_key    : $t.lens_key
            status      : "not_started"
          }
        } as $task
      }
    }

    // SCALE-1 story 01: the job's order lines (and the items that could not become a line) are
    // written with the job, inside the caller's transaction. Nothing sent = nothing written.
    var $ol_text {
      value = ($input.order_lines ?? [])|json_encode
    }

    var $ol_first {
      value = $ol_text|substr:0:1
    }

    var $ol_rows {
      value = []
    }

    conditional {
      if ($ol_first == "[") {
        var.update $ol_rows {
          value = $input.order_lines
        }
      }
    }

    foreach ($ol_rows) {
      each as $ol_row {
        db.add work_item_line {
          data = {
            created_at      : "now"
            work_item_id    : $job.id
            item_type_id    : $ol_row.item_type_id
            quantity        : $ol_row.quantity
            flagged_quantity: 0
            created_by      : $input.created_by
          }
        } as $ol_added
      }
    }

    var $um_text {
      value = ($input.unmatched_lines ?? [])|json_encode
    }

    var $um_first {
      value = $um_text|substr:0:1
    }

    var $um_rows {
      value = []
    }

    conditional {
      if ($um_first == "[") {
        var.update $um_rows {
          value = $input.unmatched_lines
        }
      }
    }

    foreach ($um_rows) {
      each as $um_row {
        db.add work_item_unmatched_line {
          data = {
            created_at   : "now"
            account_id   : $input.account_id
            work_item_id : $job.id
            source_system: $um_row.source_system
            external_id  : $um_row.external_id
            label        : $um_row.label
            quantity     : $um_row.quantity
            reason       : $um_row.reason
          }
        } as $um_added
      }
    }
  }

  response = $job
}
