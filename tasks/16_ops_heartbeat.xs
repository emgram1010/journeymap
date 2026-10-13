// OBS-1 (US-OBS-1-05, heartbeat only) — Every 5 minutes: confirm the
// database is reachable and write one success event. The Health page
// treats a heartbeat older than 15 minutes as "No heartbeat" (red) — see
// webapp/protype-2/src/ops/healthStatus.ts.
//
// SCOPING NOTE: the epic also calls for a daily integrity-audit task
// running the GOV-1 checks. GOV-1 is a later epic in the build order and
// does not exist yet, so that task is deferred to GOV-1 rather than
// stubbed here with no real checks to run. This heartbeat task is
// self-contained and does not depend on GOV-1.
task ops_heartbeat {
  stack {
    var $db_reachable {
      value = true
    }

    try_catch {
      try {
        db.query event_log {
          sort = {created_at: "desc"}
          return = {type: "list", paging: {page: 1, per_page: 1}}
        } as $_probe
      }

      catch {
        var.update $db_reachable {
          value = false
        }
      }
    }

    db.query event_log {
      where = $db.event_log.outcome == "failure" && $db.event_log.created_at >= (now|transform_timestamp:"24 hours ago":"UTC")
      return = {type: "list"}
    } as $failures_24h

    db.query event_log {
      where = $db.event_log.feature == "PUB-1" && $db.event_log.step == "publish_version" && $db.event_log.outcome == "success"
      sort = {created_at: "desc"}
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $last_publish_rows

    db.query event_log {
      sort = {created_at: "desc"}
      where = $db.event_log.feature == "LOG-1" && $db.event_log.outcome == "success"
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $last_performer_event_rows

    function.run "ops/log_event" {
      input = {
        feature : "OPS"
        step    : "heartbeat"
        outcome : "success"
        severity: "info"
        metadata: {
          db_reachable            : $db_reachable
          failures_24h            : ($failures_24h|count)
          has_last_publish        : (($last_publish_rows|count) > 0)
          has_last_performer_event: (($last_performer_event_rows|count) > 0)
        }
      }
    } as $_logged
  }

  schedule = [{starts_on: 2026-10-12 00:00:00+0000, freq: 300}]
}
