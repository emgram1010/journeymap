// COP-6 story 01 — the Connections list for one business: every connection in the account's
// library, whether it is switched on for THIS business, when it last worked, whether it is failing,
// and whether a login is stored (yes/no only - the login itself is never read here, story 02).
// Account admins only; another account's business answers "not found" (E-COP-035).
query "copilot/connections" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int journey_architecture_id?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "copilot/connections", entity_id: $input.journey_architecture_id}
    } as $admin_user

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
      where = $db.copilot_connection.account_id == $admin_user.account_id
      sort = {copilot_connection.name: "asc"}
      return = {type: "list"}
      output = ["id", "key", "name", "description", "status"]
    } as $library

    db.query copilot_connection_switch {
      where = $db.copilot_connection_switch.journey_architecture_id == $input.journey_architecture_id && $db.copilot_connection_switch.account_id == $admin_user.account_id
      return = {type: "list"}
      output = ["connection_id", "is_on", "last_ok_at", "failing_since", "last_error_code"]
    } as $switches

    db.query copilot_connection_secret {
      where = $db.copilot_connection_secret.journey_architecture_id == $input.journey_architecture_id && $db.copilot_connection_secret.account_id == $admin_user.account_id
      return = {type: "list"}
      output = ["connection_id"]
    } as $logins

    // Keyed maps, keys prefixed so none is ever empty (CLAUDE.md). Pre-seeded per library row so a
    // variable-key |get never needs its default.
    var $sw_by {
      value = {}
    }

    var $login_by {
      value = {}
    }

    var $k {
      value = ""
    }

    foreach ($library) {
      each as $c {
        var.update $k {
          value = "c:" ~ ($c.id|to_text)
        }

        var.update $sw_by {
          value = $sw_by|set:$k:{is_on: false, last_ok_at: 0, failing_since: 0, last_error_code: ""}
        }

        var.update $login_by {
          value = $login_by|set:$k:false
        }
      }
    }

    foreach ($switches) {
      each as $s {
        var.update $k {
          value = "c:" ~ ($s.connection_id|to_text)
        }

        var.update $sw_by {
          value = $sw_by|set:$k:{is_on: $s.is_on, last_ok_at: $s.last_ok_at, failing_since: $s.failing_since, last_error_code: $s.last_error_code}
        }
      }
    }

    foreach ($logins) {
      each as $l {
        var.update $k {
          value = "c:" ~ ($l.connection_id|to_text)
        }

        var.update $login_by {
          value = $login_by|set:$k:true
        }
      }
    }

    var $rows {
      value = []
    }

    var $sw {
      value = {}
    }

    var $has_login {
      value = false
    }

    foreach ($library) {
      each as $c {
        var.update $k {
          value = "c:" ~ ($c.id|to_text)
        }

        var.update $sw {
          value = ($sw_by|get:$k:null) ?? {}
        }

        var.update $has_login {
          value = (($login_by|get:$k:null) ?? false) == true
        }

        array.push $rows {
          value = {
            id             : $c.id
            key            : $c.key
            name           : $c.name
            description    : $c.description
            status         : $c.status
            is_on          : (($sw.is_on ?? false) == true)
            has_login      : $has_login
            last_ok_at     : ($sw.last_ok_at ?? 0)
            failing_since  : ($sw.failing_since ?? 0)
            last_error_code: ($sw.last_error_code ?? "")
          }
        }
      }
    }
  }

  response = {journey_architecture_id: $input.journey_architecture_id, connections: $rows}
  tags = ["cop-6"]
}
