// TAG-1 story 01 — take a tag off one map. The tag is named by id or by name (any case). Other maps keep the tag, and the tag itself stays in the account's list. A tag the map does not carry changes nothing. An unknown tag is "not found" (E-TAG-005), and so is another account's.
function "tags/remove_from_map" {
  input {
    int account_id
    int user_id
    int journey_map_id
    int map_tag_id?
    text name?
  }

  stack {
    var $key {
      value = ($input.name ?? "")|trim|lower
    }

    db.query map_tag {
      where = $db.map_tag.account_id == $input.account_id && (($input.map_tag_id != 0 && $db.map_tag.id == $input.map_tag_id) || ($input.map_tag_id == 0 && $db.map_tag.name_key == $key))
      return = {type: "single"}
    } as $tag

    var $tag_id {
      value = $tag|get:"id":0
    }

    precondition ($tag_id != 0 && $input.account_id != 0) {
      error_type = "notfound"
      error = "Tag not found. Call list_tags to see the tags that exist. (E-TAG-005)"
    }

    db.query journey_map_tag {
      where = $db.journey_map_tag.journey_map_id == $input.journey_map_id && $db.journey_map_tag.map_tag_id == $tag_id && $db.journey_map_tag.account_id == $input.account_id
      return = {type: "single"}
    } as $link

    var $link_id {
      value = $link|get:"id":0
    }

    var $removed {
      value = false
    }

    conditional {
      if ($link_id != 0) {
        db.del journey_map_tag {
          field_name = "id"
          field_value = $link_id
        }

        var.update $removed {
          value = true
        }

        function.run "ops/log_event" {
          input = {feature: "TAG-1", step: "tag_removed", outcome: "success", severity: "info", error_code: "", message: "A tag was removed from a map.", user_id: $input.user_id, account_id: $input.account_id, entity_type: "journey_map", entity_id: $input.journey_map_id, correlation_id: "", duration_ms: 0, metadata: {map_tag_id: $tag_id}}
        } as $_ev
      }
    }
  }

  response = {removed: $removed, map_tag_id: $tag_id, name: ($tag|get:"name":"")}
}
