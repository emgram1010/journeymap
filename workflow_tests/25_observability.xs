// OBS-1 — Functional tests for the client event pipeline and the
// additive event_log safety guarantee.
//
// NOT RUN YET: this requires the OBS-1 backend (table changes, functions,
// apis/ops/*, the heartbeat task) to be pushed to the live Xano workspace
// first — ask before doing that push.
//
// SCOPE NOTE: this file does not test the admin-only gate on
// ops/health|issues|bundle|timeline (FT-OBS-1-11 in the epic's test
// plan). No existing workflow_test in this repo demonstrates running a
// workflow_test as a second, specifically-provisioned user (vs. the
// runner's default identity), and XanoScript's `api.call` has no
// documented option for that found in the syntax reference. Confirm how
// to do that (a spike, same spirit as US-OBS-1-12) before adding the
// admin-gate assertions here — do not guess at unverified syntax for a
// security-relevant check.
workflow_test observability {
  stack {
    // ── FT-OBS-1-01: a successful client event is written faithfully ──
    var $success_correlation_id {
      value = "25a00000-0000-0000-0000-000000000001"
    }

    api.call "ops/event" verb=POST {
      api_group = "Ops"
      input = {
        feature       : "OBS-1"
        step          : "workflow_test_success"
        outcome       : "success"
        correlation_id: $success_correlation_id
        duration_ms   : 42
      }
    } as $success_call

    expect.to_equal ($success_call.accepted) {
      value = true
    }

    db.query event_log {
      where = $db.event_log.correlation_id == $success_correlation_id
      return = {type: "list"}
    } as $success_rows

    expect.to_equal ($success_rows|count) {
      value = 1
    }

    expect.to_equal ($success_rows[0].outcome) {
      value = "success"
    }

    expect.to_equal ($success_rows[0].feature) {
      value = "OBS-1"
    }

    expect.to_equal ($success_rows[0].duration_ms) {
      value = 42
    }

    // ── FT-OBS-1-03: a failure event carries its error code, no stack trace ──
    var $failure_correlation_id {
      value = "25a00000-0000-0000-0000-000000000002"
    }

    api.call "ops/event" verb=POST {
      api_group = "Ops"
      input = {
        feature       : "OBS-1"
        step          : "workflow_test_failure"
        outcome       : "failure"
        error_code    : "E-OBS-999"
        message       : "Something unexpected happened while saving."
        correlation_id: $failure_correlation_id
      }
    } as $failure_call

    expect.to_equal ($failure_call.accepted) {
      value = true
    }

    db.query event_log {
      where = $db.event_log.correlation_id == $failure_correlation_id
      return = {type: "list"}
    } as $failure_rows

    expect.to_equal ($failure_rows|count) {
      value = 1
    }

    expect.to_equal ($failure_rows[0].outcome) {
      value = "failure"
    }

    expect.to_equal ($failure_rows[0].error_code) {
      value = "E-OBS-999"
    }

    // The friendly message must not contain a stack-trace-shaped line.
    expect.to_equal ($failure_rows[0].message|contains:"at ") {
      value = false
    }

    // ── De-dup: an identical event reported twice within 5s is not double-logged ──
    var $dedup_correlation_id {
      value = "25a00000-0000-0000-0000-000000000003"
    }

    api.call "ops/event" verb=POST {
      api_group = "Ops"
      input = {feature: "OBS-1", step: "workflow_test_dedup", outcome: "failure", correlation_id: $dedup_correlation_id}
    } as $dedup_call_1

    api.call "ops/event" verb=POST {
      api_group = "Ops"
      input = {feature: "OBS-1", step: "workflow_test_dedup", outcome: "failure", correlation_id: $dedup_correlation_id}
    } as $dedup_call_2

    expect.to_equal ($dedup_call_1.accepted) {
      value = true
    }

    expect.to_equal ($dedup_call_2.accepted) {
      value = false
    }

    db.query event_log {
      where = $db.event_log.feature == "OBS-1" && $db.event_log.step == "workflow_test_dedup"
      return = {type: "list"}
    } as $dedup_rows

    expect.to_equal ($dedup_rows|count) {
      value = 1
    }

    // ── FT-OBS-1-10: existing event_log writers and shape are unaffected ──
    api.call "auth/me" verb=GET {
      api_group = "Authentication"
      input = {}
    } as $me

    expect.to_equal ($me.id != null) {
      value = true
    }

    db.query event_log {
      where = $db.event_log.action == "get_auth_user" && $db.event_log.user_id == $me.id
      sort = {created_at: "desc"}
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $legacy_rows

    expect.to_equal ($legacy_rows|count) {
      value = 1
    }

    // Legacy rows (written by "Getting Started Template/create_event_log",
    // which this epic does not touch) have no value in the new columns.
    expect.to_equal ($legacy_rows[0].outcome) {
      value = null
    }
  }
}
