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

    var $ctx {
      value = "## Business you are working on\n- name: " ~ $arch_title ~ "\n- journey_architecture_id: " ~ ($input.journey_architecture_id|to_text) ~ "\n\n## Who you are talking to\n- " ~ ($me|get:"name":"the owner") ~ "\n\n## What the owner is looking at\n- " ~ $screen ~ "\n\n## Waiting for the owner\n- " ~ ($waiting_count|to_text) ~ " item(s) waiting in Approvals for this business\n\n## Tool Logging\n- conversation_id: " ~ ($conv_id|to_text) ~ "\n- turn_id: " ~ $turn_id ~ "\n- ticket: " ~ $ticket.ticket ~ "\n"
    }

    var $agent_msgs {
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
        var.update $agent_err {
          value = $error.message ?? "The copilot could not answer."
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
  }
  tags = ["cop-3"]
}
