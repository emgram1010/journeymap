// COP-9 story 04 — the history of one skill-library item, newest first: every version with who
// changed it (copilot or owner), why, the run or chat it came from, and the full content, so the
// screen can say what changed in plain words and offer Undo. Only an item in the person's own
// account (anything else answers "not found" with E-COP-081, the same as an item outside its own business). Read-only.
query "copilot/skill_versions" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int skill_id?
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $me

    var $account_id {
      value = $me|get:"account_id":0
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $db.copilot_skill.account_id == $account_id && $account_id != 0
      return = {type: "single"}
      output = ["id", "version_no"]
    } as $skill

    var $skill_found {
      value = $skill|get:"id":0
    }

    precondition ($skill_found != 0) {
      error_type = "notfound"
      error = "The copilot can only write skills in its own business, 'how I work'. (E-COP-081)"
    }

    db.query copilot_skill_version {
      where = $db.copilot_skill_version.skill_id == $skill_found
      sort = {copilot_skill_version.version_no: "desc"}
      return = {type: "list"}
      output = ["id", "created_at", "version_no", "change", "changed_by", "changed_by_user_id", "reason", "content", "copilot_run_id", "conversation_id", "undo_of_version_no"]
    } as $versions
  }

  response = {skill_id: $skill_found, current_version_no: ($skill|get:"version_no":0), versions: $versions}
  tags = ["cop-9"]
}
