// COP-4 story 05 - "My edits teach it". When the owner EDITS a waiting copilot action before approving it, both versions are kept (copilot_action.payload = what the copilot drafted, approved_payload = what the owner approved). This reads those, for THIS business (the pin) and this copilot only, and counts which field of which kind of action the owner keeps changing. A (kind, field) pair is a pattern only with at least 3 edits (min_samples, never below 3: one or two examples are not a pattern). Returns the count and the newest before/after example. Read-only: it changes nothing; the copilot proposes "next time I will draft this like that", asks the owner, and saves it as a note only after a yes (save_note, which follows its own level).
// No `if` that reads a variable updated in the same loop iteration (CLAUDE.md): counts are folded in with bool|to_int and ?? on |get, and the result list branches only on a variable set before its loop.
tool get_my_edit_patterns {
  instructions = "How the owner has been editing your drafts before approving them, in this business. Each row: action_type, field, edits (how many times the owner changed that field), pattern (true only with enough edits), and the newest example (drafted and approved). Only when pattern is true, propose ONE change to how you draft that (quote edits and the example exactly), ask the owner to confirm, and only after a clear yes save it with save_note. Never propose anything from a row where pattern is false."

  input {
    int min_samples? {
      description = "How many edits make a pattern. Leave empty for 3. Values below 3 are treated as 3."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "get_my_edit_patterns", kind: "read"}
    } as $cop1_gate

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    var $min {
      value = (($input.min_samples > 3) ? $input.min_samples : 3)
    }

    // Edited before approval: the owner's version is kept in approved_payload. "executed" rows that
    // were edited still carry both versions, so both statuses are read; the field-by-field compare
    // below decides what really changed.
    db.query copilot_action {
      where = $db.copilot_action.account_id == $caller_account && $db.copilot_action.journey_architecture_id == $pin && $db.copilot_action.requested_by_user_id == $caller_user && ($db.copilot_action.status == "edited" || $db.copilot_action.status == "executed" || $db.copilot_action.status == "failed")
      sort = {copilot_action.created_at: "desc"}
      return = {type: "list"}
      output = ["id", "action_type", "payload", "approved_payload", "created_at"]
    } as $rows

    var $tally {
      value = {}
    }

    var $examples {
      value = {}
    }

    var $order {
      value = []
    }

    foreach ($rows) {
      each as $row {
        var $pkeys {
          value = ($row.payload ?? {})|keys
        }

        foreach ($pkeys) {
          each as $k {
            var $key {
              value = "k:" ~ ($row.action_type ?? "") ~ "::" ~ $k
            }

            var $drafted {
              value = ($row.payload ?? {})|get:$k:null
            }

            var $approved_v {
              value = ($row.approved_payload ?? {})|get:$k:null
            }

            var $has_approved {
              value = (($row.approved_payload ?? {})|keys|count) > 0
            }

            var $changed {
              value = ($has_approved == true) && (($drafted|json_encode) != ($approved_v|json_encode))
            }

            var $seen_before {
              value = ($tally|get:$key:null) ?? -1
            }

            var $cur {
              value = (($seen_before < 0) ? 0 : $seen_before)
            }

            var $new_count {
              value = $cur + ($changed|to_int)
            }

            var.update $tally {
              value = $tally|set:$key:$new_count
            }

            var $first_time {
              value = ($seen_before < 0)
            }

            var $type_name {
              value = $row.action_type ?? ""
            }

            var $with_new {
              value = $order|push:{key: $key, action_type: $type_name, field: $k}
            }

            var.update $order {
              value = (($first_time == true) ? $with_new : $order)
            }

            var $old_example {
              value = ($examples|get:$key:null) ?? {}
            }

            var $keep_old {
              value = ($changed == false) || ((($old_example|keys|count) > 0))
            }

            var $new_example {
              value = (($keep_old == true) ? $old_example : {action_id: $row.id, drafted: $drafted, approved: $approved_v})
            }

            var.update $examples {
              value = $examples|set:$key:$new_example
            }
          }
        }
      }
    }

    var $out {
      value = []
    }

    foreach ($order) {
      each as $o {
        var $n {
          value = ($tally|get:$o.key:null) ?? 0
        }

        var $ex {
          value = ($examples|get:$o.key:null) ?? {}
        }

        array.push $out {
          value = {action_type: $o.action_type, field: $o.field, edits: $n, pattern: ($n >= $min), example: $ex}
        }
      }
    }
  }

  response = {min_samples: $min, actions_read: ($rows|count), rows: $out}
}
