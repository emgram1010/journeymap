// COP-1 — the first line of every AI tool: who is calling (usr/tool_caller: ticket or request token, switched on, Intelligent Layer) and is this map in their account (journey/assert_map_owner). No rule is written here; it makes the calls in order and returns one verdict. In "report" mode (usr/tool_gate_mode, set separately for outside assistants and in-app agents) it logs what it would refuse (at most 60 rows an hour) and lets the tool carry on. A map in another account answers exactly like one that does not exist. Returns the caller's user_id and account_id so a tool that creates something can stamp it.
function "journey/tool_gate" {
  input {
    int journey_map_id?
    int journey_architecture_id?
    text ticket? filters=trim
    text tool? filters=trim
    text kind? filters=trim
  }

  stack {
    function.run "usr/tool_caller" {
      input = {
        ticket: $input.ticket
      }
    } as $caller

    function.run "usr/tool_gate_mode" {
      input = {}
    } as $modes

    var $kind {
      value = "read"
    }

    conditional {
      if ($input.kind == "write") {
        var.update $kind {
          value = "write"
        }
      }
    }

    var $mode_key {
      value = $caller.context ~ "_" ~ $kind
    }

    var $mode_raw {
      value = $modes|get:$mode_key:null
    }

    var $mode {
      value = "report"
    }

    conditional {
      if ($mode_raw == "enforce") {
        var.update $mode {
          value = "enforce"
        }
      }
    }

    var $ok {
      value = true
    }

    var $code {
      value = ""
    }

    var $step {
      value = "tool/" ~ $input.tool
    }

    conditional {
      if ($caller.allowed != true && $caller.reason == "not_allowed") {
        var.update $ok {
          value = false
        }

        var.update $code {
          value = "E-COP-001"
        }
      }

      elseif ($caller.allowed != true) {
        var.update $ok {
          value = false
        }

        var.update $code {
          value = "E-SEC-020"
        }
      }

      elseif ($input.journey_map_id != 0) {
        try_catch {
          try {
            function.run "journey/assert_map_owner" {
              input = {
                journey_map_id   : $input.journey_map_id
                caller_account_id: $caller.account_id
                user_id          : $caller.user_id
                step             : $step
              }
            } as $_owner
          }

          catch {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = "E-COP-002"
            }
          }
        }
      }
    }

    // The architecture (business), when the tool names one. Same answer for "someone else's"
    // and "does not exist". Account 0 owns nothing.
    var $what {
      value = "map"
    }

    conditional {
      if ($ok == true && $input.journey_architecture_id != 0) {
        db.query journey_architecture {
          where = $db.journey_architecture.id == $input.journey_architecture_id
          return = {type: "single"}
          output = ["id", "account_id"]
        } as $arch_row

        var $arch_id {
          value = $arch_row|get:"id":0
        }

        var $arch_account {
          value = $arch_row|get:"account_id":0
        }

        conditional {
          if ($arch_id == 0 || $caller.account_id == 0 || $arch_account != $caller.account_id) {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = "E-COP-002"
            }

            var.update $what {
              value = "architecture"
            }
          }
        }
      }
    }

    // COP-1 story 05: an AI identity (copilot) has a daily cap on tool calls, counted per UTC day
    // from the audit trail. People have no cap. One "cap reached" event per copilot per day.
    var $over_cap {
      value = false
    }

    conditional {
      if ($ok == true && $caller.user_id != 0) {
        function.run "copilot/identity_for_user" {
          input = {user_id: $caller.user_id}
        } as $ai

        conditional {
          if ($ai.is_ai == true) {
            var $now_cap {
              value = now|to_int
            }

            var $day_start {
              value = $now_cap - ($now_cap % 86400000)
            }

            db.query tool_call_log {
              where = $db.tool_call_log.user_id == $caller.user_id && $db.tool_call_log.created_at >= $day_start
              return = {type: "count"}
            } as $calls_today

            conditional {
              if ($calls_today >= $ai.daily_cap) {
                var.update $ok {
                  value = false
                }

                var.update $code {
                  value = "E-COP-004"
                }

                var.update $over_cap {
                  value = true
                }

                db.query event_log {
                  where = $db.event_log.feature == "COP-1" && $db.event_log.step == "cap_reached" && $db.event_log.user_id == $caller.user_id && $db.event_log.created_at >= $day_start
                  return = {type: "count"}
                } as $cap_events_today

                conditional {
                  if ($cap_events_today == 0) {
                    function.run "ops/log_event" {
                      input = {
                        feature    : "COP-1"
                        step       : "cap_reached"
                        outcome    : "rejected"
                        severity   : "warn"
                        error_code : "E-COP-004"
                        message    : "The copilot reached its daily limit and is paused until tomorrow (UTC)."
                        user_id    : $caller.user_id
                        account_id : $caller.account_id
                        entity_type: "ai_identity"
                        entity_id  : $ai.identity_id
                        metadata   : {daily_cap: $ai.daily_cap, calls_today: $calls_today}
                      }
                    } as $_cap_logged
                  }
                }
              }
            }
          }
        }
      }
    }

    var $recent_logs {
      value = 0
    }

    conditional {
      if ($ok == false) {
        var $now_ms {
          value = now|to_int
        }

        var $log_cutoff {
          value = $now_ms - 3600000
        }

        db.query event_log {
          where = $db.event_log.feature == "COP-1" && $db.event_log.step == "tool_gate" && $db.event_log.created_at >= $log_cutoff
          return = {type: "count"}
        } as $recent_count

        var.update $recent_logs {
          value = $recent_count
        }
      }
    }

    var $msg {
      value = "AI tool gate (" ~ $mode ~ ", " ~ $caller.context ~ "): " ~ $input.tool ~ " - " ~ $caller.reason
    }

    conditional {
      if ($ok == false && $recent_logs < 60) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-1"
            step       : "tool_gate"
            outcome    : "rejected"
            severity   : "warn"
            error_code : $code
            message    : $msg
            user_id    : $caller.user_id
            account_id : $caller.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            metadata   : {mode: $mode, context: $caller.context, tool: $input.tool, kind: $kind, via: $caller.via, reason: $caller.reason}
          }
        } as $_logged
      }
    }

    // COP-1 story 04: the audit trail. One row per call, from any caller, written BEFORE any
    // refusal so a refused call is recorded too. Holds who, which tool, which map and the verdict
    // — never the call's input, the ticket or the token. A failure to write must never break the tool.
    var $verdict {
      value = "allowed"
    }

    conditional {
      if ($ok == false && $mode == "enforce") {
        var.update $verdict {
          value = "refused"
        }
      }

      elseif ($ok == false) {
        var.update $verdict {
          value = "would_refuse"
        }
      }
    }

    try_catch {
      try {
        db.add tool_call_log {
          data = {
            user_id                : $caller.user_id
            account_id             : $caller.account_id
            tool                   : $input.tool
            kind                   : $kind
            journey_map_id         : $input.journey_map_id
            journey_architecture_id: $input.journey_architecture_id
            context                : $caller.context
            via                    : $caller.via
            verdict                : $verdict
            code                   : $code
          }
        } as $_audit
      }

      catch {
        // Never let the audit write break the tool.
      }
    }

    var $refuse {
      value = ($ok == false && $mode == "enforce")
    }

    var $refuse_signin {
      value = ($refuse == true && $code == "E-SEC-020")
    }

    var $refuse_grant {
      value = ($refuse == true && $code == "E-COP-001")
    }

    var $refuse_map {
      value = ($refuse == true && $code == "E-COP-002" && $what == "map")
    }

    var $refuse_arch {
      value = ($refuse == true && $code == "E-COP-002" && $what == "architecture")
    }

    var $refuse_cap {
      value = ($refuse == true && $code == "E-COP-004")
    }

    precondition ($refuse_cap == false) {
      error_type = "accessdenied"
      error = "The copilot has reached today's limit and is paused until tomorrow. (E-COP-004)"
    }

    precondition ($refuse_signin == false) {
      error_type = "accessdenied"
      error = "Sign in to use these tools. (E-SEC-020)"
    }

    precondition ($refuse_grant == false) {
      error_type = "accessdenied"
      error = "You don't have access to this part of the product. Ask your admin to turn it on. (E-COP-001)"
    }

    precondition ($refuse_map == false) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($refuse_arch == false) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  }

  response = {
    ok        : $ok
    mode      : $mode
    code      : $code
    reason    : $caller.reason
    via       : $caller.via
    context   : $caller.context
    user_id   : $caller.user_id
    account_id: $caller.account_id
  }
}
