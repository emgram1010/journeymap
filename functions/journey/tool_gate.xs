// COP-1 — the first line of every AI tool: who is calling (usr/tool_caller: ticket or request token, switched on, Intelligent Layer) and is this map in their account (journey/assert_map_owner). No rule is written here; it makes the calls in order and returns one verdict. In "report" mode (usr/tool_gate_mode, set separately for outside assistants and in-app agents) it logs what it would refuse (at most 60 rows an hour) and lets the tool carry on. A map in another account answers exactly like one that does not exist. Returns the caller's user_id and account_id so a tool that creates something can stamp it.
function "journey/tool_gate" {
  input {
    int journey_map_id?
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
      value = ($refuse == true && $code == "E-COP-002")
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
