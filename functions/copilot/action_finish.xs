// COP-2 review fix — a tool reports how an action it was allowed to run ended. Contract for every tool that declares an act_type: after the gate lets it through, do the write, then call this with the gate's action_id and ok = true; if the write fails, call it with ok = false. An approved/edited item becomes executed or failed; a "told" item stays told on success and becomes failed on failure. Only the same account's items move, and only forward. action_id 0 (the gate stored nothing — e.g. a person, or "runs on its own") is a no-op. Never throws.
function "copilot/action_finish" {
  input {
    int action_id?
    int account_id?
    bool ok?
  }

  stack {
    db.query copilot_action {
      where = $db.copilot_action.id == $input.action_id && $input.action_id != 0
      return = {type: "single"}
      output = ["id", "account_id", "status", "action_type", "tool"]
    } as $act

    var $act_id {
      value = $act|get:"id":0
    }

    var $status {
      value = $act|get:"status":""
    }

    var $same_account {
      value = ($act_id != 0 && ($act|get:"account_id":0) == $input.account_id)
    }

    var $was_approved {
      value = ($status == "approved" || $status == "edited")
    }

    var $new_status {
      value = ""
    }

    conditional {
      if ($same_account == true && $was_approved == true && $input.ok == true) {
        var.update $new_status {
          value = "executed"
        }
      }

      elseif ($same_account == true && ($was_approved == true || $status == "told") && $input.ok != true) {
        var.update $new_status {
          value = "failed"
        }
      }
    }

    conditional {
      if ($new_status != "") {
        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: $new_status, executed_at: "now", updated_at: "now"}
        } as $_finished

        function.run "ops/log_event" {
          input = {
            feature    : "COP-2"
            step       : (($new_status == "executed") ? "action_executed" : "action_failed")
            outcome    : (($new_status == "executed") ? "success" : "failure")
            severity   : (($new_status == "executed") ? "info" : "warn")
            error_code : ""
            message    : (($new_status == "executed") ? "An approved copilot action was carried out." : "A copilot action failed while running; nothing more will happen without a new approval.")
            user_id    : 0
            account_id : $input.account_id
            entity_type: "copilot_action"
            entity_id  : $act_id
            metadata   : {action_type: ($act|get:"action_type":""), tool: ($act|get:"tool":"")}
          }
        } as $_fin_logged
      }
    }
  }

  response = {action_id: $act_id, status: (($new_status != "") ? $new_status : $status)}
}
