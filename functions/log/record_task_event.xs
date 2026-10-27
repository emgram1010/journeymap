// EXC-1 (extraction before US-EXC-1-03) — THE ONE PLACE a task event is
// recorded: LOG-1's engine, moved verbatim out of endpoint 563 so the
// exception spawn can block a parent step (and leave a `note` on it)
// through exactly the same rules, writes and logging as a performer's
// tap. A copy would drift (LOG-1's house rule).
//
// Everything 563's header says still holds here: the only thing allowed
// to move work_task.status; a duplicate client_event_id is a success that
// returns the first result; the job status is re-derived after every
// event; refusal messages never show a raw status; the transition table
// is NOT here (log/next_status); the log row and the status move in ONE
// db.transaction.
//
// `soft` (default false): false = refusals RAISE exactly as 563 always
// did (same codes, same messages, same error types) — 563 calls it this
// way. true = refusals are RETURNED ({rejected, error_type, code,
// message}) and nothing is written; the spawn uses this so a refused
// "also block the parent" never fails the spawn (EXC-1 D-1). The
// `rejected` LOG-1 event is logged either way.
//
// `actor` is planner/resolve_actor's result: {user_id, account_id, role}.
// `source` is activity_log.source: manual (default) | ai | system.
function "log/record_task_event" {
  input {
    json actor
    int work_task_id filters=min:1
    text event_type filters=trim
    text reason_code? filters=trim
    text note? filters=trim
    text client_event_id filters=trim
    text correlation_id? filters=trim
    text source? filters=trim
    bool soft?
    // EXC-1: a NOTE the system writes about a fork (610's "Sent to … →
    // job #N"). Not a performer recording their own work, so the
    // assignment rule (E-LOG-003) does not apply to it. Ignored for every
    // other event type; 563 never sends it.
    bool system_note?
  }

  stack {
    var $actor {
      value = $input.actor
    }

    var $event_source {
      value = "manual"
    }

    conditional {
      if ($input.source == "ai" || $input.source == "system") {
        var.update $event_source {
          value = $input.source
        }
      }
    }

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

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    var $reject_type {
      value = "inputerror"
    }

    // E-LOG-003. Work scheduled to a named person is recorded by that
    // person, or by an account admin acting for them. UNASSIGNED WORK IS
    // NOT BLOCKED (see 563's history): where there is no assignment there
    // is nobody to deny, and account tenancy above still applies.
    var $assignment_ok {
      value = ($assigned_user == 0 || $assigned_user == $actor.user_id || $actor.role == "admin" || ($input.system_note == true && $input.event_type == "note"))
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

        var.update $reject_code {
          value = "E-LOG-003"
        }

        var.update $reject_msg {
          value = "This step isn't assigned to you. (E-LOG-003)"
        }

        var.update $reject_type {
          value = "accessdenied"
        }
      }
    }

    precondition ($assignment_ok || $input.soft == true) {
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

    // The transition table lives in log/next_status — ONE backend copy,
    // shared with the replay audit, mirrored by logModel.ts::canTransition.
    function.run "log/next_status" {
      input = {from: $from, event: $input.event_type}
    } as $trans

    var $to {
      value = $trans.to
    }

    var $not_available {
      value = $trans.message
    }

    var $reason_ok {
      value = ($input.reason_code == "waiting_on_someone" || $input.reason_code == "missing_information" || $input.reason_code == "something_went_wrong" || $input.reason_code == "other")
    }

    // 563 only ever saw these seven values (its input is an enum). The
    // spawn passes fixed values, but a function must not trust its caller.
    var $event_ok {
      value = ($input.event_type == "started" || $input.event_type == "completed" || $input.event_type == "blocked" || $input.event_type == "unblocked" || $input.event_type == "skipped" || $input.event_type == "reopened" || $input.event_type == "note")
    }

    conditional {
      if ($reject_code == "" && $event_ok == false) {
        var.update $reject_code {
          value = "E-LOG-001"
        }

        var.update $reject_msg {
          value = "That action isn't available for this step right now. (E-LOG-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.event_type == "blocked" && $input.reason_code == "") {
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

    // APP-2 (US-APP-2-07, D-3): a skip's reason is OPTIONAL, but if one
    // was sent it must be a real one.
    conditional {
      if ($reject_code == "" && $input.event_type == "skipped" && $input.reason_code != "" && $reason_ok == false) {
        var.update $reject_code {
          value = "E-LOG-005"
        }

        var.update $reject_msg {
          value = "Pick one of the listed reasons. (E-LOG-005)"
        }
      }
    }

    // APP-2 (US-APP-2-02, -06): the server is the one that enforces a
    // non-empty note, whatever the Step screen's box does.
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

    // A replayed tap is a success even if the state has since moved on:
    // the work it describes was already recorded. (E-LOG-003 is not
    // cleared — a duplicate does not grant access.)
    conditional {
      if ($is_duplicate && $reject_code != "E-LOG-003") {
        var.update $reject_code {
          value = ""
        }
      }
    }

    conditional {
      if ($reject_code != "" && $reject_code != "E-LOG-003") {
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

    precondition ($reject_code == "" || $input.soft == true) {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $now_ms {
      value = now|to_int
    }

    // The first start is never moved. A reopened task was still started
    // when it was first started.
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

    var $will_write {
      value = ($reject_code == "" && $is_duplicate == false)
    }

    conditional {
      if ($will_write) {
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
                source              : $event_source
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
    // duplicate branch, so a replayed tap gets the same answer.
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
    rejected           : ($reject_code != "")
    error_type         : $reject_type
    code               : $reject_code
    message            : $reject_msg
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
