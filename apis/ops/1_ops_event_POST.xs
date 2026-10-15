// OBS-1 (US-OBS-1-04) — The app reports a failed request, an unhandled
// front-end error, or a notable success through this endpoint. Rate
// limited and de-duplicated per user so a broken screen cannot flood the
// log, then written via the shared ops/log_event helper so it behaves
// exactly like a backend event.
//
// REWRITTEN 2026-10-15 (found while verifying APP-1 over a real
// browser): the original version used `redis.ratelimit` / `redis.get` /
// `redis.set`, and every one of those calls 403s on this Xano plan
// ("Not supported. Please upgrade your Xano instance.") — so this
// endpoint has rejected EVERY call since OBS-1 was built, for every
// feature, not just APP-1. Combined with the frontend's own base-URL
// bug (xano.ts, fixed the same day), no client-side event had ever
// reached `event_log`.
//
// Replaced with the same table every other backend event already
// writes to: count this user's recent rows for the rate limit, look
// for a near-duplicate for the de-dup window. No new infrastructure,
// no redis dependency, same external behaviour (same codes, same
// windows). `created_at` is unindexed on `user_id` alone; fine at MVP
// volumes (this table is pruned daily — see its own header comment),
// worth revisiting if client-event volume grows materially.
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

    var $now_ms {
      value = now|to_int
    }

    var $rate_cutoff {
      value = $now_ms - 60000
    }

    var $dedup_cutoff {
      value = $now_ms - 5000
    }

    db.query event_log {
      where = $db.event_log.user_id == $auth.id && $db.event_log.created_at >= $rate_cutoff
      return = {type: "count"}
    } as $recent_count

    var $accepted {
      value = false
    }

    conditional {
      if ($recent_count >= 20) {
        debug.log {
          value = "ops/event: rate limit exceeded for this user in the last 60s"
        }
      }

      else {
        db.query event_log {
          where = $db.event_log.user_id == $auth.id && $db.event_log.feature == $input.feature && $db.event_log.step == $input.step && $db.event_log.error_code == $input.error_code && $db.event_log.created_at >= $dedup_cutoff
          return = {type: "count"}
        } as $dup_count

        conditional {
          if ($dup_count > 0) {
            debug.log {
              value = "ops/event: suppressed as a duplicate within the de-dup window"
            }
          }

          else {
            function.run "ops/log_event" {
              input = {
                feature       : $input.feature
                step          : $input.step
                outcome       : $input.outcome
                severity      : $input.severity
                user_id       : $auth.id
                account_id    : $user.account_id
                entity_type   : $input.entity_type
                entity_id     : $input.entity_id
                correlation_id: $input.correlation_id
                error_code    : $input.error_code
                message       : $input.message
                duration_ms   : $input.duration_ms
                metadata      : $input.metadata
              }
            } as $logged

            var.update $accepted {
              value = true
            }
          }
        }
      }
    }
  }

  response = {accepted: $accepted}
}
