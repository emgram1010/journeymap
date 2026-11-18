// COP-9 story 04 — one-click undo for a skill-library item: puts an earlier version's FULL content
// back (text, "when", scope, links and status, so undoing a retire brings the item back) and saves
// that as a NEW version (change "undo", undo_of_version_no = the version restored). Nothing is ever
// lost: the version being undone stays in the history. Loads on the next chat or run.
//
// Called only by POST copilot/skill_undo (a signed-in admin, never an AI identity). The account is
// the admin's own, never taken from the request. Only text / int / enum columns are patched (the
// json history row is only ever inserted), so a patch fully replaces and nothing is merged.
// A version that is not in the history, or is the current one, is refused (E-COP-087); a failed
// write is logged and raised as E-COP-085. Either way the item keeps its latest version.
function "copilot/skill_undo" {
  input {
    int account_id
    int actor_user_id
    int skill_id
    int restore_version_no
    text reason? filters=trim
  }

  stack {
    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0
      return = {type: "single"}
    } as $cur

    var $cur_id {
      value = $cur|get:"id":0
    }

    var $cur_version {
      value = ($cur|get:"version_no":0) ?? 0
    }

    db.query copilot_skill_version {
      where = $db.copilot_skill_version.skill_id == $cur_id && $cur_id != 0 && $db.copilot_skill_version.version_no == $input.restore_version_no
      return = {type: "single"}
    } as $target

    var $target_id {
      value = $target|get:"id":0
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($cur_id == 0 || $target_id == 0) {
        var.update $reject_msg {
          value = "That version can't be put back: it doesn't exist or is already the current one. Nothing was changed. (E-COP-087)"
        }
      }

      elseif ($input.restore_version_no == $cur_version) {
        var.update $reject_msg {
          value = "That version can't be put back: it doesn't exist or is already the current one. Nothing was changed. (E-COP-087)"
        }
      }
    }

    conditional {
      if ($reject_msg != "") {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-9"
            step       : "skill_undo"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-COP-087"
            message    : $reject_msg
            user_id    : $input.actor_user_id
            account_id : $input.account_id
            entity_type: "copilot_skill"
            entity_id  : $input.skill_id
            metadata   : {restore_version_no: $input.restore_version_no}
          }
        } as $_rejected_logged
      }
    }

    precondition ($reject_msg == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $content {
      value = $target|get:"content":null
    }

    var $c_status {
      value = ($content|get:"status":"trial") ?? "trial"
    }

    var $c_title {
      value = ($content|get:"title":"") ?? ""
    }

    var $c_body {
      value = ($content|get:"body":"") ?? ""
    }

    var $c_condition {
      value = ($content|get:"condition_text":"") ?? ""
    }

    var $c_parent {
      value = ($content|get:"parent_skill_id":0) ?? 0
    }

    var $c_link {
      value = ($content|get:"link_to_skill_id":0) ?? 0
    }

    var $c_scope_type {
      value = ($content|get:"scope_type":"all") ?? "all"
    }

    var $c_scope_ref {
      value = ($content|get:"scope_ref_id":0) ?? 0
    }

    var $c_scope_text {
      value = ($content|get:"scope_text":"") ?? ""
    }

    var $next_version {
      value = $cur_version + 1
    }

    var $map_id {
      value = ($cur|get:"journey_map_id":0) ?? 0
    }

    var $map_title {
      value = "Skill: " ~ $c_title
    }

    var $undo_reason {
      value = (($input.reason != "") ? $input.reason : ("Put back version " ~ ($input.restore_version_no|to_text)))
    }

    var $write_ok {
      value = false
    }

    try_catch {
      try {
        db.transaction {
          stack {
            db.patch copilot_skill {
              field_name = "id"
              field_value = $cur_id
              data = {
                updated_at        : "now"
                status            : $c_status
                title             : $c_title
                body              : $c_body
                condition_text    : $c_condition
                parent_skill_id   : $c_parent
                link_to_skill_id  : $c_link
                scope_type        : $c_scope_type
                scope_ref_id      : $c_scope_ref
                scope_text        : $c_scope_text
                version_no        : $next_version
                updated_by_user_id: $input.actor_user_id
              }
            } as $_patched

            conditional {
              if ($map_id != 0) {
                db.patch journey_map {
                  field_name = "id"
                  field_value = $map_id
                  data = {updated_at: "now", title: $map_title, journey_scope: $c_body}
                } as $_map_patched
              }
            }

            db.add copilot_skill_version {
              data = {
                skill_id          : $cur_id
                account_id        : $input.account_id
                version_no        : $next_version
                change            : "undo"
                changed_by        : "owner"
                changed_by_user_id: $input.actor_user_id
                reason            : $undo_reason
                content           : $content
                copilot_run_id    : 0
                conversation_id   : 0
                undo_of_version_no: $input.restore_version_no
              }
            } as $_version

            var.update $write_ok {
              value = true
            }
          }
        }
      }

      catch {
        var.update $write_ok {
          value = false
        }
      }
    }

    conditional {
      if ($write_ok == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-9"
            step       : "skill_undo"
            outcome    : "failure"
            severity   : "error"
            error_code : "E-COP-085"
            message    : "A skill change could not be undone; the skill keeps its latest version."
            user_id    : $input.actor_user_id
            account_id : $input.account_id
            entity_type: "copilot_skill"
            entity_id  : $cur_id
            metadata   : {restore_version_no: $input.restore_version_no, next_version: $next_version}
          }
        } as $_failed_logged
      }
    }

    precondition ($write_ok == true) {
      error_type = "inputerror"
      error = "That change couldn't be undone. Nothing was changed; try again. (E-COP-085)"
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-9"
        step       : "skill_undo"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "A skill was put back to an earlier version."
        user_id    : $input.actor_user_id
        account_id : $input.account_id
        entity_type: "copilot_skill"
        entity_id  : $cur_id
        metadata   : {restore_version_no: $input.restore_version_no, version_no: $next_version}
      }
    } as $_ok_logged
  }

  response = {skill_id: $cur_id, version_no: $next_version, restored_version_no: $input.restore_version_no, status: $c_status}
}
