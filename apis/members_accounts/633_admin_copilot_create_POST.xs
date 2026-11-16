// COP-1 story 01 (2026-11-15) — an account admin creates the account's copilot.
// The copilot is a real user row (role member) marked by ai_identity, so grants, switch-off and
// the audit trail apply to it unchanged. It gets the Intelligent Layer only. Its email uses the
// reserved .invalid domain and its password is random and never shown: it cannot sign in, reset
// by email or receive a magic link. One per account, enforced by unique indexes (account_id on
// ai_identity, email on user) inside one transaction — not by a pre-check.
query "admin/copilot_create" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // Display name. Defaults to "Copilot".
    text name? filters=trim
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/copilot_create"
      }
    } as $admin_user

    var $account_id {
      value = $admin_user.account_id
    }

    precondition ($account_id != 0) {
      error_type = "accessdenied"
      error = "Your user is not in an account yet, so it cannot have a copilot. (E-COP-010)"
    }

    var $display {
      value = "Copilot"
    }

    conditional {
      if ($input.name != "") {
        var.update $display {
          value = $input.name
        }
      }
    }

    var $email {
      value = "copilot+a" ~ ($account_id|to_text) ~ "@ai.emgram.invalid"
    }

    security.create_uuid as $pw_a

    security.create_uuid as $pw_b

    var $password {
      value = "Ai1-" ~ $pw_a ~ $pw_b
    }

    var $now_ms {
      value = now|to_int
    }

    var $created_id {
      value = 0
    }

    var $failed {
      value = false
    }

    var $fail_msg {
      value = ""
    }

    try_catch {
      try {
        db.transaction {
          stack {
            db.add user {
              enforce_hidden_fields = false
              data = {
                created_at: "now"
                name      : $display
                email     : $email
                password  : $password
                role      : "member"
                account_id: $account_id
              }
            } as $new_user

            db.add ai_identity {
              data = {
                updated_at        : "now"
                user_id           : $new_user.id
                account_id        : $account_id
                name              : $display
                daily_cap         : 500
                created_by_user_id: $admin_user.id
              }
            } as $new_identity

            db.add user_module_access {
              data = {
                user_id           : $new_user.id
                account_id        : $account_id
                module            : "intelligence"
                granted           : true
                granted_by_user_id: $admin_user.id
                granted_at        : $now_ms
                revoked_by_user_id: 0
                revoked_at        : 0
              }
            } as $new_grant
          }
        }

        var.update $created_id {
          value = $new_user.id
        }
      }

      catch {
        var.update $failed {
          value = true
        }

        // Read the caught error whole first (reading a field straight off $error is unreliable).
        var $caught {
          value = $error
        }

        var.update $fail_msg {
          value = ($caught|get:"message":"") ?? ""
        }
      }
    }

    db.query ai_identity {
      where = $db.ai_identity.account_id == $account_id
      return = {type: "count"}
    } as $existing

    var $already_had_one {
      value = ($failed == true && $existing > 0)
    }

    var $other_failure {
      value = ($failed == true && $existing == 0)
    }

    precondition ($already_had_one == false) {
      error_type = "inputerror"
      error = "This account already has a copilot. Switch it off or rename it instead. (E-COP-006)"
    }

    // Final review follow-up (2026-11-16): the database's own words go to the event log for
    // support, never to the person's screen.
    conditional {
      if ($other_failure == true) {
        function.run "ops/log_event" {
          input = {feature: "COP-1", step: "copilot_create", outcome: "failure", severity: "error", error_code: "E-COP-007", message: "Creating the copilot failed; nothing was saved.", user_id: $admin_user.id, account_id: $account_id, entity_type: "account", entity_id: $account_id, metadata: {detail: $fail_msg}}
        } as $_fail_logged
      }
    }

    precondition ($other_failure == false) {
      error_type = "inputerror"
      error = "We could not create the copilot. Nothing was saved. (E-COP-007)"
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-1"
        step       : "copilot_create"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "Copilot created for this account."
        user_id    : $admin_user.id
        account_id : $account_id
        entity_type: "user"
        entity_id  : $created_id
        metadata   : {copilot_user_id: $created_id}
      }
    } as $_logged
  }

  response = {
    user_id   : $created_id
    name      : $display
    account_id: $account_id
    daily_cap : 500
    modules   : ["intelligence"]
  }
}
