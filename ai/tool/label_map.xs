// COP-4 stories 02/04 — the copilot labels a map in this business: what kind it is (insight or
// runnable), how it was made, the pages it drew on, and what was general practice vs fitted to this
// business. It can never mark a map "Tested" — only the owner or completed work does that.
tool label_map {
  instructions = "Label a map you made or researched: kind ('insight' for knowledge/strategy, 'runnable' for a process to plan and run from), made_by ('copilot_research', 'copilot_strategy' or 'copilot_draft'), sources (JSON array of {title, url} for every page you used - never long quotes), and research_note (which parts are general practice, which were fitted to this business, and anything thin or conflicting). You cannot mark a map tested."

  input {
    int journey_map_id filters=min:1
    text kind? filters=trim
    text made_by? filters=trim
    json sources?
    text research_note? filters=trim

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "label_map", kind: "write"}
    } as $cop1_gate

    var $kind_ok {
      value = ($input.kind == "" || $input.kind == "insight" || $input.kind == "runnable")
    }

    var $made_ok {
      value = ($input.made_by == "" || $input.made_by == "copilot_research" || $input.made_by == "copilot_strategy" || $input.made_by == "copilot_draft")
    }

    precondition ($kind_ok && $made_ok) {
      error_type = "inputerror"
      error = "kind is insight or runnable; made_by is copilot_research, copilot_strategy or copilot_draft. (E-COP-046)"
    }

    db.query journey_map {
      where = $db.journey_map.id == $input.journey_map_id
      return = {type: "single"}
      output = ["id", "journey_architecture", "account_id"]
    } as $map

    db.query copilot_map_profile {
      where = $db.copilot_map_profile.journey_map_id == $input.journey_map_id
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    var $new_kind {
      value = ($existing|get:"kind":"")
    }

    conditional {
      if ($input.kind != "") {
        var.update $new_kind {
          value = $input.kind
        }
      }
    }

    var $new_made {
      value = ($existing|get:"made_by":"copilot_draft")
    }

    conditional {
      if ($input.made_by != "") {
        var.update $new_made {
          value = $input.made_by
        }
      }
    }

    // A field left out keeps what is there (an omitted text input arrives as "").
    var $new_note {
      value = ($existing|get:"research_note":"")
    }

    conditional {
      if ($input.research_note != "") {
        var.update $new_note {
          value = $input.research_note
        }
      }
    }

    var $sources_text {
      value = ($input.sources ?? [])|json_encode
    }

    var $has_sources {
      value = ($sources_text != "[]" && $sources_text != "{}" && $sources_text != "null")
    }

    conditional {
      if ($existing_id == 0) {
        db.add copilot_map_profile {
          data = {
            journey_map_id         : $input.journey_map_id
            account_id             : ($map|get:"account_id":0)
            journey_architecture_id: ($map|get:"journey_architecture":0)
            kind                   : $new_kind
            made_by                : $new_made
            sources                : ($input.sources ?? [])
            research_note          : $new_note
            updated_by_user_id     : $cop1_gate.user_id
            updated_at             : "now"
          }
        } as $_added
      }

      else {
        db.patch copilot_map_profile {
          field_name = "id"
          field_value = $existing_id
          data = {kind: $new_kind, made_by: $new_made, research_note: $new_note, updated_by_user_id: $cop1_gate.user_id, updated_at: "now"}
        } as $_patched

        // sources is a json column: a patch MERGES (CLAUDE.md, CRITICAL). To replace the list,
        // clear it first, then write the new one.
        conditional {
          if ($has_sources == true) {
            db.patch copilot_map_profile {
              field_name = "id"
              field_value = $existing_id
              data = {sources: null}
            } as $_cleared

            db.patch copilot_map_profile {
              field_name = "id"
              field_value = $existing_id
              data = {sources: $input.sources}
            } as $_sources
          }
        }
      }
    }

    db.query copilot_map_profile {
      where = $db.copilot_map_profile.journey_map_id == $input.journey_map_id
      return = {type: "single"}
    } as $profile
  }

  response = {
    journey_map_id: $input.journey_map_id
    kind          : ($profile|get:"kind":"")
    made_by       : ($profile|get:"made_by":"")
    sources       : ($profile|get:"sources":null)
    tested        : (($profile|get:"tested_since":0) != 0)
  }
}
