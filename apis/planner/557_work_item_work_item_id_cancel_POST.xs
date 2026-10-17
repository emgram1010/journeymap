// JOB-1 (US-JOB-1-05) — Cancel a job.
//
// CANCELLING LEAVES THE TASKS EXACTLY AS THEY ARE. Whatever was
// started, finished or blocked stays on the record — a cancelled job
// is history, not a mistake to be erased. What changes is that it
// drops out of scheduling and out of performer lists.
//
// Cancel is the planner's alternative to deleting a job, in the same
// way archiving is the alternative for a plan. There is no job delete
// at all once anything has been logged against it.
//
// IDEMPOTENT: cancelling an already-cancelled job succeeds and says
// so (E-JOB-005 is informational, not a failure). A second click, or
// a retried request, should not produce an error. Confirmed live —
// the second call returns 200 with `was_already_cancelled: true`.
query "work_item/{work_item_id}/cancel" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    var $was_already {
      value = ($job.status == "cancelled")
    }

    var $message {
      value = "Job cancelled."
    }

    conditional {
      if ($was_already == true) {
        var.update $message {
          value = "This job is already cancelled."
        }
      }
    }

    conditional {
      if ($was_already == false) {
        var $now_ms {
          value = now|to_int
        }

        db.patch work_item {
          field_name = "id"
          field_value = $input.work_item_id
          data = {status: "cancelled", finished_at: $now_ms, updated_at: "now"}
        } as $patched

        function.run "ops/log_event" {
          input = {
            feature       : "JOB-1"
            step          : "cancel_job"
            outcome       : "success"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            message       : "Job cancelled."
          }
        }
      }
    }

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $final
  }

  response = {
    work_item            : $final
    was_already_cancelled: $was_already
    message              : $message
  }
}
