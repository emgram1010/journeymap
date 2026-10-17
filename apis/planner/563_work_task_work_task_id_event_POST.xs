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

    db.get work_task {
      field_name = "id"
      field_value = $input.work_task_id
    } as $task

    precondition ($task != null) {
      error_type = "notfound"
      error = "Step not found"
    }

    db.get work_item {
      field_name = "id"
      field_value = $task.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Step not found"
    }

    // Which scheduled slot is this task on? One lookup answers two
    // questions: whose work it is, and which frozen day the performer
    // was looking at.
    var $publication_id {
      value = 0
    }

    var $item_ref {
      value = ""
    }

    var $assigned_user {
      value = 0
    }

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id == $input.work_task_id
      return = {type: "list"}
    } as $links

    conditional {
      if (($links|count) > 0) {
        var $slot_id {
          value = ($links|first).planner_task_id
        }

        db.get planner_task {
          field_name = "id"
          field_value = $slot_id
        } as $slot

        db.get planner_timeline {
          field_name = "id"
          field_value = $slot.timeline_id
        } as $tl

        conditional {
          if ($tl != null) {
            db.get planner_agent {
              field_name = "id"
              field_value = $tl.agent_id
            } as $agent

            conditional {
              if ($agent != null && $agent.user_id != null && $agent.user_id != 0) {
                var.update $assigned_user {
                  value = $agent.user_id
                }
              }
            }
          }
        }

        db.query plan_publication {
          where = $db.plan_publication.timeline_id == $slot.timeline_id
          return = {type: "list"}
        } as $pubs

        conditional {
          if (($pubs|count) > 0) {
            var.update $publication_id {
              value = ($pubs|first).id
            }

            var.update $item_ref {
              value = "pt-" ~ ($slot_id|to_text)
            }
          }
        }
      }
    }

    // E-LOG-003. Work scheduled to a named person is recorded by that
    // person, or by an account admin acting for them.
    //
    // UNASSIGNED WORK IS NOT BLOCKED. `planner_agent.user_id` is 0
    // until an agent is linked to a login, and most are; denying
    // those would stop all work rather than protect anything. Where
    // there is no assignment there is nobody to deny, and account
    // tenancy above still applies. APP-1 makes assignment the normal
    // case; this rule tightens by itself as that data appears.
    var $assignment_ok {
      value = ($assigned_user == 0 || $assigned_user == $actor.user_id || $actor.role == "admin")
    }

    conditional {
      if ($assignment_ok == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "LOG-1"
            step          : "record_event"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : "E-LOG-003"
            message       : "Task event refused: not the assigned performer."
          }
        }
      }
    }

    precondition ($assignment_ok) {
      error_type = "accessdenied"
      error = "This step isn't assigned to you. (E-LOG-003)"
    }

    db.query activity_log {
      where = $db.activity_log.client_event_id == $input.client_event_id
      return = {type: "list"}
    } as $existing

    var $is_duplicate {
      value = (($existing|count) > 0)
    }

    var $from {
      value = $task.status
    }

    // The transition table lives in log/next_status — ONE backend
    // copy, shared with the replay audit, mirrored by
    // logModel.ts::canTransition. All 35 (status, event) pairs were
    // diffed live against the TypeScript twin and matched.
    function.run "log/next_status" {
      input = {from: $from, event: $input.event_type}
    } as $trans

    var $to {
      value = $trans.to
    }

    var $not_available {
      value = $trans.message
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    var $reason_ok {
      value = ($input.reason_code == "waiting_on_someone" || $input.reason_code == "missing_information" || $input.reason_code == "something_went_wrong" || $input.reason_code == "other")
    }

    conditional {
      if ($input.event_type == "blocked" && $input.reason_code == "") {
        var.update $reject_code {
          value = "E-LOG-002"
        }

        var.update $reject_msg {
          value = "Pick a reason so the team knows why. (E-LOG-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.event_type == "blocked" && $reason_ok == false) {
        var.update $reject_code {
          value = "E-LOG-005"
        }

        var.update $reject_msg {
          value = "Pick one of the listed reasons. (E-LOG-005)"
        }
      }
    }

    // APP-2 (US-APP-2-02, -06): a note event was always accepted with
    // whatever text came in, including none at all. "The UI helps, the
    // server always re-checks" (CLAUDE.md) — the Step screen's own box
    // refuses an empty save, but this endpoint is the one that actually
    // enforces it.
    conditional {
      if ($reject_code == "" && $input.event_type == "note" && ($input.note == null || $input.note == "")) {
        var.update $reject_code {
          value = "E-LOG-006"
        }

        var.update $reject_msg {
          value = "Write something before saving. (E-LOG-006)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.event_type == "note" && ($input.note|strlen) > 1000) {
        var.update $reject_code {
          value = "E-LOG-007"
        }

        var.update $reject_msg {
          value = "Notes can be up to 1,000 characters. (E-LOG-007)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $to == "") {
        var.update $reject_code {
          value = "E-LOG-001"
        }

        var.update $reject_msg {
          value = ($not_available ~ " (E-LOG-001)")
        }
      }
    }

    // A replayed tap is a success even if the state has since moved
    // on: the work it describes was already recorded.
    conditional {
      if ($is_duplicate) {
        var.update $reject_code {
          value = ""
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "LOG-1"
            step          : "record_event"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Task event refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $now_ms {
      value = now|to_int
    }

    // The first start is never moved. A reopened task was still
    // started when it was first started.
    var $next_started {
      value = $task.started_at
    }

    conditional {
      if ($input.event_type == "started" && ($task.started_at == null || $task.started_at == 0)) {
        var.update $next_started {
          value = $now_ms
        }
      }
    }

    var $next_completed {
      value = $task.completed_at
    }

    conditional {
      if ($input.event_type == "completed" || $input.event_type == "skipped") {
        var.update $next_completed {
          value = $now_ms
        }
      }
    }

    conditional {
      if ($input.event_type == "reopened") {
        var.update $next_completed {
          value = 0
        }
      }
    }

    conditional {
      if ($is_duplicate == false) {
        db.transaction {
          stack {
            db.add activity_log {
              data = {
                work_task_id        : $input.work_task_id
                work_item_id        : $task.work_item_id
                event_type          : $input.event_type
                performer_user_id   : $actor.user_id
                performer_agent_id  : 0
                occurred_at         : $now_ms
                reason_code         : $input.reason_code
                note                : $input.note
                source              : "manual"
                plan_publication_id : $publication_id
                publication_item_ref: $item_ref
                client_event_id     : $input.client_event_id
              }
            } as $row

            db.patch work_task {
              field_name = "id"
              field_value = $input.work_task_id
              data = {
                status      : $to
                started_at  : $next_started
                completed_at: $next_completed
                updated_at  : "now"
              }
            } as $patched
          }
        }

        // The job's cached status follows its tasks, every time.
        function.run "log/sync_job_status" {
          input = {work_item_id: $task.work_item_id}
        } as $job_sync

        function.run "ops/log_event" {
          input = {
            feature       : "LOG-1"
            step          : "record_event"
            outcome       : "success"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            message       : "Task event recorded."
            metadata      : {
            event_type: $input.event_type
            from      : $from
            to        : $to
            job_status: $job_sync.status
          }
          }
        }
      }
    }

    db.get work_task {
      field_name = "id"
      field_value = $input.work_task_id
    } as $final

    db.get work_item {
      field_name = "id"
      field_value = $task.work_item_id
    } as $final_job

    // US-LOG-1-04, stage half. Derived on the way out, outside the
    // duplicate branch, so a replayed tap gets the same answer as the
    // first one. The performer app needs this to say "stage finished"
    // without a second round trip.
    function.run "log/stage_progress" {
      input = {work_item_id: $task.work_item_id}
    } as $stage_progress

    var $this_stage {
      value = null
    }

    foreach ($stage_progress.stages) {
      each as $s {
        conditional {
          if ($s.stage_key == $task.stage_key) {
            var.update $this_stage {
              value = $s
            }
          }
        }
      }
    }
  }

  response = {
    work_task          : $final
    from               : $from
    to                 : $final.status
    job_status         : $final_job.status
    duplicate          : $is_duplicate
    publication        : {id: $publication_id, item_ref: $item_ref}
    stage              : $this_stage
    all_stages_complete: $stage_progress.all_complete
  }
}
