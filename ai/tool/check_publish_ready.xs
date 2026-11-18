// COP-10 — the AI checks a map against the real publish checklist (the one Publish version uses).
// Read-only: it never publishes and writes nothing to the map. The answer is whatever
// pub/check_map_ready returns from pub/evaluate_gate, passed through as it is; this tool keeps no list
// of rules, so a rule added to the gate reaches the AI with no change here.
tool check_publish_ready {
  instructions = """
      Check whether a journey map would pass Publish version, using the SAME checklist the product
      uses. Pass journey_map_id. Call this before you tell the owner a map is ready to publish, and
      again after you fix things.

      The answer has: ready (true or false), blockers (each has a code, stage_key, lens_key and a
      plain message; ready is false while there is any), warnings (they never stop a publish, but
      mention them), ready_count and total.

      What to do with the answer: fix the blockers you can fix with your own tools (a missing
      duration or "done when", for example), then call this again. For a blocker only the owner can
      decide (which role owns a stage), ask ONE question. Say "ready to publish" only when ready is
      true. You cannot publish: the owner presses Publish version.
    """

  input {
    // The ID of the journey map to check.
    int journey_map_id filters=min:1

    // Optional: for tool trace logging (transparency layer).
    int conversation_id?

    text turn_id?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? A map in another account answers like one that does not exist.
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "check_publish_ready", kind: "read"}
    } as $cop1_gate

    var $check {
      value = null
    }

    var $ok {
      value = true
    }

    var $err_msg {
      value = ""
    }

    try_catch {
      try {
        group {
          stack {
            function.run "pub/check_map_ready" {
              input = {journey_map_id: $input.journey_map_id}
            } as $check_inner

            var.update $check {
              value = $check_inner
            }
          }
        }
      }

      catch {
        var $check_caught {
          value = $error
        }

        var.update $err_msg {
          value = ($check_caught|get:"message":"unknown")
        }

        var.update $ok {
          value = false
        }
      }
    }

    var $account_id {
      value = $cop1_gate.account_id ?? 0
    }

    conditional {
      if ($ok == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-10"
            step       : "publish_check"
            outcome    : "failure"
            severity   : "warn"
            error_code : "E-COP-088"
            message    : "The publish checklist could not be run for a map."
            user_id    : 0
            account_id : $account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            metadata   : {reason: $err_msg}
          }
        } as $_fail_logged
      }

      else {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-10"
            step       : "publish_check"
            outcome    : "success"
            severity   : "info"
            error_code : ""
            message    : "The publish checklist was run for a map."
            user_id    : 0
            account_id : $account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            metadata   : {ready: ($check|get:"ready":false), blocker_count: (($check|get:"blockers":[])|count)}
          }
        } as $_ok_logged
      }
    }

    precondition ($ok) {
      error_type = "inputerror"
      error = "I couldn't run the publish checklist just now. Nothing was changed. (E-COP-088)"
    }
  }

  response = {
    ready        : $check.ready
    blockers     : $check.blockers
    warnings     : $check.warnings
    ready_count  : $check.ready_count
    total        : $check.total
    map_status   : $check.status
    map_title    : $check.title
    blocker_count: ($check.blockers|count)
  }
}
