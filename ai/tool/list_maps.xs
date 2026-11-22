// IL-00-06: MCP tool — list journey maps for the authenticated scope.
// Optional filters: architecture_id, intent, status.
// TAG-1 story 02 (2026-11-21): tag, parent_map_id and top_level_only filters (all in the where
// clause, so the loop gained no branch), and each result now also carries tags and parent_map_id.
// With none of the new filters the same maps come back in the same order.
tool list_maps {
  instructions = "List journey maps. Optionally filter by architecture_id, intent (sop|automation|hybrid), status (draft|active|archived), map_level (architecture|actor-journey|atomic), tag (a tag's name, any case), parent_map_id (only the maps under that parent) or top_level_only (only maps with no parent). Filters combine: a map must match all of them. Returns an array of { id, title, intent, status, map_level, last_interaction_at, parent_map_id, tags }. An unknown tag returns an empty list. Call list_tags to see the tags that exist."

  input {
    int architecture_id?
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }
  
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    // LA-4: filter by Intelligence Layer map level.
    // Use map_level='atomic' to find L3 maps valid for leakage analysis.
    enum map_level? {
      values = ["architecture", "actor-journey", "atomic"]
    }

    text tag? filters=trim {
      description = "Optional. Only maps that carry this tag (any case)."
    }

    int parent_map_id? {
      description = "Optional. Only maps whose parent is this map. Leave 0 for no parent filter."
    }

    bool top_level_only? {
      description = "Optional. True lists only maps that have no parent."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "list_maps", kind: "read"}
    } as $cop1_gate

    // COP-1: a known caller sees only their own account's maps (journey/visible_map_ids, the
    // same rule the screens use). An unknown caller is only possible while the gate is in
    // report mode, and then the list is unchanged.
    var $caller_account {
      value = $cop1_gate.account_id
    }

    // COP-1 review (2026-11-14): never "see all". A caller with no account sees nothing
    // (journey/visible_map_ids), even if they hold the Intelligent Layer.
    var $see_all {
      value = false
    }

    // COP-3 story 02: in a conversation pinned to one business, only that business's maps.
    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    function.run "journey/visible_map_ids" {
      input = {caller_account_id: $caller_account}
    } as $visible

    var $visible_ids {
      value = $visible.map_ids
    }

    // TAG-1: the tag filter becomes a list of map ids (seeded with -1, so an unknown tag matches nothing).
    var $tag_key {
      value = ($input.tag ?? "")|trim|lower
    }

    var $has_tag {
      value = $tag_key != ""
    }

    db.query map_tag {
      where = $db.map_tag.account_id == $caller_account && $db.map_tag.name_key == $tag_key && $has_tag == true
      return = {type: "single"}
    } as $tag_row

    var $tag_id {
      value = $tag_row|get:"id":0
    }

    db.query journey_map_tag {
      where = $db.journey_map_tag.map_tag_id == $tag_id && $tag_id != 0 && $db.journey_map_tag.account_id == $caller_account
      return = {type: "list"}
    } as $tag_links

    var $tagged_ids {
      value = [-1]
    }

    foreach ($tag_links) {
      each as $tl {
        array.push $tagged_ids {
          value = $tl.journey_map_id
        }
      }
    }

    var $parent_filter {
      value = $input.parent_map_id ?? 0
    }

    var $top_only {
      value = $input.top_level_only == true
    }

    function.run "tags/overview" {
      input = {account_id: $caller_account, map_ids: $visible_ids}
    } as $tag_info

    var $by_map {
      value = $tag_info.by_map
    }

    var $mk {
      value = ""
    }

    var $m_tags {
      value = []
    }

    // Load the caller's maps — filter in-memory for flexibility
    db.query journey_map {
      where = (($see_all == true) || ($db.journey_map.id in $visible_ids)) && (($pin == 0) || ($db.journey_map.journey_architecture == $pin)) && (($has_tag == false) || ($db.journey_map.id in $tagged_ids)) && (($parent_filter == 0) || ($db.journey_map.parent_map_id == $parent_filter)) && (($top_only == false) || ($db.journey_map.parent_map_id == 0) || ($db.journey_map.parent_map_id == null))
      sort = {last_interaction_at: "desc"}
      return = {type: "list"}
    } as $all_maps
  
    var $results {
      value = []
    }
  
    foreach ($all_maps) {
      each as $m {
        var $pass {
          value = true
        }

        var.update $mk {
          value = "m:" ~ ($m.id|to_text)
        }

        var.update $m_tags {
          value = ($by_map|get:$mk:null) ?? []
        }
      
        conditional {
          if ($input.architecture_id != null && $m.journey_architecture != $input.architecture_id) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($input.intent != null && $m.intent != $input.intent) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($input.status != null && $m.status != $input.status) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($input.map_level != null && $m.map_level != $input.map_level) {
            var.update $pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($pass) {
            array.push $results {
              value = {
                id                 : $m.id
                title              : $m.title
                intent             : $m.intent
                status             : $m.status
                map_level          : $m.map_level
                last_interaction_at: $m.last_interaction_at
                parent_map_id      : ($m.parent_map_id ?? 0)
                tags               : $m_tags
              }
            }
          }
        }
      }
    }
  }

  response = {count: $results|count, results: $results}
  guid = "724YD1-Z9MFsuWxNDupqDWq4nL0"
}