// TAG-1 story 02 — the account's tags with how many maps the caller can see carry each. READ-ONLY. In a chat pinned to one business only that business's maps are counted; a tag none of them carries shows 0. Counts come from tags/overview, the same reader list_maps uses.
tool list_tags {
  instructions = "List the tags that exist, each with the number of maps you can see that carry it (0 when none do). Call this before tag_map so you reuse a tag instead of making a near-duplicate, and before list_maps with a tag filter. This only reads."

  input {
    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: 0, ticket: $input.ticket, tool: "list_tags", kind: "read"}
    } as $cop1_gate

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    function.run "journey/visible_map_ids" {
      input = {caller_account_id: $caller_account}
    } as $visible

    var $visible_ids {
      value = $visible.map_ids
    }

    db.query journey_map {
      where = ($db.journey_map.id in $visible_ids) && (($pin == 0) || ($db.journey_map.journey_architecture == $pin))
      return = {type: "list"}
      output = ["id"]
    } as $maps

    var $ids {
      value = [-1]
    }

    foreach ($maps) {
      each as $m {
        array.push $ids {
          value = $m.id
        }
      }
    }

    function.run "tags/overview" {
      input = {account_id: $caller_account, map_ids: $ids}
    } as $o
  }

  response = {count: ($o.tags|count), tags: $o.tags}
}
