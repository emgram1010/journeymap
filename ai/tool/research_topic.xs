// COP-4 stories 02/03 — the copilot hands a research topic to its restricted research agent
// ("Emgram Copilot Researcher"), which works with the SAME pinned run ticket (same identity, same
// business, same daily cap and approval levels) but only has search + draft-map tools. Returns the
// researcher's short report. Logged as a research run (topic length only, never the topic text).
// COP-7 (2026-11-15): the researcher gets its OWN short-lived ticket, source "research" - the gate
// then lets it change only maps the copilot made (E-COP-051). That ticket is ended when the run
// ends, and both tickets are scrubbed from the report.
tool research_topic {
  instructions = "Research a topic for this business and draft it as maps (journey, sub-journeys, exceptions) with sources. Use when the owner asks how to do something you don't know. Pass a generic topic (no customer names, contact details or figures). Returns a short report of what was drafted, the sources, and open questions."

  input {
    text topic filters=trim

    // Anything the owner said that the drafts should fit (generic; no private details).
    text fit_notes? filters=trim

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "research_topic", kind: "write"}
    } as $cop1_gate

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    var $topic_len {
      value = $input.topic|strlen
    }

    precondition ($input.topic != "" && $topic_len <= 300) {
      error_type = "inputerror"
      error = "Give a short research topic (up to 300 characters)."
    }

    var $fit_len {
      value = $input.fit_notes|strlen
    }

    precondition ($fit_len <= 500) {
      error_type = "inputerror"
      error = "Keep the fit notes short (up to 500 characters)."
    }

    function.run "usr/mint_tool_ticket" {
      input = {user_id: $cop1_gate.user_id, journey_map_id: 0, journey_architecture_id: $pin, source: "research", ttl_seconds: 900}
    } as $research_ticket

    var $rticket {
      value = $research_ticket.ticket
    }

    var $ctx {
      value = "## Business\n- journey_architecture_id: " ~ ($pin|to_text) ~ "\n\n## Fit to this business\n- " ~ $input.fit_notes ~ "\n\n## Tool Logging\n- ticket: " ~ $rticket ~ "\n"
    }

    var $msgs {
      value = [{role: "system", content: $ctx}, {role: "user", content: ("Research and draft: " ~ $input.topic)}]
    }

    var $report {
      value = ""
    }

    try_catch {
      try {
        group {
          stack {
            ai.agent.run "Emgram Copilot Researcher" {
              args = {}|set:"messages":$msgs
              allow_tool_execution = true
            } as $run

            var.update $report {
              value = $run|get:"result":""
            }
          }
        }
      }

      catch {
        var.update $report {
          value = ""
        }
      }
    }

    // The research ticket stops working the moment the run ends, and no ticket leaves in the report.
    function.run "usr/expire_tool_ticket" {
      input = {ticket: $rticket}
    } as $_expired

    var.update $report {
      value = $report|replace:$rticket:"[hidden]"|replace:$input.ticket:"[hidden]"
    }

    var $ok {
      value = ($report != "")
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-4"
        step       : "research_run"
        outcome    : (($ok == true) ? "success" : "failure")
        severity   : (($ok == true) ? "info" : "warn")
        error_code : (($ok == true) ? "" : "E-COP-047")
        message    : (($ok == true) ? "The copilot ran a research step." : "A copilot research step returned nothing usable.")
        user_id    : $cop1_gate.user_id
        account_id : $cop1_gate.account_id
        entity_type: "journey_architecture"
        entity_id  : $pin
        metadata   : {topic_length: $topic_len}
      }
    } as $_logged
  }

  response = {
    ok    : $ok
    report: (($ok == true) ? $report : "Research returned nothing usable this time. Nothing was drafted. (E-COP-047)")
  }
}
