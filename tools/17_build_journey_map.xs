// Triggers a full AI build of a journey map.
// Runs the Journey Map Assistant for one turn with a build prompt.
// For multi-turn headless builds, use POST /journey_map/{id}/build_full.
// US-BIM-07
tool build_journey_map {
  instructions = """
    Use this tool to build or complete a journey map using AI.
    Pass the journey_map_id of the map to build.
    Optionally pass context (domain description) to guide the AI.
    The tool runs the Journey Map Assistant with a build prompt and returns
    the assistant reply plus any tool calls made during the turn.
    For large maps that need multiple turns, the agent will include
    [CONTINUE_BUILD] in its reply — call this tool again to continue.
  """

  input {
    // The numeric ID of the journey map to build.
    int journey_map_id filters=min:1

    // Optional domain context injected into the build prompt.
    // Example: "B2B SaaS onboarding flow for mid-market customers"
    text context?

    // Optional continuation: pass [CONTINUE_BUILD] to resume a build in progress.
    text continuation_message?
  }

  stack {
    // ── Validate map exists ──
    db.get journey_map {
      field_name  = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error      = "Journey map not found"
    }

    // ── Build the prompt ──
    var $context_suffix { value = "" }

    conditional {
      if ($input.context != null && $input.context != "") {
        var.update $context_suffix {
          value = " Context: " ~ $input.context
        }
      }
    }

    var $prompt { value = "Build the full journey map." ~ $context_suffix }

    conditional {
      if ($input.continuation_message != null && $input.continuation_message != "") {
        var.update $prompt {
          value = $input.continuation_message
        }
      }
    }

    // ── Run the Journey Map Assistant ──
    ai.agent.run "Journey Map Assistant" {
      args = {}|set:"messages":[{role: "user", content: $prompt}]
      allow_tool_execution = true
    } as $agent_run
  }

  response = {
    journey_map_id : $input.journey_map_id
    map_title      : $journey_map.title
    reply          : $agent_run.output
    continue_needed: $agent_run.output|contains:"[CONTINUE_BUILD]"
  }
}
