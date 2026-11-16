// COP-6 story 01 — switch one connection on or off for ONE business. Account admins only, never an
// AI identity. Governance: a connection cannot be switched ON without a working login for this
// business (E-COP-062) - so until logins can be stored (story 02, decision pending), switching on
// is refused and only "off" is accepted. Switching off keeps the row and its history.
// Refusals: E-COP-025 (AI), E-COP-035 (business not in this account), E-COP-065 (connection not
// in this account, or retired), E-COP-062 (no working login).
query "copilot/connection_switch" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int journey_architecture_id?
    int connection_id?
    bool is_on?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "copilot/connection_switch", entity_id: $input.journey_architecture_id}
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
      return = {type: "count"}
    } as $logins

    precondition ($input.is_on == false || $logins > 0) {
      error_type = "inputerror"
      error = "That connection has no working login for this business yet. (E-COP-062)"
    }

    db.query copilot_connection_switch {
      where = $db.copilot_connection_switch.journey_architecture_id == $input.journey_architecture_id && $db.copilot_connection_switch.connection_id == $conn_id
      return = {type: "single"}
      output = ["id", "is_on"]
    } as $existing

    var $existing_id {
      value = ($existing|get:"id":0) ?? 0
    }

    var $was_on {
      value = (($existing|get:"is_on":false) ?? false) == true
    }

    var $want_on {
      value = ($input.is_on == true)
    }

    conditional {
      if ($existing_id == 0) {
        db.add copilot_connection_switch {
          data = {account_id: $admin_user.account_id, journey_architecture_id: $input.journey_architecture_id, connection_id: $conn_id, is_on: $want_on, updated_by_user_id: $auth.id, updated_at: "now"}
        } as $_added
      }

      else {
        db.patch copilot_connection_switch {
          field_name = "id"
          field_value = $existing_id
          data = {is_on: $want_on, updated_by_user_id: $auth.id, updated_at: "now"}
        } as $_patched
      }
    }

    var $step {
      value = (($want_on == true) ? "connection_switched_on" : "connection_switched_off")
    }

    function.run "ops/log_event" {
      input = {feature: "COP-6", step: $step, outcome: "success", severity: "info", error_code: "", message: "A connection was switched for a business.", user_id: $auth.id, account_id: $admin_user.account_id, entity_type: "copilot_connection", entity_id: $conn_id, metadata: {journey_architecture_id: $input.journey_architecture_id, from: $was_on, to: $want_on}}
    } as $_logged
  }

  response = {journey_architecture_id: $input.journey_architecture_id, connection_id: $conn_id, is_on: $want_on}
  tags = ["cop-6"]
}
