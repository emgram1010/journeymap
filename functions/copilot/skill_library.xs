// COP-9 story 01 — loads the copilot's skill library ("how I work") for ONE business, as text for
// the copilot's context. The ONE loader: copilot chat (endpoint 643) and scheduled runs
// (copilot/run_for_business) both call it, so they always follow the same skills.
//
// Loaded: every item in this account that is not retired, not switched off for this business
// (copilot_skill_off), and not scoped to a DIFFERENT business. Items scoped to one map or one kind
// of work are loaded with that scope written next to them, so the copilot applies them only there.
// Exceptions are loaded only under a skill that is itself loaded. Trial items are marked "trial",
// so the copilot records them as such when it uses them (record_skill_used).
//
// Never stops the copilot: any failure is caught, logged as E-COP-080 (Health shows it) and the
// caller carries on with its built-in instructions (ok = false, empty text).
//
// Engine notes (CLAUDE.md): exclusions are written `not in` with a sentinel-seeded array; no
// conditional inside the loops (values are chosen with ternaries on the LOOP ITEM only).
function "copilot/skill_library" {
  input {
    int account_id
    int journey_architecture_id?

    // Scheduled runs log a success event; a chat turn does not (one event per message is noise).
    bool log_success?
  }

  stack {
    var $ok {
      value = true
    }

    var $text {
      value = ""
    }

    var $count {
      value = 0
    }

    var $trial_count {
      value = 0
    }

    var $off_ids {
      value = [-1]
    }

    var $skill_ids {
      value = [-1]
    }

    var $line {
      value = ""
    }

    var $err_msg {
      value = ""
    }

    try_catch {
      try {
        group {
          stack {
            db.query copilot_skill_off {
              where = $db.copilot_skill_off.account_id == $input.account_id && $db.copilot_skill_off.journey_architecture_id == $input.journey_architecture_id && $db.copilot_skill_off.is_off == true
              return = {type: "list"}
              output = ["skill_id"]
            } as $offs

            foreach ($offs) {
              each as $o {
                array.push $off_ids {
                  value = $o.skill_id
                }
              }
            }

            // Skills, lessons and links. A business-scoped item loads only in its own business.
            db.query copilot_skill {
              where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status != "retired" && $db.copilot_skill.kind != "exception" && $db.copilot_skill.id not in $off_ids && ($db.copilot_skill.scope_type != "business" || $db.copilot_skill.scope_ref_id == $input.journey_architecture_id)
              sort = {kind: "asc", id: "asc"}
              return = {type: "list"}
            } as $items

            foreach ($items) {
              each as $it {
                var.update $line {
                  value = "- [" ~ $it.kind ~ " #" ~ ($it.id|to_text) ~ ", v" ~ ($it.version_no|to_text) ~ (($it.status == "trial") ? ", trial" : "") ~ "] " ~ $it.title ~ (($it.scope_type == "business") ? " (this business only)" : (($it.scope_type == "map") ? (" (only for map #" ~ ($it.scope_ref_id|to_text) ~ ")") : (($it.scope_type == "work_kind") ? (" (only for: " ~ $it.scope_text ~ ")") : ""))) ~ (($it.kind == "link") ? (" (from skill #" ~ ($it.parent_skill_id|to_text) ~ " to skill #" ~ ($it.link_to_skill_id|to_text) ~ ")") : "") ~ ": " ~ $it.body ~ "\n"
                }

                var.update $text {
                  value = $text ~ $line
                }

                var.update $count {
                  value = $count + 1
                }

                var.update $trial_count {
                  value = $trial_count + (($it.status == "trial")|to_int)
                }

                array.push $skill_ids {
                  value = $it.id
                }
              }
            }

            // Exceptions: only under a skill that was loaded above.
            db.query copilot_skill {
              where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status != "retired" && $db.copilot_skill.kind == "exception" && $db.copilot_skill.id not in $off_ids && $db.copilot_skill.parent_skill_id in $skill_ids && ($db.copilot_skill.scope_type != "business" || $db.copilot_skill.scope_ref_id == $input.journey_architecture_id)
              sort = {parent_skill_id: "asc", id: "asc"}
              return = {type: "list"}
            } as $exceptions

            foreach ($exceptions) {
              each as $ex {
                var.update $line {
                  value = "- [exception #" ~ ($ex.id|to_text) ~ " on skill #" ~ ($ex.parent_skill_id|to_text) ~ ", v" ~ ($ex.version_no|to_text) ~ (($ex.status == "trial") ? ", trial" : "") ~ "] " ~ $ex.title ~ (($ex.scope_type == "business") ? " (this business only)" : (($ex.scope_type == "map") ? (" (only for map #" ~ ($ex.scope_ref_id|to_text) ~ ")") : (($ex.scope_type == "work_kind") ? (" (only for: " ~ $ex.scope_text ~ ")") : ""))) ~ ". WHEN: " ~ $ex.condition_text ~ ". THEN: " ~ $ex.body ~ "\n"
                }

                var.update $text {
                  value = $text ~ $line
                }

                var.update $count {
                  value = $count + 1
                }

                var.update $trial_count {
                  value = $trial_count + (($ex.status == "trial")|to_int)
                }
              }
            }

            var.update $text {
              value = $text|substr:0:24000
            }
          }
        }
      }

      catch {
        var $lib_caught {
          value = $error
        }

        var.update $err_msg {
          value = ($lib_caught|get:"message":"unknown")
        }

        var.update $ok {
          value = false
        }

        var.update $text {
          value = ""
        }
      }
    }

    conditional {
      if ($ok == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-9"
            step       : "skills_load"
            outcome    : "failure"
            severity   : "warn"
            error_code : "E-COP-080"
            message    : "The copilot couldn't read its skills; it used its built-in instructions."
            user_id    : 0
            account_id : $input.account_id
            entity_type: "journey_architecture"
            entity_id  : $input.journey_architecture_id
            metadata   : {reason: $err_msg}
          }
        } as $_fail_logged
      }

      elseif ($input.log_success == true) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-9"
            step       : "skills_load"
            outcome    : "success"
            severity   : "info"
            error_code : ""
            message    : "The copilot loaded its skills."
            user_id    : 0
            account_id : $input.account_id
            entity_type: "journey_architecture"
            entity_id  : $input.journey_architecture_id
            metadata   : {count: $count, trial_count: $trial_count}
          }
        } as $_ok_logged
      }
    }
  }

  response = {ok: $ok, text: $text, count: $count, trial_count: $trial_count}
}
