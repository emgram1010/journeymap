// Pushed to workspace 1 as task id 18 (id 16 was already taken by an
// existing "hourly_mixpanel_ingest" task — Xano assigns task ids on
// creation; this local filename is a pre-push naming guess).
// OBS-1 (US-OBS-1-05, heartbeat only) — Every 5 minutes: confirm the
// database is reachable and write one success event. The Health page
// treats a heartbeat older than 15 minutes as "No heartbeat" (red) — see
// webapp/protype-2/src/ops/healthStatus.ts.
//
// The daily integrity-audit half of US-OBS-1-05 now exists as
// tasks/19_ops_integrity_audit.xs, built with GOV-1 (which supplies the
// checks it runs).
//
// FIXED TWICE after live pushes:
// 1. `paging` dropped from the queries (it does not produce a plain
//    array — see CLAUDE.md verified constraints).
// 2. 2026-10-13: this task ran every 5 minutes for ~8 hours and wrote
//    NOTHING, silently. Cause: `transform_timestamp` was called inside
//    a db.query `where` clause. A where clause compiles to SQL and
//    cannot call filter functions — it only takes fields, inputs and
//    plain variables. The timestamp is now computed into $since_24h
//    first and the where clause references the variable. Every
//    computed value passed to log_event is likewise hoisted into its
//    own var rather than written inline in the object literal.
//    Caught by comparing event_log's row count against the number of
//    rows this session created — the task history showed it running,
//    but no events existed.
task ops_heartbeat {
  stack {
    var $since_24h {
      value = now|transform_timestamp:"24 hours ago":"UTC"
    }

    var $db_reachable {
      value = true
    }

    try_catch {
      try {
        db.query event_log {
          sort = {created_at: "desc"}
          return = {type: "list"}
        } as $_probe
      }

      catch {
        var.update $db_reachable {
          value = false
        }
      }
    }

    db.query event_log {
      where = $db.event_log.outcome == "failure" && $db.event_log.created_at >= $since_24h
      return = {type: "list"}
    } as $failures_24h

    db.query event_log {
      where = $db.event_log.feature == "PUB-1" && $db.event_log.step == "publish_version" && $db.event_log.outcome == "success"
      return = {type: "list"}
    } as $last_publish_rows

    db.query event_log {
      where = $db.event_log.feature == "LOG-1" && $db.event_log.outcome == "success"
      return = {type: "list"}
    } as $last_performer_event_rows

    var $failures_count {
      value = $failures_24h|count
    }

    var $publish_count {
      value = $last_publish_rows|count
    }

    var $performer_count {
      value = $last_performer_event_rows|count
    }

    var $has_last_publish {
      value = $publish_count > 0
    }

    var $has_last_performer_event {
      value = $performer_count > 0
    }

    function.run "ops/log_event" {
      input = {
        feature : "OPS"
        step    : "heartbeat"
        outcome : "success"
        severity: "info"
        metadata: {
          db_reachable            : $db_reachable
          failures_24h            : $failures_count
          has_last_publish        : $has_last_publish
          has_last_performer_event: $has_last_performer_event
        }
      }
    } as $_logged
  }

  schedule = [{starts_on: 2026-10-12 00:00:00+0000, freq: 300}]
}
