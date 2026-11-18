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
// COP-11: a LOCKED item is marked "locked" so the copilot follows it but only suggests changes.
// work_kinds (optional): only items tagged with one of those kinds, plus "general" and untagged ones.
// No list = every kind, exactly as before. The load is capped at max_load_words (settings, default
// 4000, counted as about 6 characters a word): trusted items first, then the rest, and what did not fit
// is counted in left_out and logged as copilot.library.load_trimmed.
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
    text[] work_kinds?
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

    var $left_out {
      value = 0
    }

    var $off_ids {
      value = [-1]
    }

    var $skill_ids {
      value = [-1]
    }

    var $allowed_kinds {
      value = ["general"]
    }

    var $lock_map {
      value = {}
    }

    var $line {
      value = ""
    }

    var $lk {
      value = ""
    }

    var $is_lk {
      value = false
    }

    var $keep {
      value = true
    }

    var $len {
      value = 0
    }

    var $used {
      value = 0
    }

    var $budget {
      value = 24000
    }

    var $err_msg {
      value = ""
    }

    try_catch {
      try {
        group {
          stack {
            // ── COP-11 settings: the word limit ──
            db.query copilot_library_setting {
              where = $db.copilot_library_setting.account_id == $input.account_id && $input.account_id != 0
              return = {type: "single"}
            } as $lib_setting

            var $words_raw {
              value = ($lib_setting|get:"max_load_words":0) ?? 0
            }

            var.update $budget {
              value = ((($words_raw != 0) ? $words_raw : 4000) * 6)
            }

            // ── COP-11: the kinds this caller wants, and which items are locked ──
            var $use_kinds {
              value = (($input.work_kinds|count) > 0)
            }

            foreach ($input.work_kinds) {
              each as $wk {
                array.push $allowed_kinds {
                  value = $wk
                }
              }
            }

            db.query copilot_skill_meta {
              where = $db.copilot_skill_meta.account_id == $input.account_id && $input.account_id != 0 && $use_kinds && $db.copilot_skill_meta.work_kind not in $allowed_kinds
              return = {type: "list"}
              output = ["skill_id"]
            } as $wrong_kind

            foreach ($wrong_kind) {
              each as $wrk {
                array.push $off_ids {
                  value = $wrk.skill_id
                }
              }
            }

            db.query copilot_skill_meta {
              where = $db.copilot_skill_meta.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill_meta.is_locked == true
              return = {type: "list"}
              output = ["skill_id"]
            } as $locked_rows

            foreach ($locked_rows) {
              each as $lr {
                var.update $lk {
                  value = "k" ~ ($lr.skill_id|to_text)
                }

                var.update $lock_map {
                  value = $lock_map|set:$lk:true
                }
              }
            }

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
            // Trusted first, so if the word limit bites it is the trial items that wait.
            db.query copilot_skill {
              where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status != "retired" && $db.copilot_skill.kind != "exception" && $db.copilot_skill.id not in $off_ids && ($db.copilot_skill.scope_type != "business" || $db.copilot_skill.scope_ref_id == $input.journey_architecture_id)
              sort = {status: "desc", kind: "asc", id: "asc"}
              return = {type: "list"}
            } as $items

            foreach ($items) {
              each as $it {
                var.update $lk {
                  value = "k" ~ ($it.id|to_text)
                }

                var.update $is_lk {
                  value = (($lock_map|get:$lk:null) == true)
                }

                var.update $line {
                  value = "- [" ~ $it.kind ~ " #" ~ ($it.id|to_text) ~ ", v" ~ ($it.version_no|to_text) ~ (($it.status == "trial") ? ", trial" : "") ~ ($is_lk ? ", locked" : "") ~ "] " ~ $it.title ~ (($it.scope_type == "business") ? " (this business only)" : (($it.scope_type == "map") ? (" (only for map #" ~ ($it.scope_ref_id|to_text) ~ ")") : (($it.scope_type == "work_kind") ? (" (only for: " ~ $it.scope_text ~ ")") : ""))) ~ (($it.kind == "link") ? (" (from skill #" ~ ($it.parent_skill_id|to_text) ~ " to skill #" ~ ($it.link_to_skill_id|to_text) ~ ")") : "") ~ ": " ~ $it.body ~ "\n"
                }

                var.update $len {
                  value = $line|strlen
                }

                var.update $keep {
                  value = (($used + $len) <= $budget)
                }

                var.update $text {
                  value = $text ~ ($keep ? $line : "")
                }

                var.update $used {
                  value = $used + ($keep ? $len : 0)
                }

                var.update $count {
                  value = $count + ($keep|to_int)
                }

                var.update $left_out {
                  value = $left_out + (1 - ($keep|to_int))
                }

                var.update $trial_count {
                  value = $trial_count + (($it.status == "trial")|to_int) * ($keep|to_int)
                }

                array.push $skill_ids {
                  value = ($keep ? $it.id : -1)
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
                var.update $lk {
                  value = "k" ~ ($ex.id|to_text)
                }

                var.update $is_lk {
                  value = (($lock_map|get:$lk:null) == true)
                }

                var.update $line {
                  value = "- [exception #" ~ ($ex.id|to_text) ~ " on skill #" ~ ($ex.parent_skill_id|to_text) ~ ", v" ~ ($ex.version_no|to_text) ~ (($ex.status == "trial") ? ", trial" : "") ~ ($is_lk ? ", locked" : "") ~ "] " ~ $ex.title ~ (($ex.scope_type == "business") ? " (this business only)" : (($ex.scope_type == "map") ? (" (only for map #" ~ ($ex.scope_ref_id|to_text) ~ ")") : (($ex.scope_type == "work_kind") ? (" (only for: " ~ $ex.scope_text ~ ")") : ""))) ~ ". WHEN: " ~ $ex.condition_text ~ ". THEN: " ~ $ex.body ~ "\n"
                }

                var.update $len {
                  value = $line|strlen
                }

                var.update $keep {
                  value = (($used + $len) <= $budget)
                }

                var.update $text {
                  value = $text ~ ($keep ? $line : "")
                }

                var.update $used {
                  value = $used + ($keep ? $len : 0)
                }

                var.update $count {
                  value = $count + ($keep|to_int)
                }

                var.update $left_out {
                  value = $left_out + (1 - ($keep|to_int))
                }

                var.update $trial_count {
                  value = $trial_count + (($ex.status == "trial")|to_int) * ($keep|to_int)
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
            metadata   : {count: $count, trial_count: $trial_count, left_out: $left_out}
          }
        } as $_ok_logged
      }
    }

    conditional {
      if ($ok == true && $left_out > 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-11"
            step       : "copilot.library.load_trimmed"
            outcome    : "success"
            severity   : "warn"
            error_code : ""
            message    : "Some skills did not fit the load limit and were left out of this run."
            user_id    : 0
            account_id : $input.account_id
            entity_type: "journey_architecture"
            entity_id  : $input.journey_architecture_id
            metadata   : {count: $count, left_out: $left_out}
          }
        } as $_trim_logged
      }
    }
  }

  response = {ok: $ok, text: $text, count: $count, trial_count: $trial_count, left_out: $left_out}
}
