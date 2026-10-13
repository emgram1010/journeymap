// OBS-1 (US-OBS-1-08, bundle only — the AI tool wrapper is deferred) —
// Builds a small, redacted, tenant-safe bundle of what happened, for the
// Health page's "Copy diagnostic bundle" button. Read-only.
//
// Redaction: the real control is upstream, at the logging call site —
// every caller of ops/log_event must log only ids and field names, never
// attribute values, notes, emails, tokens or passwords (see EPIC-OBS-1
// conventions). This function does NOT additionally strip metadata keys.
//
// REWRITTEN 2026-10-13 after a live push, twice:
// 1. The original version used array.map over the query result and
//    crashed live with "Unable to locate var: $this.created_at" as soon
//    as a real row flowed through it. Rewritten with a plain
//    foreach/each + array.push loop instead.
// 2. `db.query ... return: {type: "list", paging: {...}}` does NOT
//    produce a plain indexable/iterable array in this workspace —
//    `foreach` and `[index]` access both failed on it with "Please use
//    a numerically indexed array." `return: {type: "list"}` WITHOUT
//    paging does work (confirmed in ops/group_issues.xs). So `paging`
//    is dropped here; the `limit` input is enforced with a counter
//    inside the loop instead. Apply the same fix anywhere else in this
//    epic that used paging (ops/health, tasks/*_ops_heartbeat.xs).
// Also fixes the "" vs null issue (an omitted optional text/int input
// arrives as "" / 0, not null) for optional text/int inputs.
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
    var $has_correlation {
      value = ($input.correlation_id != null && $input.correlation_id != "")
    }

    var $has_entity {
      value = ($input.entity_type != null && $input.entity_type != "" && $input.entity_id != null && $input.entity_id != 0)
    }

    var $has_account_filter {
      value = ($input.account_id != null && $input.account_id != 0)
    }

    precondition ($has_correlation || $has_entity) {
      error_type = "inputerror"
      error = "Provide either a correlation_id or an entity_type + entity_id."
    }

    db.query event_log {
      where = ($has_correlation && $db.event_log.correlation_id == $input.correlation_id) || ($has_entity && $db.event_log.entity_type == $input.entity_type && $db.event_log.entity_id == $input.entity_id && ($has_account_filter == false || $db.event_log.account_id == $input.account_id))
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $raw_events

    var $events {
      value = []
    }

    var $last_error_code {
      value = null
      description = "Updated on every loop iteration; since $raw_events is sorted ascending by created_at, this naturally ends up holding the LAST event's error_code with no array indexing needed."
    }

    foreach ($raw_events) {
      each as $row {
        conditional {
          if (($events|count) < $input.limit) {
            array.push $events {
              value = {}|set:"created_at":$row.created_at|set:"feature":$row.feature|set:"step":$row.step|set:"outcome":$row.outcome|set:"severity":$row.severity|set:"error_code":$row.error_code|set:"message":$row.message|set:"entity_type":$row.entity_type|set:"entity_id":$row.entity_id|set:"duration_ms":$row.duration_ms|set:"metadata":$row.metadata
            }

            var.update $last_error_code {
              value = $row.error_code
            }
          }
        }
      }
    }

    var $event_count {
      value = $events|count
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
    event_count   : $event_count
    events        : $events
    catalog_entry : $catalog_entry
    owner         : ($catalog_entry|get:"owner":"engineer")
  }
}
