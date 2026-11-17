// GOV-1 (US-GOV-1-05) + OBS-1 (US-OBS-1-05, the half deferred to GOV-1)
// — Daily at 04:00 UTC: run the integrity audit and log one event with
// the result, so the Health page shows data problems the same way it
// shows broken requests.
//
// Clean data logs a `success` event (the audit ran, found nothing).
// Findings log a `failure` event carrying E-GOV-006 and the per-check
// counts, which puts it in the Health page's failure count and issue
// list with an owner and a suggested fix.
//
// 04:00 UTC deliberately, so it does not collide with the 03:00 prune
// tasks. Pushed to workspace 1 as task id 19.
task ops_integrity_audit {
  stack {
    function.run "ops/audit_integrity" {
      input = {max_detail: 1}
      description = "max_detail 1 keeps the logged event small; the counts are always complete, and the full list is available on demand from ops/audit_integrity."
    } as $audit

    conditional {
      if ($audit.finding_count > 0) {
        var $message {
          value = "Integrity audit found " ~ ($audit.finding_count|to_text) ~ " record(s) pointing at something that no longer exists."
        }

        function.run "ops/log_event" {
          input = {
            feature   : "GOV-1"
            step      : "integrity_audit"
            outcome   : "failure"
            severity  : "warn"
            error_code: "E-GOV-006"
            message   : $message
            metadata  : {
              finding_count  : $audit.finding_count
              counts_by_check: $audit.counts_by_check
              rows_checked   : $audit.rows_checked
            }
          }
        } as $_logged_findings
      }

      else {
        function.run "ops/log_event" {
          input = {
            feature : "GOV-1"
            step    : "integrity_audit"
            outcome : "success"
            severity: "info"
            message : "Integrity audit found no orphaned records."
            metadata: {
              finding_count: 0
              rows_checked : $audit.rows_checked
            }
          }
        } as $_logged_clean
      }
    }

    // RATE-1 (US-RATE-1-05) — version integrity: every version's hash
    // re-verifies, and v2 stage_rate counts match snapshot.rates. Logs its
    // own RATE-1 `rate_integrity_mismatch` failure (E-RATE-003) when it
    // finds any; separate function for the size reason in its header.
    function.run "ops/audit_rates" {
      input = {}
    } as $rate_audit

    // SEC-3 story 06 (2026-11-16) - prove the AI tool address is still shut to a caller with no
    // sign-in. Lives here because the Xano plan allows 10 tasks and all 10 are used. An OPEN door
    // logs E-SEC-021 (error); a check that cannot run logs E-SEC-022.
    try_catch {
      try {
        function.run "ops/mcp_door_check" {
          input = {}
        } as $door
      }

      catch {
        function.run "ops/log_event" {
          input = {feature: "SEC-3", step: "mcp_door_check", outcome: "failure", severity: "warn", user_id: 0, account_id: 0, entity_type: "mcp_server", entity_id: 8, correlation_id: "", error_code: "E-SEC-022", message: "Nightly check of the AI tool address could not run.", metadata: {}}
        } as $_door_failed
      }
    }

    // R17 (2026-11-16) - prune old copilot run history (copilot/prune_runs logs its own success).
    // Same reason for living here: no free task slot. A prune that cannot run logs E-COP-074.
    try_catch {
      try {
        function.run "copilot/prune_runs" {
          input = {}
        } as $pruned
      }

      catch {
        function.run "ops/log_event" {
          input = {feature: "COP-5", step: "prune_runs", outcome: "failure", severity: "warn", user_id: 0, account_id: 0, entity_type: "copilot_run", entity_id: 0, correlation_id: "", error_code: "E-COP-074", message: "Nightly cleanup of old copilot run history could not run.", metadata: {}}
        } as $_prune_failed
      }
    }
  }

  schedule = [{starts_on: 2026-10-14 04:00:00+0000, freq: 86400}]
}
