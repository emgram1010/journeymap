// COP-2 story 06 — remind, then expire; never approve by silence (decision D-5). A waiting action older than 24 hours gets one reminder (reminded_at set, one Health event); older than 72 hours it becomes "expired" and can never run. account_id 0 = every account (the scheduled task); otherwise one account (the Approvals screen runs it before listing, so a stale item never shows as approvable even if the task is late). Cutoffs are computed into vars first (a where clause cannot call filters). Each row is patched by id (a patch by a non-unique field touches one row only).
function "copilot/expire_waiting" {
  input {
    int account_id?
  }

  stack {
    var $now_ms {
      value = now|to_int
    }

    var $remind_cutoff {
      value = $now_ms - 86400000
    }

    var $expire_cutoff {
      value = $now_ms - 259200000
    }

    var $all {
      value = ($input.account_id == 0)
    }

    db.query copilot_action {
      where = $db.copilot_action.status == "waiting" && $db.copilot_action.created_at < $expire_cutoff && (($all == true) || ($db.copilot_action.account_id == $input.account_id))
      return = {type: "list"}
      output = ["id", "account_id", "action_type", "tool"]
    } as $to_expire

    foreach ($to_expire) {
      each as $x {
        db.patch copilot_action {
          field_name = "id"
          field_value = $x.id
          data = {status: "expired", updated_at: "now"}
        } as $_expired

        function.run "ops/log_event" {
          input = {
            feature    : "COP-2"
            step       : "action_expired"
            outcome    : "rejected"
            severity   : "info"
            error_code : "E-COP-024"
            message    : "A copilot action waited 72 hours without an answer and expired. It was not carried out."
            user_id    : 0
            account_id : $x.account_id
            entity_type: "copilot_action"
            entity_id  : $x.id
            metadata   : {action_type: $x.action_type, tool: $x.tool}
          }
        } as $_exp_logged
      }
    }

    // An untouched timestamp may be stored as null or 0; both mean "never reminded". In a where
    // clause (SQL) those are different values, so both are tested.
    db.query copilot_action {
      where = $db.copilot_action.status == "waiting" && $db.copilot_action.created_at < $remind_cutoff && ($db.copilot_action.reminded_at == null || $db.copilot_action.reminded_at == 0) && (($all == true) || ($db.copilot_action.account_id == $input.account_id))
      return = {type: "list"}
      output = ["id", "account_id", "action_type"]
    } as $to_remind

    foreach ($to_remind) {
      each as $r {
        db.patch copilot_action {
          field_name = "id"
          field_value = $r.id
          data = {reminded_at: "now", updated_at: "now"}
        } as $_reminded

        function.run "ops/log_event" {
          input = {
            feature    : "COP-2"
            step       : "action_reminder"
            outcome    : "success"
            severity   : "info"
            error_code : ""
            message    : "A copilot action has waited over 24 hours for the owner."
            user_id    : 0
            account_id : $r.account_id
            entity_type: "copilot_action"
            entity_id  : $r.id
            metadata   : {action_type: $r.action_type}
          }
        } as $_rem_logged
      }
    }
  }

  response = {expired: $to_expire|count, reminded: $to_remind|count}
}
