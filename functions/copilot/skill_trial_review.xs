// COP-9 story 05 — trial before trust. THE one place the trial rule lives (founder, 2026-11-19).
// Reviews every item on trial in ONE account:
//   - trusted when it was used at least trial_min_uses times (default 5), in at least 2 different
//     chats or scheduled runs, and the owner never overrode it;
//   - switched off (retired: kept, never deleted, Undo brings it back) when the owner overrode it
//     trial_max_overrides times (default 2).
// An override is an owner edit or Undo on the item. Pressing Lock / Unlock is recorded as an owner
// "edit" with reason "locked" / "unlocked" and is NOT an override.
// An item the rule already switched off once and the owner then brought back is exempt from the
// switch-off for good: bringing it back is the owner's decision (and Undo would otherwise be
// undone again every night).
//
// Every promotion and switch-off writes a version (changed_by "copilot", user 0: the system) and an
// event (copilot.skill.trusted / copilot.skill.trial_switched_off) that the weekly digest reads.
// One item failing (a race on its version number) does not stop the others; it is logged.
// dry_run = report only: the write passes are constrained to nothing, so nothing changes.
//
// Engine notes (CLAUDE.md): the per-item loop decides with ternaries only (no conditional reading a
// var updated in the same iteration); the writes happen in a second pass over a query constrained
// to the chosen ids; distinct chats/runs are counted as the keys of a map; no |contains on arrays.
function "copilot/skill_trial_review" {
  input {
    int account_id

    // true = only report what the rule WOULD do; nothing is written (for the owner's preview and tests).
    bool dry_run?
  }

  stack {
    db.query copilot_library_setting {
      where = $db.copilot_library_setting.account_id == $input.account_id && $input.account_id != 0
      return = {type: "single"}
    } as $setting

    var $min_raw {
      value = ($setting|get:"trial_min_uses":0) ?? 0
    }

    var $max_raw {
      value = ($setting|get:"trial_max_overrides":0) ?? 0
    }

    var $min_uses {
      value = (($min_raw != 0) ? $min_raw : 5)
    }

    var $max_overrides {
      value = (($max_raw != 0) ? $max_raw : 2)
    }

    var $override_changes {
      value = ["edit", "undo"]
    }

    var $lock_reasons {
      value = ["locked", "unlocked"]
    }

    var $switch_off_reason {
      value = "Trial rule: switched off because the owner overrode it. Kept; Undo brings it back."
    }

    var $trust_reason {
      value = "Trial rule: trusted after enough uses in different chats or runs, never overridden."
    }

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status == "trial"
      sort = {copilot_skill.id: "asc"}
      return = {type: "list"}
      output = ["id"]
    } as $trials

    var $promote_ids {
      value = [-1]
    }

    var $switch_ids {
      value = [-1]
    }

    var $report {
      value = []
    }

    var $ctx {
      value = {}
    }

    var $ck {
      value = ""
    }

    var $use_n {
      value = 0
    }

    var $ctx_n {
      value = 0
    }

    var $promote {
      value = false
    }

    var $switch {
      value = false
    }

    var $was_switched_off {
      value = false
    }

    foreach ($trials) {
      each as $t {
        db.query copilot_skill_use {
          where = $db.copilot_skill_use.account_id == $input.account_id && ($db.copilot_skill_use.skill_id == $t.id || $db.copilot_skill_use.exception_skill_id == $t.id)
          return = {type: "list"}
          output = ["conversation_id", "copilot_run_id"]
        } as $uses

        var.update $ctx {
          value = {}
        }

        foreach ($uses) {
          each as $u {
            var.update $ck {
              value = "c" ~ ($u.conversation_id|to_text) ~ "r" ~ ($u.copilot_run_id|to_text)
            }

            var.update $ctx {
              value = $ctx|set:$ck:true
            }
          }
        }

        var.update $use_n {
          value = $uses|count
        }

        var.update $ctx_n {
          value = $ctx|keys|count
        }

        db.query copilot_skill_version {
          where = $db.copilot_skill_version.skill_id == $t.id && $db.copilot_skill_version.changed_by == "owner" && $db.copilot_skill_version.change in $override_changes && $db.copilot_skill_version.reason not in $lock_reasons
          return = {type: "count"}
        } as $ov_n

        db.query copilot_skill_version {
          where = $db.copilot_skill_version.skill_id == $t.id && $db.copilot_skill_version.reason == $switch_off_reason
          return = {type: "count"}
        } as $off_before

        var.update $was_switched_off {
          value = ($off_before > 0)
        }

        var.update $promote {
          value = ($ov_n == 0 && $use_n >= $min_uses && $ctx_n >= 2)
        }

        var.update $switch {
          value = ($ov_n >= $max_overrides && $was_switched_off == false)
        }

        array.push $promote_ids {
          value = ($promote ? $t.id : -1)
        }

        array.push $switch_ids {
          value = ($switch ? $t.id : -1)
        }

        array.push $report {
          value = {skill_id: $t.id, uses: $use_n, chats_or_runs: $ctx_n, overrides: $ov_n, trusted: $promote, switched_off: $switch}
        }
      }
    }

    // ── Phase 2: the writes, over queries constrained to the chosen ids ──
    var $promoted {
      value = 0
    }

    var $switched {
      value = 0
    }

    var $failed {
      value = 0
    }

    var $next_v {
      value = 0
    }

    var $c_obj {
      value = {}
    }

    var $reviewed_n {
      value = $trials|count
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id in $promote_ids && $db.copilot_skill.status == "trial" && $db.copilot_skill.account_id == $input.account_id && $input.dry_run != true
      return = {type: "list"}
    } as $to_promote

    foreach ($to_promote) {
      each as $p {
        var.update $next_v {
          value = $p.version_no + 1
        }

        var.update $c_obj {
          value = {}|set:"kind":$p.kind|set:"status":"trusted"|set:"title":$p.title|set:"body":$p.body|set:"condition_text":$p.condition_text|set:"parent_skill_id":$p.parent_skill_id|set:"link_to_skill_id":$p.link_to_skill_id|set:"scope_type":$p.scope_type|set:"scope_ref_id":$p.scope_ref_id|set:"scope_text":$p.scope_text
        }

        try_catch {
          try {
            db.transaction {
              stack {
                db.patch copilot_skill {
                  field_name = "id"
                  field_value = $p.id
                  data = {updated_at: "now", status: "trusted", version_no: $next_v}
                } as $_p_patched

                db.add copilot_skill_version {
                  data = {
                    skill_id          : $p.id
                    account_id        : $input.account_id
                    version_no        : $next_v
                    change            : "edit"
                    changed_by        : "copilot"
                    changed_by_user_id: 0
                    reason            : $trust_reason
                    content           : $c_obj
                    copilot_run_id    : 0
                    conversation_id   : 0
                    undo_of_version_no: 0
                  }
                } as $_p_version
              }
            }

            var.update $promoted {
              value = $promoted + 1
            }

            function.run "ops/log_event" {
              input = {
                feature    : "COP-9"
                step       : "copilot.skill.trusted"
                outcome    : "success"
                severity   : "info"
                error_code : ""
                message    : "A skill passed its trial and is now trusted."
                user_id    : 0
                account_id : $input.account_id
                entity_type: "copilot_skill"
                entity_id  : $p.id
                metadata   : {title: $p.title, version_no: $next_v}
              }
            } as $_p_logged
          }

          catch {
            var.update $failed {
              value = $failed + 1
            }
          }
        }
      }
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id in $switch_ids && $db.copilot_skill.status == "trial" && $db.copilot_skill.account_id == $input.account_id && $input.dry_run != true
      return = {type: "list"}
    } as $to_switch

    foreach ($to_switch) {
      each as $s {
        var.update $next_v {
          value = $s.version_no + 1
        }

        var.update $c_obj {
          value = {}|set:"kind":$s.kind|set:"status":"retired"|set:"title":$s.title|set:"body":$s.body|set:"condition_text":$s.condition_text|set:"parent_skill_id":$s.parent_skill_id|set:"link_to_skill_id":$s.link_to_skill_id|set:"scope_type":$s.scope_type|set:"scope_ref_id":$s.scope_ref_id|set:"scope_text":$s.scope_text
        }

        try_catch {
          try {
            db.transaction {
              stack {
                db.patch copilot_skill {
                  field_name = "id"
                  field_value = $s.id
                  data = {updated_at: "now", status: "retired", version_no: $next_v}
                } as $_s_patched

                db.add copilot_skill_version {
                  data = {
                    skill_id          : $s.id
                    account_id        : $input.account_id
                    version_no        : $next_v
                    change            : "retire"
                    changed_by        : "copilot"
                    changed_by_user_id: 0
                    reason            : $switch_off_reason
                    content           : $c_obj
                    copilot_run_id    : 0
                    conversation_id   : 0
                    undo_of_version_no: 0
                  }
                } as $_s_version
              }
            }

            var.update $switched {
              value = $switched + 1
            }

            function.run "ops/log_event" {
              input = {
                feature    : "COP-9"
                step       : "copilot.skill.trial_switched_off"
                outcome    : "success"
                severity   : "warn"
                error_code : ""
                message    : "A skill on trial was switched off because the owner overrode it. It is kept; Undo brings it back."
                user_id    : 0
                account_id : $input.account_id
                entity_type: "copilot_skill"
                entity_id  : $s.id
                metadata   : {title: $s.title, version_no: $next_v}
              }
            } as $_s_logged
          }

          catch {
            var.update $failed {
              value = $failed + 1
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-9"
        step       : "skill_trial_review"
        outcome    : (($failed > 0) ? "failure" : "success")
        severity   : (($failed > 0) ? "warn" : "info")
        error_code : ""
        message    : "The trial rule reviewed the skills on trial."
        user_id    : 0
        account_id : $input.account_id
        entity_type: "account"
        entity_id  : $input.account_id
        metadata   : {dry_run: $input.dry_run, reviewed: $reviewed_n, promoted: $promoted, switched_off: $switched, failed: $failed, min_uses: $min_uses, max_overrides: $max_overrides}
      }
    } as $_summary_logged
  }

  response = {dry_run: $input.dry_run, reviewed: $report, promoted: $promoted, switched_off: $switched, failed: $failed, min_uses: $min_uses, max_overrides: $max_overrides}
}
