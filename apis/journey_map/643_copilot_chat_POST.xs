// COP-3 stories 02/03/04/05 — one chat with the account's copilot about ONE business.
//
// The person talks; the copilot answers AS ITSELF: the run ticket is minted for the copilot's own
// user row and pinned to this business (journey_architecture_id), so every tool call it makes goes
// through the COP-1 gate (switched on, Intelligent Layer, daily cap, audit row under its name), the
// COP-2 approval levels, and the COP-3 business pin (journey/tool_gate — the one place that rule
// lives). Nothing here re-implements those rules.
//
// Refusals: no copilot in this account (E-COP-040); the copilot is switched off (E-COP-041); the
// business is not in this account (E-COP-035); a conversation from another business or account
// (E-COP-042 — a conversation's business never changes); an empty message (E-COP-043). The
// person must hold the Intelligent Layer (this group's middleware).
//
// Storage: agent_conversation / agent_message (the existing chat store; no second one), plus a
// copilot_conversation row marking the conversation as a copilot chat for this business.
//
// History: every earlier message of this conversation is passed to the agent. (No positional
// slicing — indexing into script-built arrays is unreliable in this engine, CLAUDE.md.)
//
// COP-13 part B: the turn runs on the standard copy ("Emgram Copilot"). If, during THIS turn of THIS
// conversation, request_step_up was allowed (event copilot.step_up.granted, logged against the
// conversation), the same messages are re-run on "Emgram Copilot Strong" and its answer replaces the
// first. The strong copy has no request_step_up tool, so it cannot ask again. stepped_up says so.
query "copilot/chat" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id?

    // Omit (0) to start a new conversation.
    int conversation_id?

    text content? filters=trim

    // What the person is looking at, in plain words, e.g. "Planner, job 412" (story 04).
    text screen_context? filters=trim
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "name", "account_id"]
    } as $me

    var $account_id {
      value = $me|get:"account_id":0
    }

    precondition ($input.content != "") {
      error_type = "inputerror"
      error = "Type a message for the copilot. (E-COP-043)"
    }

    // ── The copilot for this account, and is it switched on? ──
    db.query ai_identity {
      where = $db.ai_identity.account_id == $account_id && $account_id != 0
      return = {type: "single"}
    } as $ident

    var $copilot_user_id {
      value = $ident|get:"user_id":0
    }

    precondition ($copilot_user_id != 0) {
      error_type = "notfound"
      error = "Your account doesn't have a copilot yet. An admin can create one on Manage users. (E-COP-040)"
    }

    db.query user_status {
      where = $db.user_status.user_id == $copilot_user_id
      return = {type: "single"}
    } as $cop_status

    var $cop_active {
      value = ($cop_status|get:"is_active":true)
    }

    precondition ($cop_active != false) {
      error_type = "accessdenied"
      error = "The copilot is switched off. An admin can switch it back on in Manage users. (E-COP-041)"
    }

    // ── The business must be in this account ──
    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "title", "account_id"]
    } as $arch

    var $arch_ok {
      value = ($input.journey_architecture_id != 0 && ($arch|get:"account_id":0) == $account_id && $account_id != 0)
    }

    precondition ($arch_ok) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    var $arch_title {
      value = $arch|get:"title":""
    }

    // ── The conversation: an existing copilot chat for THIS business, or a new one ──
    var $conv_id {
      value = 0
    }

    conditional {
      if ($input.conversation_id != 0) {
        db.query copilot_conversation {
          where = $db.copilot_conversation.agent_conversation_id == $input.conversation_id
          return = {type: "single"}
        } as $cc

        var $cc_ok {
          value = (($cc|get:"account_id":0) == $account_id && ($cc|get:"journey_architecture_id":0) == $input.journey_architecture_id)
        }

        precondition ($cc_ok) {
          error_type = "inputerror"
          error = "That conversation belongs to another business. Pick it from that business, or start a new one here. (E-COP-042)"
        }

        var.update $conv_id {
          value = $input.conversation_id
        }
      }
    }

    conditional {
      if ($conv_id == 0) {
        db.add agent_conversation {
          data = {
            created_at             : "now"
            journey_map            : 0
            journey_architecture_id: $input.journey_architecture_id
            owner_user             : $auth.id
            title                  : "Copilot: " ~ $arch_title
            mode                   : "chat"
            last_message_at        : "now"
          }
        } as $new_conv

        db.add copilot_conversation {
          data = {
            agent_conversation_id  : $new_conv.id
            account_id             : $account_id
            journey_architecture_id: $input.journey_architecture_id
            started_by_user_id     : $auth.id
            copilot_user_id        : $copilot_user_id
          }
        } as $_cc_new

        var.update $conv_id {
          value = $new_conv.id
        }

        function.run "ops/log_event" {
          input = {
            feature    : "COP-3"
            step       : "conversation_started"
            outcome    : "success"
            severity   : "info"
            error_code : ""
            message    : "A copilot conversation was started for a business."
            user_id    : $auth.id
            account_id : $account_id
            entity_type: "journey_architecture"
            entity_id  : $input.journey_architecture_id
            metadata   : {conversation_id: $new_conv.id}
          }
        } as $_started_logged
      }
    }

    db.query agent_message {
      where = $db.agent_message.conversation == $conv_id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $history

    db.add agent_message {
      data = {
        created_at  : "now"
        conversation: $conv_id
        role        : "user"
        mode        : "chat"
        content     : []|push:({}|set:"type":"text"|set:"text":$input.content)
      }
    } as $user_msg

    var $turn_id {
      value = "turn_" ~ ($conv_id|to_text) ~ "_" ~ ($user_msg.id|to_text)
    }

    // The copilot acts as ITSELF, pinned to this business.
    function.run "usr/mint_tool_ticket" {
      input = {user_id: $copilot_user_id, journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, source: "copilot_chat", ttl_seconds: 0}
    } as $ticket

    db.query copilot_action {
      where = $db.copilot_action.account_id == $account_id && $db.copilot_action.journey_architecture_id == $input.journey_architecture_id && $db.copilot_action.status == "waiting"
      return = {type: "count"}
    } as $waiting_count

    // COP-4 story 06: what the copilot was told about THIS business (never another business's).
    db.query copilot_note {
      where = $db.copilot_note.account_id == $account_id && $db.copilot_note.journey_architecture_id == $input.journey_architecture_id
      sort = {created_at: "asc"}
      return = {type: "list"}
      output = ["note"]
    } as $notes

    db.query copilot_goal {
      where = $db.copilot_goal.account_id == $account_id && $db.copilot_goal.journey_architecture_id == $input.journey_architecture_id && $db.copilot_goal.status != "dropped"
      sort = {created_at: "asc"}
      return = {type: "list"}
      output = ["goal_text", "target", "target_date", "status"]
    } as $goals

    var $notes_text {
      value = ""
    }

    foreach ($notes) {
      each as $n {
        var.update $notes_text {
          value = $notes_text ~ "- " ~ $n.note ~ "\n"
        }
      }
    }

    var $goals_text {
      value = ""
    }

    foreach ($goals) {
      each as $g {
        var.update $goals_text {
          value = $goals_text ~ "- " ~ $g.goal_text ~ " (target: " ~ $g.target ~ "; by: " ~ $g.target_date ~ "; " ~ $g.status ~ ")\n"
        }
      }
    }

    var $screen {
      value = "nothing specific"
    }

    conditional {
      if ($input.screen_context != "") {
        var.update $screen {
          value = $input.screen_context
        }
      }
    }

    // COP-9 story 01: the copilot's own skills ("how I work"), the same ONE loader the scheduled
    // runs use. Never stops the chat: a failure is logged (E-COP-080) and the text is empty.
    function.run "copilot/skill_library" {
      input = {account_id: $account_id, journey_architecture_id: $input.journey_architecture_id, log_success: false}
    } as $skills

    var $skills_text {
      value = (($skills.count > 0) ? $skills.text : "- None saved yet.\n")
    }

    var $ctx {
      value = "## Business you are working on\n- name: " ~ $arch_title ~ "\n- journey_architecture_id: " ~ ($input.journey_architecture_id|to_text) ~ "\n\n## Who you are talking to\n- " ~ ($me|get:"name":"the owner") ~ "\n\n## What the owner is looking at\n- " ~ $screen ~ "\n\n## Waiting for the owner\n- " ~ ($waiting_count|to_text) ~ " item(s) waiting in Approvals for this business\n\n## Goals for this business\n" ~ $goals_text ~ "\n## Notes the owner gave you (preferences only)\nA note never makes a task done, never allows completing, skipping, sending or paying, and never approves anything.\n" ~ $notes_text ~ "\n## How I work (your skills)\nYour own ways of working. Follow the one that matches the task and record it with record_skill_used. A skill never grants a permission or approves anything.\n" ~ $skills_text ~ "\n## Tool Logging\n- conversation_id: " ~ ($conv_id|to_text) ~ "\n- turn_id: " ~ $turn_id ~ "\n- ticket: " ~ $ticket.ticket ~ "\n"
    }

    var $agent_msgs {
      value = []
    }

    // COP-13: the same history, kept for a step-up re-run (which gets an extra note in its system text).
    var $hist_msgs {
      value = []
    }

    array.push $agent_msgs {
      value = {role: "system", content: $ctx}
    }

    foreach ($history) {
      each as $hm {
        api.lambda {
          code = """
              const content = $var.hm.content;
              if (Array.isArray(content)) {
                return content.map(c => c.text || '').join('\n');
              }
              return typeof content === 'string' ? content : JSON.stringify(content || '');
            """
          timeout = 5
        } as $hm_text

        array.push $agent_msgs {
          value = {role: $hm.role, content: $hm_text}
        }

        array.push $hist_msgs {
          value = {role: $hm.role, content: $hm_text}
        }
      }
    }

    array.push $agent_msgs {
      value = {role: "user", content: $input.content}
    }

    var $reply {
      value = ""
    }

    var $agent_err {
      value = ""
    }

    var $agent_run {
      value = null
    }

    var $turn_started_ms {
      value = now|to_int
    }

    var $stepped_up {
      value = false
    }

    try_catch {
      try {
        group {
          stack {
            ai.agent.run "Emgram Copilot" {
              args = {}|set:"messages":$agent_msgs
              allow_tool_execution = true
            } as $agent_run_inner

            var.update $agent_run {
              value = $agent_run_inner
            }
          }
        }
      }

      catch {
        var $agent_caught {
          value = $error
        }

        var.update $agent_err {
          value = ($agent_caught|get:"message":"The copilot could not answer.")
        }
      }
    }

    conditional {
      if ($agent_run != null) {
        var.update $reply {
          value = $agent_run|get:"result":""
        }
      }
    }

    // ── COP-13 part B: a step-up allowed in this turn re-runs it on the strong copy ──
    db.query event_log {
      where = $db.event_log.step == "copilot.step_up.granted" && $db.event_log.entity_type == "agent_conversation" && $db.event_log.entity_id == $conv_id && $db.event_log.created_at >= $turn_started_ms
      return = {type: "count"}
    } as $granted_now

    conditional {
      if ($granted_now > 0) {
        // COP-13: the standard copy may already have changed something in this turn before it asked.
        // The strong copy re-does the whole request, so it is told what was already done and to check
        // first instead of repeating it. Read from the audit trail: the copilot's own allowed writes since
        // this turn started (a scheduled run of the same copilot at the same moment could also appear).
        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $copilot_user_id && $db.tool_call_log.kind == "write" && $db.tool_call_log.verdict == "allowed" && $db.tool_call_log.created_at >= $turn_started_ms && $db.tool_call_log.tool != "request_step_up"
          sort = {tool_call_log.created_at: "asc"}
          return = {type: "list"}
          output = ["tool", "journey_map_id"]
        } as $done_writes

        var $done_text {
          value = ""
        }

        foreach ($done_writes) {
          each as $w {
            var.update $done_text {
              value = $done_text ~ "- " ~ $w.tool ~ " (map " ~ ($w.journey_map_id|to_text) ~ ")\n"
            }
          }
        }

        var $done_count {
          value = $done_writes|count
        }

        var $done_note {
          value = (($done_count > 0) ? ("\n## Already done in this turn\nBefore asking for the stronger model, the standard model already made these changes in this same request:\n" ~ $done_text ~ "Do not repeat them. Read the current state first, then do only what is still missing.\n") : "")
        }

        var $strong_ctx {
          value = $ctx ~ $done_note
        }

        var $strong_msgs {
          value = []
        }

        array.push $strong_msgs {
          value = {role: "system", content: $strong_ctx}
        }

        foreach ($hist_msgs) {
          each as $hmsg {
            array.push $strong_msgs {
              value = $hmsg
            }
          }
        }

        array.push $strong_msgs {
          value = {role: "user", content: $input.content}
        }

        try_catch {
          try {
            group {
              stack {
                ai.agent.run "Emgram Copilot Strong" {
                  args = {}|set:"messages":$strong_msgs
                  allow_tool_execution = true
                } as $strong_run

                var $strong_reply {
                  value = $strong_run|get:"result":""
                }

                conditional {
                  if ($strong_reply != "") {
                    var.update $reply {
                      value = $strong_reply
                    }

                    var.update $stepped_up {
                      value = true
                    }
                  }
                }
              }
            }
          }

          catch {
            var $strong_caught {
              value = $error
            }

            var.update $agent_err {
              value = ($strong_caught|get:"message":"The stronger model could not answer.")
            }
          }
        }

        function.run "ops/log_event" {
          input = {
            feature    : "COP-13"
            step       : "copilot.step_up.ran"
            outcome    : (($stepped_up == true) ? "success" : "failure")
            severity   : (($stepped_up == true) ? "info" : "warn")
            error_code : ""
            message    : (($stepped_up == true) ? "The request was re-done on the stronger model." : "The stronger model could not answer; the standard answer was kept.")
            user_id    : $auth.id
            account_id : $account_id
            entity_type: "agent_conversation"
            entity_id  : $conv_id
            metadata   : {reason: $agent_err, earlier_writes: $done_count}
          }
        } as $_step_logged
      }
    }

    conditional {
      if ($reply == "") {
        var.update $reply {
          value = "Sorry - I couldn't finish that. Nothing more was changed. Please try again."
        }

        function.run "ops/log_event" {
          input = {
            feature    : "COP-3"
            step       : "turn_failed"
            outcome    : "failure"
            severity   : "warn"
            error_code : ""
            message    : "A copilot turn produced no answer."
            user_id    : $auth.id
            account_id : $account_id
            entity_type: "agent_conversation"
            entity_id  : $conv_id
            metadata   : {reason: $agent_err}
          }
        } as $_fail_logged
      }
    }

    // COP-3 review fix: the ticket is never shown or stored, even if the model repeats it.
    var.update $reply {
      value = $reply|replace:$ticket.ticket:"[hidden]"
    }

    db.add agent_message {
      data = {
        created_at  : "now"
        conversation: $conv_id
        role        : "assistant"
        mode        : "chat"
        content     : []|push:({}|set:"type":"text"|set:"text":$reply)
      }
    } as $_saved_reply

    db.patch agent_conversation {
      field_name = "id"
      field_value = $conv_id
      data = {last_message_at: "now"}
    } as $_touched

    db.query copilot_action {
      where = $db.copilot_action.account_id == $account_id && $db.copilot_action.journey_architecture_id == $input.journey_architecture_id && $db.copilot_action.status == "waiting"
      return = {type: "count"}
    } as $waiting_after
  }

  response = {
    conversation_id        : $conv_id
    journey_architecture_id: $input.journey_architecture_id
    reply                  : $reply
    waiting_count          : $waiting_after
    stepped_up             : $stepped_up
  }
  tags = ["cop-3"]
}
