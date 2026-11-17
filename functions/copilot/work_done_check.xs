// COP-8 story 01 — "has the copilot done any work on this task?" The one place the rule lives; record_my_task_event calls it, before the gate, when the event is "completed". An AI identity may complete its own task only if, since the task started (or, if it never started, since the current ticket was made), it made at least one call to another tool that the gate allowed. Read from tool_call_log, which only the gate writes. A call that only reads still counts. The bookkeeping tools (record_my_task_event, list_my_tasks) do not. A person is never checked. A task outside the caller's account is not judged here (the tool's own checks answer "Task not found"). If anything in the check fails, the answer is "not ok": it fails closed. Never throws. Logs a rejected (or failure) event with E-COP-075. The ticket is never logged or returned.
function "copilot/work_done_check" {
  input {
    text ticket? filters=trim
    int work_task_id?
  }

  stack {
    var $applies {
      value = false
    }

    var $ok {
      value = true
    }

    var $failed {
      value = false
    }

    var $user_id {
      value = 0
    }

    var $account_id {
      value = 0
    }

    var $window_start {
      value = 0
    }

    var $window_from {
      value = ""
    }

    var $calls {
      value = 0
    }

    var $bookkeeping {
      value = ["record_my_task_event", "list_my_tasks"]
    }

    try_catch {
      try {
        function.run "usr/tool_caller" {
          input = {ticket: $input.ticket}
        } as $caller

        var.update $user_id {
          value = $caller.user_id ?? 0
        }

        var.update $account_id {
          value = $caller.account_id ?? 0
        }

        // A caller the gate will refuse anyway is left to the gate.
        conditional {
          if ($caller.allowed == true && $user_id != 0) {
            function.run "copilot/identity_for_user" {
              input = {user_id: $user_id}
            } as $ai

            conditional {
              if ($ai.is_ai == true) {
                db.query work_task {
                  where = $db.work_task.id == $input.work_task_id
                  return = {type: "single"}
                  output = ["id", "work_item_id", "started_at"]
                } as $task

                var $job_id {
                  value = ($task|get:"work_item_id":0) ?? 0
                }

                db.query work_item {
                  where = $db.work_item.id == $job_id && $job_id != 0 && $db.work_item.account_id == $account_id
                  return = {type: "count"}
                } as $in_account

                conditional {
                  if ($in_account > 0) {
                    var.update $applies {
                      value = true
                    }

                    // started_at is a real epoch-ms timestamp when set (never legitimately 0), so
                    // the loose != null / != 0 pair is safe here (CLAUDE.md).
                    var $started {
                      value = ($task|get:"started_at":0) ?? 0
                    }

                    db.query tool_run_ticket {
                      where = $db.tool_run_ticket.ticket == $input.ticket
                      return = {type: "single"}
                      output = ["id", "created_at"]
                    } as $ticket_row

                    var $ticket_made {
                      value = ($ticket_row|get:"created_at":0) ?? 0
                    }

                    var.update $window_start {
                      value = $ticket_made
                    }

                    var.update $window_from {
                      value = "ticket"
                    }

                    conditional {
                      if ($started != null && $started != 0) {
                        var.update $window_start {
                          value = $started
                        }

                        var.update $window_from {
                          value = "started_at"
                        }
                      }
                    }

                    var $win {
                      value = $window_start
                    }

                    var $skip_tools {
                      value = $bookkeeping
                    }

                    db.query tool_call_log {
                      where = $db.tool_call_log.user_id == $user_id && $db.tool_call_log.verdict == "allowed" && ($db.tool_call_log.tool not in $skip_tools) && $db.tool_call_log.created_at >= $win
                      return = {type: "count"}
                    } as $allowed_calls

                    var.update $calls {
                      value = $allowed_calls
                    }

                    // No window at all (no start, no ticket row) cannot be judged: refuse.
                    var.update $ok {
                      value = ($window_start != 0 && $allowed_calls > 0)
                    }
                  }
                }
              }
            }
          }
        }
      }

      catch {
        var.update $failed {
          value = true
        }

        var.update $ok {
          value = false
        }
      }
    }

    conditional {
      if ($ok == false && $failed == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-8"
            step       : "work_done_check"
            outcome    : "rejected"
            severity   : "info"
            error_code : "E-COP-075"
            message    : "The copilot tried to complete its own task without any other allowed tool call since the task started."
            user_id    : $user_id
            account_id : $account_id
            entity_type: "work_task"
            entity_id  : $input.work_task_id
            metadata   : {window_from: $window_from, window_start: $window_start, allowed_calls: $calls}
          }
        } as $_rejected_logged
      }

      elseif ($ok == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-8"
            step       : "work_done_check"
            outcome    : "failure"
            severity   : "error"
            error_code : "E-COP-075"
            message    : "The work-done check could not run, so the copilot's completion was refused (fails closed)."
            user_id    : $user_id
            account_id : $account_id
            entity_type: "work_task"
            entity_id  : $input.work_task_id
            metadata   : {window_from: $window_from}
          }
        } as $_failure_logged
      }
    }
  }

  response = {
    ok           : $ok
    applies      : $applies
    failed       : $failed
    allowed_calls: $calls
    window_from  : $window_from
  }
}
