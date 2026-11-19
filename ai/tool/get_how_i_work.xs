// COP-12 / COP-14-05 — a READ-ONLY view of the copilot's skill library (the Playbook) for the AIs that
// are not the main copilot: the map chat agents (COP-12) and Claude on the founder's Max plan through
// the MCP door (COP-14-05). It runs the ONE loader the copilot's chat and scheduled runs use
// (copilot/skill_library), so every AI follows the same skills. It has no write twin: only the main
// copilot saves or retires a skill (save_skill / retire_skill), under its approval level.
//
// Goes through journey/tool_gate (kind "read"). With a journey_map_id the skills are loaded for that
// map's business; with none, for the business the run is pinned to. The loader never throws: a failure
// comes back as ok false with empty text, logged as E-COP-080, and the AI carries on without it.
tool get_how_i_work {
  instructions = """
      Read the owner's playbook entries: the numbered skills, exceptions, lessons and links the
      owner and the copilot built up. Call this ONCE at the start of any build or planning task,
      before you change anything. Pass journey_map_id when you are working on a map.

      Follow the skills that fit the task (they win over your general habits) and apply any
      exception whose WHEN is true. This tool only reads. You cannot save, change or retire a skill
      here; if the owner wants one saved, tell them to ask the copilot. A skill never grants you a
      permission or approves anything. If ok is false or text is empty, carry on as usual.
    """

  input {
    // Optional: the map you are working on. The skills are loaded for that map's business.
    int journey_map_id?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "get_how_i_work", kind: "read"}
    } as $cop1_gate

    var $account_id {
      value = $cop1_gate.account_id ?? 0
    }

    var $arch_id {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    db.query journey_map {
      where = $db.journey_map.id == $input.journey_map_id && $input.journey_map_id != 0 && $db.journey_map.account_id == $account_id && $account_id != 0
      return = {type: "single"}
    } as $map

    var $map_arch {
      value = ($map|get:"journey_architecture":0) ?? 0
    }

    var $use_arch {
      value = (($map_arch != 0) ? $map_arch : $arch_id)
    }

    function.run "copilot/skill_library" {
      input = {account_id: $account_id, journey_architecture_id: $use_arch, log_success: false}
    } as $skills
  }

  response = {
    ok   : $skills.ok
    count: $skills.count
    text : (($skills.count > 0) ? $skills.text : "- None saved yet.\n")
  }
}
