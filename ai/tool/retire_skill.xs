// COP-9 story 02 — the copilot stops using one of its own skills: the item is marked retired and
// no longer loads. It is never deleted; only the owner can delete, and the copilot's own business
// never can be (COP-3, E-COP-073). The owner can bring it back with Undo. Passes the gate with
// action type skill_write; the write is copilot/skill_write (op retire), which checks the item is
// in the copilot's own business (E-COP-081).
tool retire_skill {
  instructions = "Stop using one of your own skills, exceptions, lessons or links in 'how I work'. It is kept (retired), not deleted, and the owner can bring it back. Give a one-line reason."

  input {
    int skill_id {
      description = "The item number from 'How I work'."
    }

    text reason? filters=trim {
      description = "Why, in one line."
    }

    int conversation_id? {
      description = "The conversation_id from Tool Logging in your context, or 0 in a scheduled run."
    }

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    var $act_summary {
      value = "Retire skill #" ~ ($input.skill_id|to_text) ~ " in 'how I work'"
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "retire_skill", kind: "write", act_type: "skill_write", act_payload: {skill_id: $input.skill_id, reason: $input.reason}, act_summary: $act_summary, act_approval_id: $input.approval_id}
    } as $cop1_gate

    var $act_action_id {
      value = $cop1_gate.action_id ?? 0
    }

    var $act_account_id {
      value = $cop1_gate.account_id ?? 0
    }

    var $act_error {
      value = null
    }

    var $saved {
      value = null
    }

    try_catch {
      try {
        group {
          stack {
            function.run "copilot/skill_trace" {
              input = {ticket: $input.ticket, account_id: $act_account_id, conversation_id: $input.conversation_id}
            } as $trace

            function.run "copilot/skill_write" {
              input = {
                account_id      : $act_account_id
                actor_user_id   : $cop1_gate.user_id
                changed_by      : "copilot"
                op              : "retire"
                skill_id        : $input.skill_id
                kind            : ""
                title           : ""
                body            : ""
                condition_text  : ""
                parent_skill_id : 0
                link_to_skill_id: 0
                scope_type      : ""
                scope_ref_id    : 0
                scope_text      : ""
                reason          : $input.reason
                copilot_run_id  : $trace.copilot_run_id
                conversation_id : $trace.conversation_id
              }
            } as $written

            var.update $saved {
              value = $written
            }
          }
        }
      }

      catch {
        var.update $act_error {
          value = $error
        }
      }
    }

    function.run "copilot/action_close" {
      input = {action_id: $act_action_id, account_id: $act_account_id, error: $act_error}
    } as $_act_closed
  }

  response = {skill_id: $saved.skill_id, version_no: $saved.version_no, status: $saved.status}
}
