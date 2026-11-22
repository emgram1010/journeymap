// TAG-1 story 01 — rename a tag for the whole account; every map that carries it shows the new name at once (the name lives in one row). If the new name is already another tag, nothing changes and status "merge_needed" comes back with that tag and the number of maps; called again with merge true, this tag's maps move to the other tag (a map that has both keeps one) and this tag is removed, all in one transaction.
function "tags/rename_tag" {
  input {
    int account_id
    int user_id
    int map_tag_id
    text name?
    bool merge?
  }

  stack {
    function.run "tags/tag_key" {
      input = {name: $input.name}
    } as $k

    precondition ($k.ok == true) {
      error_type = "inputerror"
      error = $k.message
    }

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

    var $key {
      value = $k.key
    }

    var $shown {
      value = $k.name
    }

    db.query map_tag {
      where = $db.map_tag.account_id == $input.account_id && $db.map_tag.name_key == $key && $db.map_tag.id != $tag_id
      return = {type: "single"}
    } as $other

    var $other_id {
      value = $other|get:"id":0
    }

    db.query journey_map_tag {
      where = $db.journey_map_tag.map_tag_id == $tag_id
      return = {type: "list"}
    } as $links

    var $status {
      value = "renamed"
    }

    var $moved {
      value = 0
    }

    conditional {
      if ($other_id == 0) {
        db.patch map_tag {
          field_name = "id"
          field_value = $tag_id
          data = {name: $shown, name_key: $key, updated_at: "now"}
        } as $patched
      }

      elseif ($input.merge != true) {
        var.update $status {
          value = "merge_needed"
        }
      }

      else {
        var.update $status {
          value = "merged"
        }

        // Which maps already carry the other tag: those links are dropped, the rest are moved.
        db.query journey_map_tag {
          where = $db.journey_map_tag.map_tag_id == $other_id
          return = {type: "list"}
        } as $other_links

        var $has_other {
          value = {}
        }

        var $mk {
          value = ""
        }

        foreach ($other_links) {
          each as $ol {
            var.update $mk {
              value = "m:" ~ ($ol.journey_map_id|to_text)
            }

            var.update $has_other {
              value = $has_other|set:$mk:1
            }
          }
        }

        var $staged {
          value = []
        }

        var $dup {
          value = 0
        }

        foreach ($links) {
          each as $l {
            var.update $mk {
              value = "m:" ~ ($l.journey_map_id|to_text)
            }

            var.update $dup {
              value = ($has_other|get:$mk:null) ?? 0
            }

            array.push $staged {
              value = {id: $l.id, dup: $dup}
            }
          }
        }

        db.transaction {
          stack {
            foreach ($staged) {
              each as $s {
                conditional {
                  if ($s.dup == 1) {
                    db.del journey_map_tag {
                      field_name = "id"
                      field_value = $s.id
                    }
                  }

                  else {
                    db.patch journey_map_tag {
                      field_name = "id"
                      field_value = $s.id
                      data = {map_tag_id: $other_id}
                    } as $moved_link
                  }
                }
              }
            }

            db.del map_tag {
              field_name = "id"
              field_value = $tag_id
            }
          }
        }

        var.update $moved {
          value = $links|count
        }
      }
    }

    conditional {
      if ($status != "merge_needed") {
        function.run "ops/log_event" {
          input = {feature: "TAG-1", step: "tag_renamed", outcome: "success", severity: "info", error_code: "", message: "A tag was renamed.", user_id: $input.user_id, account_id: $input.account_id, entity_type: "map_tag", entity_id: $tag_id, correlation_id: "", duration_ms: 0, metadata: {merged_into: $other_id, maps: ($links|count)}}
        } as $_ev
      }
    }
  }

  response = {status: $status, map_tag_id: $tag_id, name: $shown, other_tag_id: $other_id, other_name: ($other|get:"name":""), map_count: ($links|count)}
}
