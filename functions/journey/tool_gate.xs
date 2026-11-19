// COP-1/COP-2 — the first line of every AI tool: who is calling (usr/tool_caller: ticket or request token, switched on, Intelligent Layer) and is this map in their account (journey/assert_map_owner). No rule is written here; it makes the calls in order and returns one verdict. In "report" mode (usr/tool_gate_mode, set separately for outside assistants and in-app agents) it logs what it would refuse (at most 60 rows an hour) and lets the tool carry on. A map in another account answers exactly like one that does not exist. Returns the caller's user_id and account_id so a tool that creates something can stamp it. COP-8 story 03: a call made with a scheduled run's ticket is also tied to that run (tool_call_run); that write never blocks or changes the call (a failure is logged, E-COP-076).
function "journey/tool_gate" {
  input {
    int journey_map_id?
    int journey_architecture_id?
    text ticket? filters=trim
    text tool? filters=trim
    text kind? filters=trim

    // COP-2: the approval level check. A tool that declares an action type passes it here; the
    // names start with act_ so no tool's own input of the same name is inherited by accident
    // (an omitted function input inherits the caller's same-named input — CLAUDE.md).
    text act_type? filters=trim
    json act_payload?
    text act_summary? filters=trim
    int act_amount?
    bool act_has_amount?
    int act_approval_id?
    bool act_force_wait?
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

    // COP-3 story 02 (= COP-1 story 03): one business at a time. A run ticket can pin a business
    // (journey_architecture_id). When it does, the map a tool touches must be in that business and
    // any business it names must be that one. This is THE one place the rule lives; refused in any
    // mode, like an approval refusal. Account checks above already ran, so this only narrows.
    var $pin {
      value = $caller.ticket_architecture_id ?? 0
    }

    var $pin_refused {
      value = false
    }

    conditional {
      if ($ok == true && $pin != 0 && $input.journey_map_id != 0) {
        db.query journey_map {
          where = $db.journey_map.id == $input.journey_map_id
          return = {type: "single"}
          output = ["id", "journey_architecture"]
        } as $pin_map

        var $pin_map_arch {
          value = $pin_map|get:"journey_architecture":0
        }

        conditional {
          if ($pin_map_arch != $pin) {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = "E-COP-038"
            }

            var.update $pin_refused {
              value = true
            }
          }
        }
      }
    }

    conditional {
      if ($ok == true && $pin != 0 && $input.journey_architecture_id != 0 && $input.journey_architecture_id != $pin) {
        var.update $ok {
          value = false
        }

        var.update $code {
          value = "E-COP-038"
        }

        var.update $pin_refused {
          value = true
        }
      }
    }

    // COP-7 story 01: a research run (a ticket minted by research_topic, source "research") may
    // only change maps the copilot itself made. Text from a web page can therefore never make it
    // change or strip a map a person made. Unknown maker = refused. Refused in any mode.
    var $research_refused {
      value = false
    }

    conditional {
      if ($ok == true && $caller.ticket_source == "research" && $kind == "write" && $input.journey_map_id != 0) {
        db.query journey_map {
          where = $db.journey_map.id == $input.journey_map_id
          return = {type: "single"}
          output = ["id", "owner_user"]
        } as $research_map

        var $research_owner {
          value = ($research_map|get:"owner_user":0) ?? 0
        }

        conditional {
          if ($research_owner == 0 || $research_owner != $caller.user_id) {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = "E-COP-051"
            }

            var.update $research_refused {
              value = true
            }
          }
        }
      }
    }

    // COP-3 review fix: an AI identity always works inside one business. A copilot call that arrives
    // with no business pin (a ticket from another chat, or none) is refused, so a person cannot hand
    // the copilot an unpinned ticket and a copilot ticket cannot be used unpinned elsewhere.
    var $ai_unpinned {
      value = false
    }

    conditional {
      if ($ok == true && $pin == 0 && $caller.user_id != 0) {
        function.run "copilot/identity_for_user" {
          input = {user_id: $caller.user_id}
        } as $pin_ai

        conditional {
          if ($pin_ai.is_ai == true) {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = "E-COP-048"
            }

            var.update $ai_unpinned {
              value = true
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

    // COP-2: approval levels, for AI identities, when the tool declares an action type. A refusal
    // here is enforced whatever usr/tool_gate_mode says: "waits for you" must be a real stop.
    var $action_refused {
      value = false
    }

    var $action_msg {
      value = ""
    }

    var $action_level {
      value = ""
    }

    var $action_id {
      value = 0
    }

    // Final review R1: the level is looked up in a business. A tool that names neither a map nor
    // a business (the plan tools, notes, the copilot's own tasks) works in the business this
    // conversation is pinned to, so the owner's level for THAT business applies - not the defaults.
    var $act_arch {
      value = $input.journey_architecture_id
    }

    conditional {
      if ($act_arch == 0 && $pin != 0) {
        var.update $act_arch {
          value = $pin
        }
      }
    }

    conditional {
      if ($ok == true && $input.act_type != "") {
        function.run "copilot/action_gate" {
          input = {
            user_id            : $caller.user_id
            account_id         : $caller.account_id
            act_type           : $input.act_type
            act_tool           : $input.tool
            act_map_id         : $input.journey_map_id
            act_architecture_id: $act_arch
            act_payload        : $input.act_payload
            act_summary        : $input.act_summary
            act_amount         : $input.act_amount
            act_has_amount     : $input.act_has_amount
            act_approval_id    : $input.act_approval_id
            act_force_wait     : $input.act_force_wait
          }
        } as $act_gate

        var.update $action_level {
          value = $act_gate.level
        }

        var.update $action_id {
          value = $act_gate.action_id
        }

        conditional {
          if ($act_gate.proceed != true) {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = $act_gate.code
            }

            var.update $action_refused {
              value = true
            }

            var.update $action_msg {
              value = $act_gate.message
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
      if ($ok == false && $recent_logs < 60 && $action_refused == false && $pin_refused == false && $ai_unpinned == false && $research_refused == false) {
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
      if ($ok == false && ($mode == "enforce" || $action_refused == true || $pin_refused == true || $over_cap == true || $ai_unpinned == true || $research_refused == true)) {
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

    var $audit_id {
      value = 0
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

        var.update $audit_id {
          value = $_audit.id
        }
      }

      catch {
        // Never let the audit write break the tool.
      }
    }

    // COP-8 story 03 (R15): a call made with a SCHEDULED RUN's ticket is tied to that run
    // (tool_call_run), so the run's refused count is exact and support can trace any refusal.
    // Only tickets listed in copilot_run_ticket are linked; a chat ticket finds no row and writes
    // nothing. Ids only - never the ticket text. This must NEVER block or change the call: any
    // failure is caught and logged as E-COP-076, and the verdict above is already decided.
    var $link_wanted {
      value = ($audit_id != 0) && ($caller.via == "ticket") && ($caller.user_id != 0) && ($input.ticket != "")
    }

    conditional {
      if ($link_wanted == true) {
        try_catch {
          try {
            db.query tool_run_ticket {
              where = $db.tool_run_ticket.ticket == $input.ticket
              return = {type: "single"}
              output = ["id"]
            } as $link_ticket

            var $link_ticket_id {
              value = $link_ticket|get:"id":0
            }

            db.query copilot_run_ticket {
              where = $db.copilot_run_ticket.tool_run_ticket_id == $link_ticket_id && $link_ticket_id != 0
              return = {type: "single"}
              output = ["id", "copilot_run_id"]
            } as $link_run

            var $link_run_id {
              value = $link_run|get:"copilot_run_id":0
            }

            conditional {
              if ($link_run_id != 0) {
                db.add tool_call_run {
                  data = {tool_call_log_id: $audit_id, copilot_run_id: $link_run_id, pin_architecture_id: $pin}
                } as $_link_row
              }
            }
          }

          catch {
            var $link_caught {
              value = $error
            }

            var $link_detail {
              value = ($link_caught|get:"message":"The link could not be written.")
            }

            function.run "ops/log_event" {
              input = {
                feature       : "COP-8"
                step          : "tool_call_run"
                outcome       : "failure"
                severity      : "warn"
                user_id       : $caller.user_id
                account_id    : $caller.account_id
                entity_type   : "tool_call_log"
                entity_id     : $audit_id
                correlation_id: ""
                error_code    : "E-COP-076"
                message       : "A copilot tool call could not be linked to its scheduled run. The call itself was not affected."
                duration_ms   : 0
                metadata      : {tool: $input.tool, verdict: $verdict, detail: $link_detail}
              }
            } as $_link_fail_logged
          }
        }
      }
    }

    // COP-2 review fix: report mode is a rollout aid for PEOPLE's tools. An AI identity is refused
    // whenever any check failed, whatever the switch says — otherwise flipping a switch back to
    // "report" would also skip the approval gate (which only runs when every check passed).
    function.run "copilot/identity_for_user" {
      input = {user_id: $caller.user_id}
    } as $caller_ai

    var $refuse {
      value = ($ok == false && ($mode == "enforce" || $caller_ai.is_ai == true))
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

    // COP-3 review fix: the copilot outside a one-business conversation — refused in any mode.
    precondition ($ai_unpinned == false) {
      error_type = "accessdenied"
      error = "The copilot only works inside a conversation about one business. (E-COP-048)"
    }

    // COP-7: a research run touching a map the copilot did not make — refused in any mode.
    precondition ($research_refused == false) {
      error_type = "accessdenied"
      error = "Research can only change maps the copilot made. Make a new draft map instead. (E-COP-051)"
    }

    // COP-3: outside the business this conversation is pinned to — refused in any mode.
    precondition ($pin_refused == false) {
      error_type = "accessdenied"
      error = "That belongs to another business. This conversation works on one business only; switch business to work on it. (E-COP-038)"
    }

    // COP-2: waiting for approval, person-only, or a bad approval — refused in any mode.
    precondition ($action_refused == false) {
      error_type = "accessdenied"
      error = $action_msg
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
    action_level: $action_level
    action_id : $action_id
    pin_architecture_id: $pin
  }
}
