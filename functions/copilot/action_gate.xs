// COP-2 stories 02/05/08 — the approval gate for one copilot action. Called ONLY by journey/tool_gate (after who/what/where checks pass) when a tool declares an action type. People are never stopped here: levels apply to AI identities only. For an AI: person-only types (Publish version / Publish to live) are refused (E-COP-025); "own" proceeds; "tell" proceeds and lists the action for the owner; "wait" stores the exact tool input as a waiting copilot_action and refuses (E-COP-020) — nothing happens. An approved action runs when the copilot calls the same tool again with approval_id: it must be this account's, this tool's, approved or edited, not run before (unique claim, E-COP-030), for the same map and action type, and the input must match exactly what the owner approved (E-COP-027). The gate only claims the run; the tool marks it executed or failed with copilot/action_finish after its own write. Never throws: returns proceed + a code + a message; tool_gate does the refusing. The payload is never logged.
function "copilot/action_gate" {
  input {
    int user_id?
    int account_id?
    text act_type? filters=trim
    text act_tool? filters=trim
    int act_map_id?
    int act_architecture_id?
    json act_payload?
    text act_summary? filters=trim
    int act_amount?
    bool act_has_amount?
    int act_approval_id?
    bool act_force_wait?
  }

  stack {
    var $proceed {
      value = true
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    var $level {
      value = "person"
    }

    var $action_id {
      value = 0
    }

    function.run "copilot/identity_for_user" {
      input = {user_id: $input.user_id}
    } as $ai

    // The business: what the tool named, else the map's own architecture.
    var $arch_id {
      value = $input.act_architecture_id
    }

    conditional {
      if ($arch_id == 0 && $input.act_map_id != 0) {
        db.query journey_map {
          where = $db.journey_map.id == $input.act_map_id
          return = {type: "single"}
          output = ["id", "journey_architecture"]
        } as $map_row

        var.update $arch_id {
          value = $map_row|get:"journey_architecture":0
        }
      }
    }

    // COP-9 story 06: "write its own skills" is set ONCE, on the copilot's own business (its
    // copilot home), whichever business the chat or run is about. A waiting skill change is filed
    // under that business's Approvals. No home = 0 = the type's default (the writer refuses anyway).
    conditional {
      if ($input.act_type == "skill_write") {
        db.query copilot_home {
          where = $db.copilot_home.account_id == $input.account_id && $input.account_id != 0
          return = {type: "single"}
        } as $skill_home

        var.update $arch_id {
          value = $skill_home|get:"journey_architecture_id":0
        }
      }
    }

    var $payload_obj {
      value = $input.act_payload ?? {}
    }

    // In the database's normal form, so it compares equal to a stored payload with the same
    // content (a json column re-orders keys on the way back — found live).
    function.run "copilot/canon_json" {
      input = {value: $payload_obj}
    } as $canon

    var $payload_json {
      value = $canon.text
    }

    conditional {
      if ($ai.is_ai == true) {
        function.run "copilot/action_level" {
          input = {
            journey_architecture_id: $arch_id
            action_type            : $input.act_type
            amount                 : $input.act_amount
            has_amount             : $input.act_has_amount
          }
        } as $lv

        var.update $level {
          value = $lv.effective_level
        }

        // COP-11 "suggest instead": a copilot change to a LOCKED skill always waits for the owner,
        // whatever the level. Forcing can only make an action wait, never let one through.
        var.update $level {
          value = (($input.act_force_wait == true) ? "wait" : $level)
        }

        conditional {
          // Never an AI: Publish version, Publish to live (decision D-4).
          if ($lv.person_only == true) {
            var.update $proceed {
              value = false
            }

            var.update $code {
              value = "E-COP-025"
            }

            var.update $message {
              value = "Only a person can do this. It is ready for the owner to do themselves. (E-COP-025)"
            }
          }

          // Running an action the owner already approved.
          elseif ($input.act_approval_id != 0) {
            db.query copilot_action {
              where = $db.copilot_action.id == $input.act_approval_id
              return = {type: "single"}
            } as $act

            var $act_id {
              value = $act|get:"id":0
            }

            var $act_account {
              value = $act|get:"account_id":0
            }

            var $act_tool {
              value = $act|get:"tool":""
            }

            var $act_status {
              value = $act|get:"status":""
            }

            var $approved_obj {
              value = $act|get:"approved_payload":null
            }

            var $approved_json {
              value = $approved_obj|json_encode
            }

            var $act_map {
              value = $act|get:"journey_map_id":0
            }

            var $act_type_stored {
              value = $act|get:"action_type":""
            }

            // COP-2 review fix: the approval is for this account, this tool, this map and this type.
            var $usable {
              value = ($act_id != 0 && $act_account == $input.account_id && $act_tool == $input.act_tool && $act_map == $input.act_map_id && $act_type_stored == $input.act_type)
            }

            conditional {
              if ($usable == false) {
                var.update $proceed {
                  value = false
                }

                var.update $code {
                  value = "E-COP-036"
                }

                var.update $message {
                  value = "That approval was not found for this tool. Nothing was done. (E-COP-036)"
                }
              }

              elseif ($act_status == "executed") {
                var.update $proceed {
                  value = false
                }

                var.update $code {
                  value = "E-COP-030"
                }

                var.update $message {
                  value = "That approved action has already been carried out. (E-COP-030)"
                }
              }

              elseif ($act_status != "approved" && $act_status != "edited") {
                var.update $proceed {
                  value = false
                }

                var.update $code {
                  value = "E-COP-027"
                }

                var.update $message {
                  value = "That action is not approved (it is " ~ $act_status ~ "). Nothing was done. (E-COP-027)"
                }
              }

              elseif ($approved_json != $payload_json) {
                var.update $proceed {
                  value = false
                }

                var.update $code {
                  value = "E-COP-027"
                }

                var.update $message {
                  value = "The input does not match what the owner approved. Send exactly the approved input. Nothing was done. (E-COP-027)"
                }
              }

              else {
                // Claim the single run. A second claim fails on the unique index.
                var $claimed {
                  value = false
                }

                try_catch {
                  try {
                    db.add copilot_action_claim {
                      data = {copilot_action_id: $act_id, kind: "execute", user_id: $input.user_id}
                    } as $claim

                    var.update $claimed {
                      value = true
                    }
                  }

                  catch {
                    var.update $claimed {
                      value = false
                    }
                  }
                }

                // COP-2 review fix: the claim stops a second run, but the item is NOT marked
                // executed here — the tool's own write has not happened yet. The tool calls
                // copilot/action_finish after its write (executed) or on failure (failed).
                conditional {
                  if ($claimed == true) {
                    var.update $action_id {
                      value = $act_id
                    }

                    var.update $level {
                      value = "approved"
                    }

                    function.run "ops/log_event" {
                      input = {
                        feature    : "COP-2"
                        step       : "action_started"
                        outcome    : "success"
                        severity   : "info"
                        error_code : ""
                        message    : "An approved copilot action started running."
                        user_id    : $input.user_id
                        account_id : $input.account_id
                        entity_type: "copilot_action"
                        entity_id  : $act_id
                        metadata   : {tool: $input.act_tool, action_type: $input.act_type}
                      }
                    } as $_exec_logged
                  }

                  else {
                    var.update $proceed {
                      value = false
                    }

                    var.update $code {
                      value = "E-COP-030"
                    }

                    var.update $message {
                      value = "That approved action has already been carried out. (E-COP-030)"
                    }
                  }
                }
              }
            }
          }

          // Runs, then tells you: do it, and list it for the owner.
          elseif ($level == "tell") {
            db.add copilot_action {
              data = {
                account_id             : $input.account_id
                journey_architecture_id: $arch_id
                journey_map_id         : $input.act_map_id
                requested_by_user_id   : $input.user_id
                action_type            : $input.act_type
                tool                   : $input.act_tool
                payload                : $payload_obj
                summary                : $input.act_summary
                amount                 : $input.act_amount
                status                 : "told"
                reason                 : ""
                reversible             : $lv.reversible
                updated_at             : "now"
              }
            } as $told

            var.update $action_id {
              value = $told.id
            }
          }

          // Waits for you: store it, do nothing.
          elseif ($level == "wait") {
            var.update $proceed {
              value = false
            }

            var.update $code {
              value = "E-COP-020"
            }

            // The newest allowed write on the target map now; a newer one at approval = out of date.
            db.query tool_call_log {
              where = $db.tool_call_log.journey_map_id == $input.act_map_id && $db.tool_call_log.kind == "write" && $db.tool_call_log.verdict == "allowed"
              sort = {id: "desc"}
              return = {type: "single"}
              output = ["id"]
            } as $last_write

            var $stale_marker {
              value = $last_write|get:"id":0
            }

            // The same waiting action already stored (same tool, map and input)? Reuse it.
            db.query copilot_action {
              where = $db.copilot_action.account_id == $input.account_id && $db.copilot_action.status == "waiting" && $db.copilot_action.tool == $input.act_tool && $db.copilot_action.journey_map_id == $input.act_map_id
              return = {type: "list"}
            } as $waiting_same

            var $dup_id {
              value = 0
            }

            foreach ($waiting_same) {
              each as $w {
                // The condition reads the loop item and a var set before the loop only (CLAUDE.md:
                // a var set earlier in the same iteration would silently drop this branch's write).
                conditional {
                  if ((($w.payload ?? {})|json_encode) == $payload_json) {
                    var.update $dup_id {
                      value = $w.id
                    }
                  }
                }
              }
            }

            var.update $action_id {
              value = $dup_id
            }

            // COP-2 review fix: already approved but the copilot called again without approval_id?
            // Point it at the approval instead of filing a new waiting item.
            db.query copilot_action {
              where = $db.copilot_action.account_id == $input.account_id && ($db.copilot_action.status == "approved" || $db.copilot_action.status == "edited") && $db.copilot_action.tool == $input.act_tool && $db.copilot_action.journey_map_id == $input.act_map_id
              return = {type: "list"}
            } as $approved_same

            var $approved_id {
              value = 0
            }

            foreach ($approved_same) {
              each as $ap {
                conditional {
                  if ((($ap.payload ?? {})|json_encode) == $payload_json) {
                    var.update $approved_id {
                      value = $ap.id
                    }
                  }
                }
              }
            }

            conditional {
              if ($approved_id != 0) {
                var.update $action_id {
                  value = $approved_id
                }
              }
            }

            conditional {
              if ($dup_id == 0 && $approved_id == 0) {
                db.add copilot_action {
                  data = {
                    account_id             : $input.account_id
                    journey_architecture_id: $arch_id
                    journey_map_id         : $input.act_map_id
                    requested_by_user_id   : $input.user_id
                    action_type            : $input.act_type
                    tool                   : $input.act_tool
                    payload                : $payload_obj
                    summary                : $input.act_summary
                    amount                 : $input.act_amount
                    status                 : "waiting"
                    reason                 : $lv.reason
                    stale_marker           : $stale_marker
                    reversible             : $lv.reversible
                    updated_at             : "now"
                  }
                } as $waiting

                var.update $action_id {
                  value = $waiting.id
                }

                function.run "ops/log_event" {
                  input = {
                    feature    : "COP-2"
                    step       : "action_waiting"
                    outcome    : "success"
                    severity   : "info"
                    error_code : ""
                    message    : "A copilot action is waiting for the owner."
                    user_id    : $input.user_id
                    account_id : $input.account_id
                    entity_type: "copilot_action"
                    entity_id  : $waiting.id
                    metadata   : {tool: $input.act_tool, action_type: $input.act_type}
                  }
                } as $_wait_logged
              }
            }

            var $action_id_text {
              value = $action_id|to_text
            }

            var.update $message {
              value = "Waiting for the owner's approval - nothing was done. It is item " ~ $action_id_text ~ " in Approvals. Tell the owner it is waiting. Once they approve, call this tool again with approval_id " ~ $action_id_text ~ " and exactly the approved input (use get_approval to read it). (E-COP-020)"
            }

            conditional {
              if ($approved_id != 0) {
                var.update $message {
                  value = "The owner already approved this - nothing was done yet. Call get_approval with approval_id " ~ $action_id_text ~ ", then call this tool again with approval_id " ~ $action_id_text ~ " and exactly the approved input. (E-COP-020)"
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    proceed  : $proceed
    code     : $code
    message  : $message
    level    : $level
    action_id: $action_id
  }
}
