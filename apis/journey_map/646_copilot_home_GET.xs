// COP-3 story 01 — the copilot's own "how I work" business for the signed-in person's account:
// whether it exists, its architecture id and its maps (shown "Copilot's own"). Also says whether
// the account has a copilot at all, so the panel can explain what to do first.
query "copilot/home" verb=GET {
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

    db.query ai_identity {
      where = $db.ai_identity.account_id == $account_id && $account_id != 0
      return = {type: "single"}
      output = ["id", "user_id", "name"]
    } as $ident

    db.query copilot_home {
      where = $db.copilot_home.account_id == $account_id && $account_id != 0
      return = {type: "single"}
    } as $home

    var $home_arch {
      value = $home|get:"journey_architecture_id":0
    }

    db.query journey_map {
      where = $db.journey_map.journey_architecture == $home_arch && $home_arch != 0
      sort = {created_at: "asc"}
      return = {type: "list"}
      output = ["id", "title", "status"]
    } as $maps
  }

  response = {
    has_copilot            : (($ident|get:"id":0) != 0)
    copilot_name           : ($ident|get:"name":"")
    has_home               : ($home_arch != 0)
    journey_architecture_id: $home_arch
    maps                   : $maps
  }
  tags = ["cop-3"]
}
