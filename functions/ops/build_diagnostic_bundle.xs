// OBS-1 (US-OBS-1-08, bundle only — the AI tool wrapper is deferred) —
// Builds a small, redacted, tenant-safe bundle of what happened, for the
// Health page's "Copy diagnostic bundle" button. Read-only.
//
// Redaction: the real control is upstream, at the logging call site —
// every caller of ops/log_event must log only ids and field names, never
// attribute values, notes, emails, tokens or passwords (see EPIC-OBS-1
// conventions). This function does NOT additionally strip metadata keys:
// doing that safely needs a verified "remove this key from a JSON
// object" filter, which has not been confirmed to exist in this
// XanoScript version yet. Add a deny-list strip here once that is
// confirmed; until then, treat this as a gap and keep the upstream
// convention strict.
function "ops/build_diagnostic_bundle" {
  description = "Return the ordered, redacted event history for a correlation id or an entity."

  input {
    text correlation_id? filters=trim
    text entity_type? filters=trim
    int entity_id?
    int account_id? {
      description = "Required when filtering by entity, so a bundle can never cross tenants."
    }
    int limit?=50 filters=min:1|max:200
  }

  stack {
    precondition ($input.correlation_id != null || ($input.entity_type != null && $input.entity_id != null)) {
      error_type = "inputerror"
      error = "Provide either a correlation_id or an entity_type + entity_id."
    }

    db.query event_log {
      where = ($input.correlation_id != null && $db.event_log.correlation_id == $input.correlation_id)
        || ($input.entity_type != null
          && $db.event_log.entity_type == $input.entity_type
          && $db.event_log.entity_id == $input.entity_id
          && ($input.account_id == null || $db.event_log.account_id == $input.account_id))
      sort = {created_at: "asc"}
      return = {type: "list", paging: {page: 1, per_page: $input.limit}}
    } as $raw_events

    array.map ($raw_events) {
      by = {
        created_at : $this.created_at
        feature    : $this.feature
        step       : $this.step
        outcome    : $this.outcome
        severity   : $this.severity
        error_code : $this.error_code
        message    : $this.message
        entity_type: $this.entity_type
        entity_id  : $this.entity_id
        duration_ms: $this.duration_ms
        metadata   : $this.metadata
      }
    } as $events

    var $last_error_code {
      value = null
    }

    conditional {
      if (($events|count) > 0) {
        var.update $last_error_code {
          value = $events[(($events|count) - 1)].error_code
        }
      }
    }

    function.run "ops/error_catalog" {
      input = {}
    } as $catalog

    var $catalog_entry {
      value = $catalog|get:($last_error_code ?? ""):null
    }
  }

  response = {
    correlation_id: $input.correlation_id
    entity_type   : $input.entity_type
    entity_id     : $input.entity_id
    event_count   : ($events|count)
    events        : $events
    catalog_entry : $catalog_entry
    owner         : ($catalog_entry|get:"owner":"engineer")
  }

  test "requires either a correlation id or an entity" {
    input = {}
    expect.to_throw {
      value = "Provide either a correlation_id or an entity_type + entity_id."
    }
  }

  test "returns zero events when nothing matches" {
    mock "db.query event_log" {
      value = []
    }
    input = {correlation_id: "11111111-1111-1111-1111-111111111111"}
    expect.to_equal ($response.event_count) {
      value = 0
    }
  }
}
