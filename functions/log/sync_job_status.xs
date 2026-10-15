//  LOG-1 (US-LOG-1-04) — Re-derive a job's status from its tasks and
//  write the cache.
//
//  `work_item.status` is a CACHE. The truth is the tasks, and the
//  tasks' truth is the activity log. This is the only thing that
//  writes that cache, and it runs after every recorded event — so the
//  two cannot drift between the event and the next nightly audit.
//
//  Without this, LOG-1 would move a task to `done` and leave the job
//  saying `open` forever: GOV-1's audit compares the stored status
//  against the derived one and would report every finished job as a
//  violation on day one.
//
//  THE RULE ITSELF LIVES IN `log/derive_job_status`, which is
//  read-only and is what the audit calls. Keeping the rule in one
//  place is the whole point: an audit holding its own copy would
//  disagree with the writer sooner or later, and sound just as
//  certain when it did.
function "log/sync_job_status" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    function.run "log/derive_job_status" {
      input = {work_item_id: $input.work_item_id}
    } as $d

    db.patch work_item {
      field_name = "id"
      field_value = $input.work_item_id
      data = {
        status     : $d.status
        started_at : $d.started_at
        finished_at: $d.finished_at
        updated_at : "now"
      }
    } as $updated
  }

  response = {
    work_item_id: $input.work_item_id
    status      : $d.status
    started_at  : $d.started_at
    finished_at : $d.finished_at
    task_count  : $d.task_count
  }
}
