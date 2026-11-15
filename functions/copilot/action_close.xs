// Final Fable review R1 — the last line of every copilot tool that declares an action type. The tool runs its own checks and its write inside a try_catch and hands whatever was caught to this function (null when nothing failed). It tells the approval list how the action ended (copilot/action_finish: an approved item becomes executed or failed; a "told" item stays told, or becomes failed) and then passes the tool's own error on unchanged, with its own kind (access denied, not found, anything else as an input error). One place, so no tool copies this. action_id 0 (a person, or a level that stores nothing) only passes the error on. The error text is the tool's own; nothing is logged here.
function "copilot/action_close" {
  input {
    int action_id?
    int account_id?
    json error?
  }

  stack {
    var $err {
      value = $input.error ?? {}
    }

    var $err_code {
      value = ($err|get:"code":"") ?? ""
    }

    var $err_message {
      value = ($err|get:"message":"") ?? ""
    }

    var $failed {
      value = ($err_code != "" || $err_message != "")
    }

    var $ok {
      value = ($failed == false)
    }

    function.run "copilot/action_finish" {
      input = {action_id: $input.action_id, account_id: $input.account_id, ok: $ok}
    } as $finished

    conditional {
      if ($failed == true && $err_message == "") {
        var.update $err_message {
          value = "That did not work."
        }
      }
    }

    var $is_denied {
      value = ($failed == true && $err_code == "ERROR_CODE_ACCESS_DENIED")
    }

    var $is_missing {
      value = ($failed == true && $err_code == "ERROR_CODE_NOT_FOUND")
    }

    precondition ($is_denied == false) {
      error_type = "accessdenied"
      error = $err_message
    }

    precondition ($is_missing == false) {
      error_type = "notfound"
      error = $err_message
    }

    precondition ($failed == false) {
      error_type = "inputerror"
      error = $err_message
    }
  }

  response = {action_id: $input.action_id, status: ($finished|get:"status":"")}
}
