// COP-6 story 02 - set, replace or remove the login for one connection in ONE business. Founder decision 2026-11-16: logins are encrypted in Xano (copilot/login_seal; the key is the COPILOT_SECRET_KEY environment variable, never in the database). The login is WRITE-ONLY: no response, screen, tool, log or event ever carries it - the input is marked sensitive so request history masks it, and the response says only whether a login is stored. Replacing overwrites the sealed value in place, so the old login stops working at once. Removing deletes the row and switches the connection off for this business in the same transaction. Every change is logged without the value. Account admins only, never an AI identity.
// Refusals: E-COP-025 (AI), E-COP-035 (business not in this account), E-COP-065 (connection not in this account, or retired), E-COP-068 (empty or too long), E-COP-067 (the server key is not set up - nothing is stored).
query "copilot/connection_login" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int journey_architecture_id?
    int connection_id?
    text login? {
      sensitive = true
    }

    bool remove?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "copilot/connection_login", entity_id: $input.journey_architecture_id}
    } as $admin_user

    function.run "copilot/identity_for_user" {
      input = {user_id: $auth.id}
    } as $me_ai

    precondition ($me_ai.is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can do this. It is ready for the owner to do themselves. (E-COP-025)"
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    var $arch_ok {
      value = ($input.journey_architecture_id != 0 && ($arch|get:"account_id":0) == $admin_user.account_id)
    }

    precondition ($arch_ok) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    db.query copilot_connection {
      where = $db.copilot_connection.id == $input.connection_id && $db.copilot_connection.account_id == $admin_user.account_id && $db.copilot_connection.status == "available"
      return = {type: "single"}
      output = ["id", "key"]
    } as $conn

    var $conn_id {
      value = ($conn|get:"id":0) ?? 0
    }

    precondition ($conn_id != 0) {
      error_type = "notfound"
      error = "There is no connection with that name in this account. (E-COP-065)"
    }

    db.query copilot_connection_secret {
      where = $db.copilot_connection_secret.journey_architecture_id == $input.journey_architecture_id && $db.copilot_connection_secret.connection_id == $conn_id
      return = {type: "single"}
      output = ["id"]
    } as $existing

    var $existing_id {
      value = ($existing|get:"id":0) ?? 0
    }

    var $removing {
      value = ($input.remove == true)
    }

    var $login_len {
      value = (($input.login ?? "")|trim)|strlen
    }

    var $login_ok {
      value = ($removing == true) || ($login_len >= 1 && (($input.login ?? "")|strlen) <= 4000)
    }

    precondition ($login_ok) {
      error_type = "inputerror"
      error = "A login can't be empty, and can be up to 4000 characters. (E-COP-068)"
    }

    var $sealed {
      value = ""
    }

    conditional {
      if ($removing == false) {
        function.run "copilot/login_seal" {
          input = {value: $input.login}
        } as $seal

        var.update $sealed {
          value = $seal.sealed
        }
      }
    }

    var $key_missing {
      value = ($removing == false) && ($sealed == "")
    }

    conditional {
      if ($key_missing == true) {
        function.run "ops/log_event" {
          input = {feature: "COP-6", step: "connection_login_set", outcome: "failure", severity: "error", error_code: "E-COP-067", message: "A login could not be saved: the server's protection key is not set up. Nothing was stored.", user_id: $auth.id, account_id: $admin_user.account_id, entity_type: "copilot_connection", entity_id: $conn_id, metadata: {journey_architecture_id: $input.journey_architecture_id}}
        } as $_failed
      }
    }

    precondition ($key_missing == false) {
      error_type = "inputerror"
      error = "Logins can't be saved yet: the server's protection key isn't set up. Nothing was stored. (E-COP-067)"
    }

    var $step {
      value = "connection_login_replaced"
    }

    conditional {
      if ($removing == true) {
        var.update $step {
          value = "connection_login_removed"
        }
      }

      elseif ($existing_id == 0) {
        var.update $step {
          value = "connection_login_set"
        }
      }
    }

    db.transaction {
      stack {
        conditional {
          if ($removing == true && $existing_id != 0) {
            db.del copilot_connection_secret {
              field_name = "id"
              field_value = $existing_id
            }

            db.query copilot_connection_switch {
              where = $db.copilot_connection_switch.journey_architecture_id == $input.journey_architecture_id && $db.copilot_connection_switch.connection_id == $conn_id
              return = {type: "single"}
              output = ["id"]
            } as $sw

            var $sw_id {
              value = ($sw|get:"id":0) ?? 0
            }

            conditional {
              if ($sw_id != 0) {
                db.patch copilot_connection_switch {
                  field_name = "id"
                  field_value = $sw_id
                  data = {is_on: false, updated_by_user_id: $auth.id, updated_at: "now"}
                } as $_off
              }
            }
          }

          elseif ($removing == false && $existing_id == 0) {
            db.add copilot_connection_secret {
              data = {account_id: $admin_user.account_id, journey_architecture_id: $input.journey_architecture_id, connection_id: $conn_id, secret_value: $sealed, set_by_user_id: $auth.id, updated_at: "now"}
            } as $_added
          }

          elseif ($removing == false) {
            db.patch copilot_connection_secret {
              field_name = "id"
              field_value = $existing_id
              data = {secret_value: $sealed, set_by_user_id: $auth.id, updated_at: "now"}
            } as $_replaced
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {feature: "COP-6", step: $step, outcome: "success", severity: "info", error_code: "", message: "A connection login was changed for a business. The value is never logged.", user_id: $auth.id, account_id: $admin_user.account_id, entity_type: "copilot_connection", entity_id: $conn_id, metadata: {journey_architecture_id: $input.journey_architecture_id, had_login: ($existing_id != 0)}}
    } as $_logged
  }

  response = {journey_architecture_id: $input.journey_architecture_id, connection_id: $conn_id, has_login: ($removing == false)}
  tags = ["cop-6"]
}
