// COP-6 story 01 - THE one answer to "may the copilot use this connection in this business right now?". The connection must be in the caller's account and available, switched on for THIS business (only the pinned business's row is read - one business's connection never serves another), and have a login. Never throws: returns ok + reason ("not_found", "off", "no_login") + code + message; the calling tool refuses. No connection tool exists yet (the first connection is on hold), so this is called by nothing until one is built.
function "copilot/connection_reachable" {
  input {
    int account_id?
    int architecture_id?
    text connection_key? filters=trim|lower
  }

  stack {
    db.query copilot_connection {
      where = $db.copilot_connection.account_id == $input.account_id && $db.copilot_connection.key == $input.connection_key && $db.copilot_connection.status == "available" && $input.account_id != 0
      return = {type: "single"}
      output = ["id", "name"]
    } as $conn

    var $conn_id {
      value = ($conn|get:"id":0) ?? 0
    }

    db.query copilot_connection_switch {
      where = $db.copilot_connection_switch.journey_architecture_id == $input.architecture_id && $db.copilot_connection_switch.connection_id == $conn_id && $db.copilot_connection_switch.account_id == $input.account_id && $conn_id != 0 && $input.architecture_id != 0
      return = {type: "single"}
      output = ["id", "is_on"]
    } as $sw

    var $is_on {
      value = (($sw|get:"is_on":false) ?? false) == true
    }

    db.query copilot_connection_secret {
      where = $db.copilot_connection_secret.journey_architecture_id == $input.architecture_id && $db.copilot_connection_secret.connection_id == $conn_id && $conn_id != 0
      return = {type: "count"}
    } as $logins

    var $reason {
      value = ""
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    conditional {
      if ($conn_id == 0) {
        var.update $reason {
          value = "not_found"
        }

        var.update $code {
          value = "E-COP-065"
        }

        var.update $message {
          value = "There is no connection with that name in this account. (E-COP-065)"
        }
      }

      elseif ($is_on == false) {
        var.update $reason {
          value = "off"
        }

        var.update $code {
          value = "E-COP-060"
        }

        var.update $message {
          value = "That connection is not switched on for this business. The owner can switch it on under Connections. (E-COP-060)"
        }
      }

      elseif ($logins == 0) {
        var.update $reason {
          value = "no_login"
        }

        var.update $code {
          value = "E-COP-062"
        }

        var.update $message {
          value = "That connection has no working login for this business yet. (E-COP-062)"
        }
      }
    }
  }

  response = {ok: ($reason == ""), reason: $reason, code: $code, message: $message, connection_id: $conn_id}
}
