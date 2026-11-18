// COP-9 story 02 — the copilot writes down HOW it works: a new skill, exception, lesson or link in
// its own business ("how I work"), or new text for an existing one. Passes the gate like every tool
// (ticket, switched on, daily cap, audit row) with action type skill_write, so the owner's ONE
// level for "write its own skills" applies (default: runs, then tells you). The write itself is
// copilot/skill_write, where the hard limits sit (E-COP-081..084); this tool adds no rule of its own.
// New items start on trial. Every change is a version the owner can undo.
tool save_skill {
  instructions = "Save something you learned about HOW to work, in your own business 'how I work'. kind: skill (a repeatable way to do a task: steps, inputs, what done looks like), exception (WHEN something happens, do this instead - needs condition_text and parent_skill_id), lesson (something a real result taught you), or link (skill parent_skill_id feeds or triggers skill link_to_skill_id). To change an existing item, pass its skill_id with the full new text; leave a field empty to keep it. Never put logins, customer details, permissions or approval rules in a skill - the server refuses them. Facts about one business go in save_note instead."

  input {
    int skill_id? {
      description = "0 for a new item. The item number from 'How I work' to change one."
    }

    text kind? filters=trim {
      description = "New items only: skill, exception, lesson or link."
    }

    text title? filters=trim {
      description = "A short name, up to 120 characters."
    }

    text body? filters=trim {
      description = "What to do: steps, inputs, what done looks like (up to 4000 characters)."
    }

    text condition_text? filters=trim {
      description = "Exceptions only: WHEN it applies."
    }

    int parent_skill_id? {
      description = "Exception: the skill it changes. Link: the skill it starts from."
    }

    int link_to_skill_id? {
      description = "Link only: the skill it points to."
    }

    text scope_type? filters=trim {
      description = "Where it applies: all (default), business, map or work_kind."
    }

    int scope_ref_id? {
      description = "business: the journey_architecture_id; map: the journey_map_id."
    }

    text scope_text? filters=trim {
      description = "work_kind only: the kind of work, in plain words."
    }

    text reason? filters=trim {
      description = "Why, in one line: what happened that taught you this."
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
    var $act_title_head {
      value = $input.title|substr:0:120
    }

    var $act_summary {
      value = (($input.skill_id == 0) ? ("Save a new " ~ $input.kind ~ " in 'how I work': " ~ $act_title_head) : ("Change skill #" ~ ($input.skill_id|to_text) ~ " in 'how I work': " ~ $act_title_head))
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "save_skill", kind: "write", act_type: "skill_write", act_payload: {skill_id: $input.skill_id, kind: $input.kind, title: $input.title, body: $input.body, condition_text: $input.condition_text, parent_skill_id: $input.parent_skill_id, link_to_skill_id: $input.link_to_skill_id, scope_type: $input.scope_type, scope_ref_id: $input.scope_ref_id, scope_text: $input.scope_text, reason: $input.reason}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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
                op              : (($input.skill_id == 0) ? "create" : "edit")
                skill_id        : $input.skill_id
                kind            : $input.kind
                title           : $input.title
                body            : $input.body
                condition_text  : $input.condition_text
                parent_skill_id : $input.parent_skill_id
                link_to_skill_id: $input.link_to_skill_id
                scope_type      : $input.scope_type
                scope_ref_id    : $input.scope_ref_id
                scope_text      : $input.scope_text
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

  response = {skill_id: $saved.skill_id, version_no: $saved.version_no, status: $saved.status, kind: $saved.kind}
}
