// COP-11 story 01 — an account admin locks or unlocks one skill-library item. A locked item is
// followed by the copilot but never changed by it (copilot/skill_write refuses, E-COP-089). The ONLY
// way a lock changes: a signed-in admin of the item's own account, never an AI identity (E-COP-092).
// No AI tool calls this or touches copilot_skill_meta.
//
// The change is recorded as a version (change "edit", changed_by owner, reason "locked" or
// "unlocked") so it shows in the item's history; the version number moves on by one, and the unique
// (skill_id, version_no) index is the race guard. Meta row is created if missing, never deleted.
query "copilot/skill_lock" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int skill_id?
    bool locked?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id : $auth.id
        step          : "copilot/skill_lock"
        entity_id     : 0
        correlation_id: ""
      }
    } as $admin_user

    function.run "copilot/assert_person_only" {
      input = {
        user_id    : $auth.id
        account_id : $admin_user.account_id
        step       : "copilot/skill_lock"
        entity_type: "copilot_skill"
        entity_id  : $input.skill_id
      }
    } as $_person

    var $account_id {
      value = $admin_user.account_id
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $db.copilot_skill.account_id == $account_id && $account_id != 0
      return = {type: "single"}
    } as $skill

    var $skill_id {
      value = $skill|get:"id":0
    }

    precondition ($skill_id != 0) {
      error_type = "inputerror"
      error = "The copilot can only write playbook entries in its own business, the Playbook. (E-COP-081)"
    }

    db.query copilot_skill_meta {
      where = $db.copilot_skill_meta.skill_id == $skill_id
      return = {type: "single"}
    } as $meta

    var $meta_id {
      value = $meta|get:"id":0
    }

    var $next_version {
      value = (($skill|get:"version_no":0) ?? 0) + 1
    }

    var $reason {
      value = (($input.locked == true) ? "locked" : "unlocked")
    }

    var $content {
      value = {}|set:"kind":$skill.kind|set:"status":$skill.status|set:"title":$skill.title|set:"body":$skill.body|set:"condition_text":$skill.condition_text|set:"parent_skill_id":$skill.parent_skill_id|set:"link_to_skill_id":$skill.link_to_skill_id|set:"scope_type":$skill.scope_type|set:"scope_ref_id":$skill.scope_ref_id|set:"scope_text":$skill.scope_text
    }

    var $ok {
      value = false
    }

    try_catch {
      try {
        db.transaction {
          stack {
            conditional {
              if ($meta_id == 0) {
                db.add copilot_skill_meta {
                  data = {updated_at: "now", skill_id: $skill_id, account_id: $account_id, is_locked: $input.locked, locked_by_user_id: $auth.id, locked_at: "now", work_kind: "general"}
                } as $_added
              }

              else {
                db.patch copilot_skill_meta {
                  field_name = "id"
                  field_value = $meta_id
                  data = {updated_at: "now", is_locked: $input.locked, locked_by_user_id: $auth.id, locked_at: "now"}
                } as $_patched
              }
            }

            db.patch copilot_skill {
              field_name = "id"
              field_value = $skill_id
              data = {updated_at: "now", version_no: $next_version, updated_by_user_id: $auth.id}
            } as $_skill_patched

            db.add copilot_skill_version {
              data = {
                skill_id          : $skill_id
                account_id        : $account_id
                version_no        : $next_version
                change            : "edit"
                changed_by        : "owner"
                changed_by_user_id: $auth.id
                reason            : $reason
                content           : $content
                copilot_run_id    : 0
                conversation_id   : 0
                undo_of_version_no: 0
              }
            } as $_version

            var.update $ok {
              value = true
            }
          }
        }
      }

      catch {
        var.update $ok {
          value = false
        }
      }
    }

    precondition ($ok) {
      error_type = "inputerror"
      error = "The lock could not be changed, perhaps because the item was changed at the same moment. Nothing was changed; reload and try again."
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-11"
        step       : (($input.locked == true) ? "copilot.skill.locked" : "copilot.skill.unlocked")
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "An owner changed the lock on a skill."
        user_id    : $auth.id
        account_id : $account_id
        entity_type: "copilot_skill"
        entity_id  : $skill_id
        metadata   : {locked: $input.locked, version_no: $next_version}
      }
    } as $_logged
  }

  response = {skill_id: $skill_id, locked: $input.locked, version_no: $next_version}
  tags = ["cop-11"]
}
