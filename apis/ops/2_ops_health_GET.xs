// Pushed to workspace 1, api_group "Ops" (id 23), api id 512.
// OBS-1 (US-OBS-1-07, status tile) — Admin-only. Returns the status tile
// data for the Health page: heartbeat freshness, failures in the last 24
// hours, and the open-issue count (grouping from ops/group_issues).
// healthStatus(heartbeatAgeMs, openIssuesCount) on the frontend turns this
// into green/amber/red — see webapp/protype-2/src/ops/healthStatus.ts.
//
// FIXED 2026-10-13 after a live push: the original version used
// `paging` + `[0]` indexing to get "just the latest row", which this
// workspace rejects ("Please use a numerically indexed array."). Fixed
// with plain `return: {type: "list"}` (no paging) + a foreach loop that
// keeps only the first row it sees (the list is sorted desc, so the
// first row is the latest) — no indexing, no paging. See
// functions/ops/build_diagnostic_bundle.xs for the same fix.
query "ops/health" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    db.query event_log {
      where = $db.event_log.feature == "OPS" && $db.event_log.step == "heartbeat" && $db.event_log.outcome == "success"
      sort = {created_at: "desc"}
      return = {type: "list"}
    } as $heartbeat_rows

    var $last_heartbeat_at {
      value = null
    }

    var $found_latest_heartbeat {
      value = false
    }

    foreach ($heartbeat_rows) {
      each as $row {
        conditional {
          if ($found_latest_heartbeat == false) {
            var.update $last_heartbeat_at {
              value = $row.created_at
            }

            var.update $found_latest_heartbeat {
              value = true
            }
          }
        }
      }
    }

    db.query event_log {
      where = $db.event_log.outcome == "failure" && $db.event_log.created_at >= (now|transform_timestamp:"24 hours ago":"UTC")
      return = {type: "list"}
    } as $failures_24h

    function.run "ops/group_issues" {
      input = {}
    } as $grouped
  }

  response = {
    last_heartbeat_at : $last_heartbeat_at
    failures_24h      : ($failures_24h|count)
    open_issues_count : ($grouped.issues|count)
    checked_at        : now
  }
}
