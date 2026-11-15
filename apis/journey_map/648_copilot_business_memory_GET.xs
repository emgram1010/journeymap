// COP-4 stories 01/04/06 — "What the copilot knows" for one business: its goals, its notes and
// the labels of its maps (kind, how made, sources, researched or tested). Any signed-in person in
// the account with the Intelligent Layer (this group's middleware) may read it.
query "copilot/business_memory" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id?
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

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    precondition ($input.journey_architecture_id != 0 && ($arch|get:"account_id":0) == $account_id && $account_id != 0) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    db.query copilot_goal {
      where = $db.copilot_goal.account_id == $account_id && $db.copilot_goal.journey_architecture_id == $input.journey_architecture_id
      sort = {created_at: "desc"}
      return = {type: "list"}
    } as $goals

    db.query copilot_note {
      where = $db.copilot_note.account_id == $account_id && $db.copilot_note.journey_architecture_id == $input.journey_architecture_id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $notes

    db.query copilot_map_profile {
      where = $db.copilot_map_profile.account_id == $account_id && $db.copilot_map_profile.journey_architecture_id == $input.journey_architecture_id
      return = {type: "list"}
    } as $profiles
  }

  response = {journey_architecture_id: $input.journey_architecture_id, goals: $goals, notes: $notes, map_profiles: $profiles}
  tags = ["cop-4"]
}
