// COP-9 story 05 — the nightly trial review for every account that has a copilot (copilot_home). Runs the
// ONE trial rule (copilot/skill_trial_review) per account; one failing account is logged and does not
// stop the others. Called by the nightly ops_integrity_audit task (task 19): the Xano plan allows 10
// scheduled tasks and all 10 are in use, so this rides on the existing nightly run at 04:00 UTC.
function "copilot/skill_trial_review_all" {
  input {
  }

  stack {
    db.query copilot_home {
      return = {type: "list"}
      output = ["account_id"]
    } as $homes

    var $reviewed {
      value = 0
    }

    var $failed {
      value = 0
    }

    foreach ($homes) {
      each as $h {
        try_catch {
          try {
            function.run "copilot/skill_trial_review" {
              input = {account_id: $h.account_id, dry_run: false}
            } as $_one

            var.update $reviewed {
              value = $reviewed + 1
            }
          }

          catch {
            var.update $failed {
              value = $failed + 1
            }

            function.run "ops/log_event" {
              input = {
                feature    : "COP-9"
                step       : "skill_trial_review"
                outcome    : "failure"
                severity   : "warn"
                error_code : ""
                message    : "The nightly trial review failed for one account; the others carried on."
                user_id    : 0
                account_id : $h.account_id
                entity_type: "account"
                entity_id  : $h.account_id
                metadata   : {}
              }
            } as $_fail_logged
          }
        }
      }
    }
  }

  response = {accounts_reviewed: $reviewed, accounts_failed: $failed}
}
