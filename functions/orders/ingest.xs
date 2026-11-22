// DEMAND-1 story 03 — the door for an outside order system. The caller proves itself with an order key (emg_ord_ + 64 hex); only its SHA-256 hash is compared, and the key is never stored, logged or returned. A key belongs to exactly one account and one source system, so the caller cannot choose either. An unknown or switched-off key is refused (E-HOOK-001) and logged at most 5 times an hour. Everything after that is orders/process.
function "orders/ingest" {
  input {
    text order_key? filters=trim
    json order?
  }

  stack {
    var $key {
      value = $input.order_key ?? ""
    }

    var $key_ok {
      value = "/^emg_ord_[a-f0-9]{64}$/"|regex_matches:$key
    }

    var $hash {
      value = $key|sha256
    }

    db.query order_route {
      where = $db.order_route.key_hash == $hash && $db.order_route.is_enabled == true && $key_ok == true
      return = {type: "list"}
    } as $rows

    var $first {
      value = $rows|first
    }

    var $acct {
      value = $first|get:"account_id":0
    }

    var $source {
      value = $first|get:"source_system":""
    }

    conditional {
      if ($acct == 0) {
        var $now_ms {
          value = now|to_int
        }

        var $hour_ago {
          value = $now_ms - 3600000
        }

        db.query event_log {
          where = $db.event_log.feature == "DEMAND-1" && $db.event_log.step == "order_key_refused" && $db.event_log.created_at >= $hour_ago
          return = {type: "count"}
        } as $recent

        conditional {
          if ($recent < 5) {
            function.run "ops/log_event" {
              input = {feature: "DEMAND-1", step: "order_key_refused", outcome: "rejected", severity: "warn", error_code: "E-HOOK-001", message: "An order arrived with an unknown or switched-off key. Nothing was added. At most 5 of these are logged an hour.", user_id: 0, account_id: 0, entity_type: "order_route", entity_id: 0, correlation_id: "", duration_ms: 0, metadata: {}}
            } as $_ev
          }
        }
      }
    }

    precondition ($acct != 0) {
      error_type = "accessdenied"
      error = "This order key isn't recognised, or it is switched off. (E-HOOK-001)"
    }

    function.run "orders/process" {
      input = {account_id: $acct, source_system: $source, order: $input.order}
    } as $result
  }

  response = $result
}
