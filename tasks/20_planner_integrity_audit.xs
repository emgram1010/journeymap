// PLN-8 (US-PLN-8-03) — Nightly planner integrity audit.
//
// ⚠️ NOT PUSHED TO XANO. A recurring job is standing configuration,
// not a one-off action: once created it runs every night whether or
// not anyone is watching, so it needs the founder's go-ahead like the
// delete paths do. Everything it calls IS live and tested, so pushing
// it later is a single step with nothing left to verify in the logic.
//
// Schedule when approved: nightly, off-peak. `19_ops_integrity_audit`
// already exists for GOV-1's own checks, so pick a different hour
// rather than stacking two full-table sweeps on top of each other.
//
// IT NEVER WRITES TO A PLANNER TABLE. It reads, and it writes
// `event_log` rows. An audit that repaired things would hide the bug
// that caused the damage, and a nightly job is the worst possible
// place to put a silent repair.
//
// ONE EVENT PER ACCOUNT THAT HAS A PROBLEM, not one per violation: a
// single plan with a broken index could otherwise write hundreds of
// rows overnight and bury everything else on the Health page. The
// count and the first few ids go in `metadata`; the endpoint
// `GET planner/workspace/integrity` gives an admin the full list on
// demand.
//
// A clean night writes nothing at all. Silence is the success signal,
// which is what makes the Health page readable.
task "planner_integrity_audit" {
  schedule {
    // Placeholder — set when the founder approves the job.
    cron = "0 3 * * *"
    timezone = "UTC"
  }

  stack {
    db.query account {
      return = {type: "list"}
    } as $accounts

    var $checked {
      value = 0
    }

    var $dirty_accounts {
      value = 0
    }

    foreach ($accounts) {
      each as $acct {
        function.run "planner/integrity_audit" {
          input = {account_id: $acct.id}
        } as $audit

        var.update $checked {
          value = $checked + 1
        }

        // Branching on a field of the loop-produced result is the safe
        // form; branching on a var updated earlier in this iteration
        // would silently lose the writes (CLAUDE.md).
        conditional {
          if ($audit.clean == false) {
            var.update $dirty_accounts {
              value = $dirty_accounts + 1
            }

            function.run "ops/log_event" {
              input = {
                feature    : "PLN-8"
                step       : "nightly_integrity_audit"
                outcome    : "failure"
                severity   : "warn"
                account_id : $acct.id
                entity_type: "planner_workspace"
                error_code : "E-GOV-006"
                message    : "Nightly planner audit found integrity violations for this account."
                metadata   : {violation_count: $audit.violation_count, violations: $audit.violations}
              }
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature  : "PLN-8"
        step     : "nightly_integrity_audit"
        outcome  : "success"
        severity : "info"
        message  : "Nightly planner audit finished."
        metadata : {accounts_checked: $checked, accounts_with_violations: $dirty_accounts}
      }
    }
  }
}
