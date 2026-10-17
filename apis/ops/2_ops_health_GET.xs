// Pushed to workspace 1, api_group "Ops" (id 23), api id 512.
// OBS-1 (US-OBS-1-07, status tile) — Admin-only. Returns the status tile
// data for the Health page: heartbeat freshness, failures in the last 24
// hours, and the open-issue count (grouping from ops/group_issues).
// healthStatus(heartbeatAgeMs, openIssuesCount) on the frontend turns this
// into green/amber/red — see webapp/protype-2/src/ops/healthStatus.ts.
//
// FIXED TWICE after live pushes (see CLAUDE.md verified constraints):
// 1. `paging` + `[0]` indexing replaced with a plain list and a
//    found-flag loop.
// 2. 2026-10-13: `transform_timestamp` cannot be called inside a
//    db.query `where` clause (the clause compiles to SQL). It is now
//    computed into $since_24h first. This endpoint would have failed
//    the very first time it was opened; it was caught while debugging
//    the heartbeat task, which had the identical bug.
query "ops/health" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    var $since_24h {
      value = now|transform_timestamp:"24 hours ago":"UTC"
    }

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
      where = $db.event_log.outcome == "failure" && $db.event_log.created_at >= $since_24h
      return = {type: "list"}
    } as $failures_24h

    function.run "ops/group_issues" {
      input = {}
    } as $grouped

    var $failures_count {
      value = $failures_24h|count
    }

    var $open_issues_count {
      value = $grouped.issues|count
    }
  }

  response = {
    last_heartbeat_at: $last_heartbeat_at
    failures_24h     : $failures_count
    open_issues_count: $open_issues_count
    checked_at       : now
  }
}
