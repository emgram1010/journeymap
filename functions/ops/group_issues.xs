// OBS-1 (US-OBS-1-06, grouping only — acknowledgement is deferred) —
// Groups failure/rejected event_log rows into "issues" on read. Nothing
// is duplicated in storage; this just aggregates existing rows.
//
// fingerprint = feature ~ "::" ~ step ~ "::" ~ (error_code or "none").
// This MUST match the frontend's ops/fingerprint.ts formula exactly
// (same three parts, same separator, same "none" fallback), so that when
// acknowledgement (US-OBS-1-06, deferred) is built later, a fingerprint
// computed in the browser matches one computed here.
//
// NOTE: this function's grouping relies on array.group_by with a
// precomputed key and object.entries to flatten the result. Both are
// documented XanoScript primitives, but this exact combination has not
// been run against a live Xano workspace yet — verify it the first time
// this function is pushed and exercised for real.
function "ops/group_issues" {
  description = "Group failure/rejected events into issues. Read-only; nothing is written."

  input {
    int account_id? {
      description = "Narrow to one account. Omitted = every account (admin-only view)."
    }

    text since? filters=trim {
      description = "ISO timestamp lower bound. Defaults to 30 days ago when omitted."
    }
  }

  stack {
    var $since {
      value = $input.since ?? (now|transform_timestamp:"30 days ago":"UTC")
    }

    db.query event_log {
      where = $db.event_log.created_at >= $since
        && ($db.event_log.outcome == "failure" || $db.event_log.outcome == "rejected")
        && ($input.account_id == null || $db.event_log.account_id == $input.account_id)
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $events

    function.run "ops/error_catalog" {
      input = {}
    } as $catalog

    // Reshape each event into a small record carrying its fingerprint,
    // so array.group_by has a simple field to group on.
    array.map ($events) {
      by = {
        fingerprint   : (($this.feature ?? "") ~ "::" ~ ($this.step ?? "") ~ "::" ~ ($this.error_code ?? "none"))
        feature       : $this.feature
        step          : $this.step
        error_code    : $this.error_code
        severity      : ($this.severity ?? "error")
        created_at    : $this.created_at
        message       : $this.message
        correlation_id: $this.correlation_id
      }
    } as $keyed_events

    array.group_by ($keyed_events) {
      by = $this.fingerprint
    } as $grouped

    object.entries {
      value = $grouped
    } as $grouped_pairs

    array.map ($grouped_pairs) {
      by = {
        fingerprint   : $this[0]
        feature       : $this[1][0].feature
        step          : $this[1][0].step
        error_code    : $this[1][0].error_code
        severity      : $this[1][0].severity
        count         : ($this[1]|count)
        first_seen    : $this[1][0].created_at
        last_seen     : $this[1][(($this[1]|count) - 1)].created_at
        latest_message: $this[1][(($this[1]|count) - 1)].message
        sample_correlation_id: $this[1][(($this[1]|count) - 1)].correlation_id
        owner         : ($catalog|get:(($this[1][0].error_code ?? "")):null|get:"owner":"engineer")
        user_message  : ($catalog|get:(($this[1][0].error_code ?? "")):null|get:"user_message":null)
        fix_hint      : ($catalog|get:(($this[1][0].error_code ?? "")):null|get:"fix_hint":null)
      }
    } as $issues
  }

  response = {issues: $issues, since: $since}

  test "returns an empty list when there are no matching events" {
    mock "db.query event_log" {
      value = []
    }
    input = {}
    expect.to_equal ($response.issues|count) {
      value = 0
    }
  }
}
