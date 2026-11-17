// R17 (2026-11-16) - keep copilot_run from growing for ever (24 rows a day per switched-on business). Nightly, from task 19 (the plan allows 10 tasks and all are used). Removes "nothing to do" and "skipped" rows older than 14 days - the runs screen only ever loads 14 days - and "finished" / "failed" rows older than 90 days. Never touches a "running" row (that is the live lock). Recent rows stay, so the "three failures today" stop and the "nothing changed since last time" check are unaffected. Logs one success event with both counts.
function "copilot/prune_runs" {
  input {
  }

  stack {
    // Computed into vars first: a where clause cannot call filters (CLAUDE.md).
    var $quiet_cut {
      value = now|transform_timestamp:"14 days ago":"UTC"
    }

    var $old_cut {
      value = now|transform_timestamp:"90 days ago":"UTC"
    }

    db.query copilot_run {
      where = ($db.copilot_run.status == "nothing_to_do" || $db.copilot_run.status == "skipped") && $db.copilot_run.created_at < $quiet_cut
      return = {type: "list"}
      output = ["id"]
    } as $quiet

    db.query copilot_run {
      where = ($db.copilot_run.status == "finished" || $db.copilot_run.status == "failed") && $db.copilot_run.created_at < $old_cut
      return = {type: "list"}
      output = ["id"]
    } as $old

    // db.del removes only the first match, so delete each row by id.
    foreach ($quiet) {
      each as $q {
        db.del copilot_run {
          field_name = "id"
          field_value = $q.id
        }
      }
    }

    foreach ($old) {
      each as $o {
        db.del copilot_run {
          field_name = "id"
          field_value = $o.id
        }
      }
    }

    var $quiet_n {
      value = $quiet|count
    }

    var $old_n {
      value = $old|count
    }

    var $msg {
      value = "Pruned copilot run history: " ~ ($quiet_n|to_text) ~ " quiet row(s) older than 14 days, " ~ ($old_n|to_text) ~ " finished or failed row(s) older than 90 days."
    }

    function.run "ops/log_event" {
      input = {feature: "COP-5", step: "prune_runs", outcome: "success", severity: "info", user_id: 0, account_id: 0, entity_type: "copilot_run", entity_id: 0, correlation_id: "", error_code: "", message: $msg, metadata: {quiet_deleted: $quiet_n, old_deleted: $old_n}}
    } as $_logged
  }

  response = {quiet_deleted: $quiet_n, old_deleted: $old_n}
}
