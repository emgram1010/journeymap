// PLN-3 / P3A-1 (US-P3A-1-02) — "Has anything actually happened on this
// plan yet?" This is the single gate that decides whether a plan may be
// deleted or must be archived.
//
// IT CURRENTLY ALWAYS ANSWERS "no history". That is correct today and
// wrong later, so read this before trusting it:
//
// The three things that count as history all live in tables that do not
// exist yet — `work_item` (JOB-1), `plan_publication` (LIVE-1) and
// `activity_log` (LOG-1). Until those are built, no plan CAN have
// history, so "no" is the true answer and delete behaves exactly as
// PLN-3 specifies.
//
// It exists as its own function anyway so the call site in the delete
// endpoint is already correct. When JOB-1, LIVE-1 and LOG-1 land, each
// adds its own count here and nothing else in the planner changes.
//
// TODO(JOB-1):  count work_item where workspace_id = $input.workspace_id
// TODO(LIVE-1): count plan_publication via that plan's timelines
// TODO(LOG-1):  count activity_log rows for that plan's work
function "planner/workspace_has_history" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    var $job_count {
      value = 0
    }

    var $publication_count {
      value = 0
    }

    var $log_count {
      value = 0
    }

    var $total {
      value = $job_count + $publication_count + $log_count
    }
  }

  response = {
    has_history      : ($total > 0)
    job_count        : $job_count
    publication_count: $publication_count
    log_count        : $log_count
    checked          : ["work_item (JOB-1, not built)", "plan_publication (LIVE-1, not built)", "activity_log (LOG-1, not built)"]
  }
}
