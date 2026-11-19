// COP-3 story 01 — an account admin sets up the copilot's own "playbook" business (decision D-2:
// one per account, never shared). Creates one journey architecture owned by the admin (so the
// admin can open and edit its maps like any other), marks it in copilot_home (unique per account,
// so a second setup is refused by the database, E-COP-044), and returns its id. The four starter
// maps (how to research, how to build maps, how to learn, how to ask for approval) are then made
// by the screen through the normal "create draft map" endpoint, with the owner, rather than
// invented in code (the epic: "the starter maps' content is written with the founder").
// Requires a copilot in the account first (E-COP-040).
query "copilot/home_create" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/home_create"
        entity_id    : 0
      }
    } as $admin_user

    db.query ai_identity {
      where = $db.ai_identity.account_id == $admin_user.account_id
      return = {type: "single"}
      output = ["id", "name"]
    } as $ident

    precondition (($ident|get:"id":0) != 0) {
      error_type = "notfound"
      error = "Your account doesn't have a copilot yet. An admin can create one on Manage users. (E-COP-040)"
    }

    db.query copilot_home {
      where = $db.copilot_home.account_id == $admin_user.account_id
      return = {type: "count"}
    } as $existing

    precondition ($existing == 0) {
      error_type = "inputerror"
      error = "The copilot already has its own business. (E-COP-044)"
    }

    var $home_arch_id {
      value = 0
    }

    var $created {
      value = false
    }

    try_catch {
      try {
        db.transaction {
          stack {
            db.add journey_architecture {
              enforce_hidden_fields = false
              data = {
                created_at : "now"
                updated_at : "now"
                title      : "Copilot's own: playbook"
                description: "The copilot's working methods, as maps you can read and improve. Shared by every business in this account."
                status     : "draft"
                account_id : $admin_user.account_id
                owner_user : $admin_user.id
              }
            } as $arch

            db.add copilot_home {
              data = {account_id: $admin_user.account_id, journey_architecture_id: $arch.id, created_by_user_id: $admin_user.id}
            } as $_home

            var.update $home_arch_id {
              value = $arch.id
            }

            var.update $created {
              value = true
            }
          }
        }
      }

      catch {
        var.update $created {
          value = false
        }
      }
    }

    precondition ($created == true) {
      error_type = "inputerror"
      error = "The copilot already has its own business. (E-COP-044)"
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-3"
        step       : "home_created"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The copilot's own business was set up."
        user_id    : $admin_user.id
        account_id : $admin_user.account_id
        entity_type: "journey_architecture"
        entity_id  : $home_arch_id
        metadata   : {}
      }
    } as $_logged
  }

  response = {journey_architecture_id: $home_arch_id}
  tags = ["cop-3"]
}
