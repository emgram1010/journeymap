// Pushed to workspace 1, api_group "Ops" (id 23), api id 511.
// OBS-1 (US-OBS-1-04) — The app reports a failed request, an unhandled
// front-end error, or a notable success through this endpoint. Rate
// limited and de-duplicated per user so a broken screen cannot flood the
// log (redis.ratelimit + a short de-dup window), then written via the
// shared ops/log_event helper so it behaves exactly like a backend event.
query "ops/event" verb=POST {
  api_group = "Ops"
  auth = "user"

  input {
    text feature filters=trim
    text step filters=trim

    enum outcome {
      values = ["success", "rejected", "failure"]
    }

    enum severity? {
      values = ["info", "warn", "error"]
    }

    text error_code? filters=trim
    text message? filters=trim|max:500
    text entity_type? filters=trim
    int entity_id?
    text correlation_id? filters=trim
    int duration_ms?
    json metadata?
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $user

    redis.ratelimit {
      key = "ops:event:" ~ ($auth.id|to_text)
      max = 20
      ttl = 60
      error = "Too many client events reported in a short time. (E-OBS-002)"
    } as $rate_limit_status

    var $dedup_key {
      value = "ops:event:dedup:" ~ ($auth.id|to_text) ~ ":" ~ $input.feature ~ ":" ~ $input.step ~ ":" ~ ($input.error_code ?? "none")
    }

    redis.get {
      key = $dedup_key
    } as $already_reported_recently

    var $accepted {
      value = false
    }

    conditional {
      if ($already_reported_recently != null) {
        debug.log {
          value = "ops/event: suppressed as a duplicate within the de-dup window"
        }
      }

      else {
        redis.set {
          key = $dedup_key
          data = "1"
          ttl = 5
        }

        function.run "ops/log_event" {
          input = {
            feature      : $input.feature
            step         : $input.step
            outcome      : $input.outcome
            severity     : $input.severity
            user_id      : $auth.id
            account_id   : $user.account_id
            entity_type  : $input.entity_type
            entity_id    : $input.entity_id
            correlation_id: $input.correlation_id
            error_code   : $input.error_code
            message      : $input.message
            duration_ms  : $input.duration_ms
            metadata     : $input.metadata
          }
        } as $logged

        var.update $accepted {
          value = true
        }
      }
    }
  }

  response = {accepted: $accepted}
}
