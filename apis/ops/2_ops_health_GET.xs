// OBS-1 (US-OBS-1-07, status tile) — Admin-only. Returns the status tile
// data for the Health page: heartbeat freshness, failures in the last 24
// hours, and the open-issue count (grouping from ops/group_issues).
// healthStatus(heartbeatAgeMs, openIssuesCount) on the frontend turns this
// into green/amber/red — see webapp/protype-2/src/ops/healthStatus.ts.
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
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $last_heartbeat_rows

    var $last_heartbeat_at {
      value = null
    }

    conditional {
      if (($last_heartbeat_rows|count) > 0) {
        var.update $last_heartbeat_at {
          value = $last_heartbeat_rows[0].created_at
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
    last_heartbeat_at   : $last_heartbeat_at
    failures_24h        : ($failures_24h|count)
    open_issues_count    : ($grouped.issues|count)
    checked_at          : now
  }
}
