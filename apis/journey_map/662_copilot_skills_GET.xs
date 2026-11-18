// COP-9 stories 01/04 — the copilot's skill library ("how I work") for the signed-in person's
// account: every item (retired ones too, so the owner can bring one back) and the businesses each
// item is switched off for. The side tables' own read endpoint (the AUTH-1 rule: a side table needs
// its own GET or the screen never sees it). Read-only. Any signed-in person in the account with the
// Intelligent Layer (this group's middleware) may read it; changes are admin-only (skill_undo,
// skill_switch).
query "copilot/skills" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
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

    db.query copilot_home {
      where = $db.copilot_home.account_id == $account_id && $account_id != 0
      return = {type: "single"}
    } as $home

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $account_id && $account_id != 0
      sort = {copilot_skill.id: "asc"}
      return = {type: "list"}
      output = ["id", "updated_at", "journey_map_id", "kind", "status", "title", "body", "condition_text", "parent_skill_id", "link_to_skill_id", "scope_type", "scope_ref_id", "scope_text", "version_no"]
    } as $items

    db.query copilot_skill_off {
      where = $db.copilot_skill_off.account_id == $account_id && $account_id != 0 && $db.copilot_skill_off.is_off == true
      return = {type: "list"}
      output = ["skill_id", "journey_architecture_id"]
    } as $off
  }

  response = {
    home_architecture_id: ($home|get:"journey_architecture_id":0)
    items               : $items
    off                 : $off
  }
  tags = ["cop-9"]
}
