// COP-9 story 07 — the raw history behind "what I learned this week" for the signed-in person's
// account: every skill-library version written in the last `days` days (default 7, 1-31), each item's
// current version/title/status (so the screen knows where Undo is safe), and the copilot's refused skill
// writes from event_log (outcome "rejected", feature COP-9: hard limits, locks, duplicates, full library).
// Read-only. The sorting into flagged / collapsed lines is one pure function on the screen
// (skillsModel.buildDigest); Undo goes through the existing copilot/skill_undo.
query "copilot/skill_digest" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int days?
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

    // An omitted optional int arrives as 0 (CLAUDE.md): 0 = the default week.
    var $days {
      value = (($input.days != 0) ? $input.days : 7)
    }

    precondition ($days >= 1 && $days <= 31) {
      error_type = "inputerror"
      error = "Choose between 1 and 31 days."
    }

    var $now_ms {
      value = now|to_int
    }

    var $cutoff {
      value = $now_ms - ($days * 86400000)
    }

    db.query copilot_skill_version {
      where = $db.copilot_skill_version.account_id == $account_id && $account_id != 0 && $db.copilot_skill_version.created_at >= $cutoff
      sort = {copilot_skill_version.created_at: "desc"}
      return = {type: "list"}
      output = ["id", "created_at", "skill_id", "version_no", "change", "changed_by", "reason", "undo_of_version_no"]
    } as $versions

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $account_id && $account_id != 0
      return = {type: "list"}
      output = ["id", "title", "kind", "version_no", "status"]
    } as $skills

    db.query event_log {
      where = $db.event_log.account_id == $account_id && $account_id != 0 && $db.event_log.created_at >= $cutoff && $db.event_log.feature == "COP-9" && $db.event_log.outcome == "rejected"
      sort = {event_log.created_at: "desc"}
      return = {type: "list"}
      output = ["created_at", "error_code", "message", "step"]
    } as $refusals
  }

  response = {days: $days, versions: $versions, skills: $skills, refusals: $refusals}
  tags = ["cop-9"]
}
