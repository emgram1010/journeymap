// DEMAND-1 story 03 — where an outside order system (or the small workspace that listens to it) sends an order. No sign-in: the caller sends its order key as "Authorization: Bearer <key>" and orders/ingest checks it by hash. Only these structured fields exist, so a customer note or any other free text has nowhere to go: external_id, order_number, status (active or cancelled), fulfilment, starts_on, ends_on (YYYY-MM-DD) and lines [{external_id, name, quantity}]. The answer always says what happened (created, updated, duplicate, flagged, no_route, held, refused or failed); sending the same order again is safe.
query "order-inbound" verb=POST {
  api_group = "planner"

  input {
    text external_id? filters=trim
    text order_number? filters=trim
    text status? filters=trim
    text fulfilment? filters=trim
    text starts_on? filters=trim
    text ends_on? filters=trim
    json lines?
  }

  stack {
    var $authz {
      value = ""
    }

    try_catch {
      try {
        var $hdrs {
          value = $env.$http_headers ?? {}
        }

        var.update $authz {
          value = $hdrs|get:"Authorization":""
        }
      }

      catch {
        var.update $authz {
          value = ""
        }
      }
    }

    var $key {
      value = "/^Bearer +/i"|regex_replace:"":$authz
    }

    var $order {
      value = {external_id: $input.external_id, order_number: $input.order_number, status: $input.status, fulfilment: $input.fulfilment, starts_on: $input.starts_on, ends_on: $input.ends_on, lines: $input.lines}
    }

    function.run "orders/ingest" {
      input = {order_key: $key, order: $order}
    } as $result
  }

  response = $result
}
