// TAG-1 story 01 — delete a tag from the account. If maps carry it and confirm is not true, nothing is deleted and status "confirm_needed" comes back with the number of maps. With confirm, every link is deleted by its own id (db.del by field only removes the first match) and then the tag, in one transaction; the links are counted again afterwards. No map is ever touched.
function "tags/delete_tag" {
  input {
    int account_id
    int user_id
    int map_tag_id
    bool confirm?
  }

  stack {
    db.query map_tag {
      where = $db.map_tag.id == $input.map_tag_id && $db.map_tag.account_id == $input.account_id
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
      where = $db.journey_map_tag.map_tag_id == $tag_id
      return = {type: "list"}
    } as $links

    var $map_count {
      value = $links|count
    }

    var $status {
      value = "deleted"
    }

    var $left {
      value = 0
    }

    conditional {
      if ($map_count > 0 && $input.confirm != true) {
        var.update $status {
          value = "confirm_needed"
        }
      }

      else {
        db.transaction {
          stack {
            foreach ($links) {
              each as $l {
                db.del journey_map_tag {
                  field_name = "id"
                  field_value = $l.id
                }
              }
            }

            db.del map_tag {
              field_name = "id"
              field_value = $tag_id
            }
          }
        }

        db.query journey_map_tag {
          where = $db.journey_map_tag.map_tag_id == $tag_id
          return = {type: "count"}
        } as $still

        var.update $left {
          value = $still
        }

        function.run "ops/log_event" {
          input = {feature: "TAG-1", step: "tag_deleted", outcome: "success", severity: "info", error_code: "", message: "A tag was deleted. No map was changed.", user_id: $input.user_id, account_id: $input.account_id, entity_type: "map_tag", entity_id: $tag_id, correlation_id: "", duration_ms: 0, metadata: {maps: $map_count, links_left: $still}}
        } as $_ev
      }
    }
  }

  response = {status: $status, map_tag_id: $tag_id, name: ($tag|get:"name":""), map_count: $map_count, links_left: $left}
}
