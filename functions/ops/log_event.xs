// OBS-1 (US-OBS-1-02) — The one place every epic records a success, a
// rejection or a failure. This function must NEVER throw: a logging
// problem must not break the user action that triggered it. If the full
// write fails for any reason, it falls back to a minimal row (just the
// outcome and feature) so the event is still counted, and increments a
// best-effort counter in redis so a broken logging path is itself visible.
//
// Convention (see EPIC-OBS-1): action = "<feature>.<step>", e.g.
// "PUB-1.publish_version". outcome is "success" | "rejected" | "failure".
// Callers pass a correlation_id generated once per user action (see
// ops/correlationId.ts on the frontend, and US-OBS-1-12 for the backend
// side of that decision).
//
// Do not duplicate "Getting Started Template/create_event_log" — that
// function is called by 10 existing auth/account endpoints and is left
// untouched. This function is a separate, richer writer for the new
// observability columns added to event_log by this epic.
function "ops/log_event" {
  description = "Write one event_log row for the observability pipeline. Never throws."

  input {
    text feature filters=trim {
      description = "Epic code, e.g. 'OBS-1', 'PUB-1'."
    }

    text step filters=trim {
      description = "The specific step within the feature, e.g. 'publish_version'."
    }

    enum outcome {
      values = ["success", "rejected", "failure"]
      description = "success = it worked. rejected = correctly refused. failure = broke unexpectedly."
    }

    enum severity? {
      values = ["info", "warn", "error"]
      description = "Defaults to 'info' when not supplied (see stack)."
    }

    int user_id? {
      description = "Who performed the action, if known."
    }

    int account_id? {
      description = "Which account this event belongs to. Null for system events (heartbeat, daily audit)."
    }

    text entity_type? filters=trim
    int entity_id?

    text correlation_id? filters=trim {
      description = "Generated once per user action by the caller. Shown to the user as 'Reference'."
    }

    text error_code? filters=trim {
      description = "A catalog code in the form E-<epic>-<three digits>. Should be null for outcome=success."
    }

    text message? filters=trim {
      description = "Plain-English, no stack traces, no secrets."
    }

    int duration_ms?

    json metadata? {
      description = "Only ids and field names — never attribute values, notes, emails, tokens or passwords."
    }
  }

  stack {
    var $severity {
      value = "info"
    }

    conditional {
      if ($input.severity != null && $input.severity != "") {
        var.update $severity {
          value = $input.severity
        }
      }
    }

    var $logged {
      value = false
      description = "Set true as soon as any write (structured or minimal) succeeds."
    }

    try_catch {
      description = "The full, structured write. If anything here fails, fall back below."

      try {
        db.add event_log {
          enforce_hidden_fields = false
          data = {
            created_at    : "now"
            user_id       : $input.user_id
            account_id    : $input.account_id
            action        : $input.feature ~ "." ~ $input.step
            severity      : $severity
            outcome       : $input.outcome
            feature       : $input.feature
            step          : $input.step
            entity_type   : $input.entity_type
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
            error_code    : $input.error_code
            message       : $input.message
            duration_ms   : $input.duration_ms
            metadata      : $input.metadata
          }
        } as $row

        var.update $logged {
          value = true
        }
      }

      catch {
        // The structured write failed (e.g. an unexpected value shape).
        // Try a minimal row so the event is still counted, and never let
        // this bubble up to the caller.
        try_catch {
          try {
            db.add event_log {
              enforce_hidden_fields = false
              data = {
                created_at: "now"
                account_id: $input.account_id
                action    : $input.feature ~ "." ~ $input.step
                outcome   : $input.outcome
                feature   : $input.feature
                step      : $input.step
                message   : "log_event: structured write failed, minimal row written"
              }
            } as $fallback_row

            var.update $logged {
              value = true
            }
          }

          catch {
            // Even the minimal write failed. Count it so a broken logging
            // path is visible without ever failing the caller. $logged
            // stays false (its initial value).
            try_catch {
              try {
                redis.incr {
                  key = "ops:log_event:dropped"
                } as $_dropped_counter
              }

              catch {
                debug.log {
                  value = "ops/log_event: both the structured and minimal writes failed, and the drop counter failed too"
                }
              }
            }
          }
        }
      }
    }
  }

  response = {logged: $logged}

  test "writes a structured success event" {
    input = {
      feature: "OBS-1"
      step   : "unit_test"
      outcome: "success"
    }
    expect.to_equal ($response.logged) {
      value = true
    }
  }

  test "accepts a rejected event with an error code and correlation id" {
    input = {
      feature       : "VAL-1"
      step          : "validate_field"
      outcome       : "rejected"
      error_code    : "TEST-ONLY-NOT-A-REAL-CODE"
      correlation_id: "11111111-1111-1111-1111-111111111111"
      message       : "Give the role a short name."
    }
    expect.to_equal ($response.logged) {
      value = true
    }
  }

  test "accepts missing optional inputs without error" {
    input = {
      feature: "OBS-1"
      step   : "minimal_call"
      outcome: "failure"
    }
    expect.to_equal ($response.logged) {
      value = true
    }
  }
}
