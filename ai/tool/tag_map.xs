// TAG-1 story 01 — put a tag on a map. A label beside the map: no cell, version or hash changes. One rule, in tags/add_to_map: any case is one tag, and a new name that looks like an existing tag creates nothing until create_new is true.
tool tag_map {
  instructions = "Put a tag on a map to group it by area (for example Ops or Onboarding). Upper and lower case are the same tag. Call list_tags first and reuse a tag that exists. If the name is new but looks like an existing tag, nothing is created: status is 'suggest' and suggestions lists the close tags. Use one of them, or call again with create_new true only if the owner really wants a new tag. status 'already' means the map had the tag. Tagging never changes the map, its cells or its versions. Limits: 20 tags a map, 200 an account, 40 characters a name."

  input {
    int journey_map_id filters=min:1
    text name filters=trim {
      description = "The tag, 1 to 40 characters."
    }

    bool create_new? {
      description = "Leave false. True creates a new tag even when a similar one exists."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, journey_architecture_id: 0, ticket: $input.ticket, tool: "tag_map", kind: "write"}
    } as $cop1_gate

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($caller_user != 0 && $caller_account != 0) {
      error_type = "accessdenied"
      error = "Sign in to tag a map. (E-SEC-020)"
    }

    function.run "tags/add_to_map" {
      input = {account_id: $caller_account, user_id: $caller_user, journey_map_id: $input.journey_map_id, name: $input.name, reuse_check: true, create_new: $input.create_new}
    } as $r

    var $hint {
      value = ""
    }

    conditional {
      if ($r.status == "suggest") {
        var.update $hint {
          value = "Nothing was created. A similar tag exists: use one from suggestions, or call again with create_new true."
        }
      }
    }
  }

  response = {
    status     : $r.status
    map_tag_id : $r.map_tag_id
    name       : $r.name
    created    : $r.created
    suggestions: $r.suggestions
    hint       : $hint
  }
}
