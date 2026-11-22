// TAG-1 story 01 — take a tag off one map. Other maps keep it and the tag stays in the account's list. Never changes the map itself.
tool untag_map {
  instructions = "Take a tag off one map. Pass the tag's name (any case). Other maps keep the tag, and the tag stays in the list. removed false means the map did not carry it. An unknown tag is refused: call list_tags to see the tags that exist. This never changes the map, its cells or its versions."

  input {
    int journey_map_id filters=min:1
    text name filters=trim {
      description = "The tag's name."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, journey_architecture_id: 0, ticket: $input.ticket, tool: "untag_map", kind: "write"}
    } as $cop1_gate

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($caller_user != 0 && $caller_account != 0) {
      error_type = "accessdenied"
      error = "Sign in to change a map's tags. (E-SEC-020)"
    }

    function.run "tags/remove_from_map" {
      input = {account_id: $caller_account, user_id: $caller_user, journey_map_id: $input.journey_map_id, map_tag_id: 0, name: $input.name}
    } as $r
  }

  response = {removed: $r.removed, map_tag_id: $r.map_tag_id, name: $r.name}
}
