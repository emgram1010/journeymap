// COP-6 story 02 - SERVER ONLY. Opens the stored login for one connection in ONE business so a connection tool can attach it to its outgoing request. Never call this from an endpoint response, a tool output, a log or a chat message: the copilot must never see the value. Reads only the row for this exact business + connection (logins are never shared). Returns ok=false + E-COP-062 when there is no login, E-COP-067 when the server key is missing, and E-COP-069 when the stored value cannot be opened (the key was changed, or the value was tampered with) - the login must then be saved again.
function "copilot/login_open" {
  input {
    int architecture_id?
    int connection_id?
  }

  stack {
    db.query copilot_connection_secret {
      where = $db.copilot_connection_secret.journey_architecture_id == $input.architecture_id && $db.copilot_connection_secret.connection_id == $input.connection_id && $input.architecture_id != 0 && $input.connection_id != 0
      return = {type: "single"}
      output = ["id", "secret_value"]
    } as $row

    var $sealed {
      value = ($row|get:"secret_value":"") ?? ""
    }

    var $key {
      value = $env.COPILOT_SECRET_KEY ?? ""
    }

    var $key_ok {
      value = ($key|strlen) >= 32
    }

    var $value {
      value = ""
    }

    var $code {
      value = ""
    }

    conditional {
      if ($sealed == "") {
        var.update $code {
          value = "E-COP-062"
        }
      }

      elseif ($key_ok == false) {
        var.update $code {
          value = "E-COP-067"
        }
      }

      else {
        try_catch {
          try {
            var.update $value {
              value = $sealed|jwe_decode:{}:$key:"A256KW":"A256GCM"
            }
          }

          catch {
            var.update $code {
              value = "E-COP-069"
            }
          }
        }
      }
    }

    conditional {
      if ($code == "" && ($value ?? "") == "") {
        var.update $code {
          value = "E-COP-069"
        }
      }
    }
  }

  response = {ok: ($code == ""), code: $code, value: (($code == "") ? $value : "")}
}
