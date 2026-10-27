//  LOG-1 (US-LOG-1-03, US-LOG-1-04) — Record one thing that happened
//  to a task.
//
//  THE MOST IMPORTANT WRITE PATH IN THE PRODUCT, and the only thing
//  allowed to move `work_task.status`. Start and end times are never
//  typed in — they come from the taps recorded here.
//
//  A DUPLICATE TAP IS A SUCCESS, NOT AN ERROR. A performer on a slow
//  connection taps Done twice; the second request finds the existing
//  `client_event_id` and returns the first result unchanged. Treating
//  it as a failure would show an error for something that worked;
//  treating it as a new event would record the work as finished twice.
//
//  THE JOB'S STATUS IS RE-DERIVED AFTER EVERY EVENT
//  (`log/sync_job_status`). `work_item.status` is a cache of the
//  tasks, and GOV-1's audit compares the two — without this call
//  every finished job would read `open` and the audit would report
//  the whole table as broken on day one.
//
//  THE REFUSAL MESSAGE NEVER SHOWS A RAW STATUS. The first version
//  said "This step is in_progress" — an internal enum, with an
//  underscore, shown to someone holding a phone. VAL-1 forbids that.
//
//  THE TRANSITION TABLE IS NOT HERE. It lives in `log/next_status`,
//  the single backend copy, which the replay audit also calls — an
//  audit holding its own copy of the rule would disagree with the
//  engine sooner or later and sound just as certain when it did. Its
//  pure twin is `webapp/protype-2/src/logModel.ts::canTransition`,
//  tested against an independently transcribed copy of the epic's
//  table; all 35 pairs were diffed live and matched.
//
//  `completed` FROM `not_started` IS ALLOWED (D-38). People finish
//  things without pressing Start; refusing it would push them to
//  invent a start time, which is worse than an honestly unknown one.
//
//  The log row and the task's status move in ONE `db.transaction`. A
//  status without its log entry would be a status nobody can explain.
//
//  EXC-1 (2026-10-26): THE ENGINE NOW LIVES IN `log/record_task_event`,
//  moved verbatim, so the exception spawn blocks a parent step (and
//  leaves its `note`) through exactly these rules. This endpoint calls
//  it with soft = false, so every refusal raises with the same code,
//  message and error type as before — re-verified by replaying a
//  14-outcome sequence before and after the move (FT-EXC-1-15).
query "work_task/{work_task_id}/event" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_task_id filters=min:1
    enum event_type {
      values = [
        "started"
        "completed"
        "blocked"
        "unblocked"
        "skipped"
        "reopened"
        "note"
      ]
    }

    text reason_code? filters=trim
    text note? filters=trim
    text client_event_id filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "log/record_task_event" {
      input = {
        actor          : $actor
        work_task_id   : $input.work_task_id
        event_type     : $input.event_type
        reason_code    : $input.reason_code
        note           : $input.note
        client_event_id: $input.client_event_id
        correlation_id : $input.correlation_id
        source         : "manual"
        soft           : false
      }
    } as $result
  }

  response = {
    work_task          : $result.work_task
    from               : $result.from
    to                 : $result.to
    job_status         : $result.job_status
    duplicate          : $result.duplicate
    publication        : $result.publication
    stage              : $result.stage
    all_stages_complete: $result.all_stages_complete
  }
}
