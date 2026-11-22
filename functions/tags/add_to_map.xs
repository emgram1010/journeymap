// TAG-1 story 01 — put a tag on a map. Reuses the account's tag when the name matches in any case; makes it when it is new. With reuse_check (AI callers) a new name that looks like an existing tag creates nothing and returns the close matches, unless create_new is true. Adding a tag a map already has changes nothing. Limits: 20 tags a map (E-TAG-003), 200 an account (E-TAG-004). The unique indexes decide a race; the loser reads the winner's row. Never touches the map, its cells or its versions.
function "tags/add_to_map" {
  input {
    int account_id
    int user_id
    int journey_map_id
    text name?
    bool reuse_check?
    bool create_new?
  }

  stack {
    function.run "tags/tag_key" {
      input = {name: $input.name}
    } as $k

    precondition ($k.ok == true) {
      error_type = "inputerror"
      error = $k.message
    }

    db.query journey_map {
      where = $db.journey_map.id == $input.journey_map_id && $db.journey_map.account_id == $input.account_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $map

    var $map_id {
      value = $map|get:"id":0
    }

    precondition ($map_id != 0 && $input.account_id != 0) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    var $key {
      value = $k.key
    }

    var $shown {
      value = $k.name
    }

    db.query map_tag {
      where = $db.map_tag.account_id == $input.account_id && $db.map_tag.name_key == $key
      return = {type: "single"}
    } as $found

    var $tag_id {
      value = $found|get:"id":0
    }

    var $tag_name {
      value = $found|get:"name":""
    }

    var $status {
      value = "added"
    }

    var $created {
      value = false
    }

    var $suggestions {
      value = []
    }

    conditional {
      if ($tag_id == 0 && $input.reuse_check == true && $input.create_new != true) {
        db.query map_tag {
          where = $db.map_tag.account_id == $input.account_id
          return = {type: "list"}
        } as $all_tags

        foreach ($all_tags) {
          each as $t {
            conditional {
              if (($t.name_key|contains:$key) || ($key|contains:$t.name_key)) {
                array.push $suggestions {
                  value = {map_tag_id: $t.id, name: $t.name}
                }
              }
            }
          }
        }

        conditional {
          if (($suggestions|count) > 0) {
            var.update $status {
              value = "suggest"
            }
          }
        }
      }
    }

    conditional {
      if ($status != "suggest" && $tag_id == 0) {
        db.query map_tag {
          where = $db.map_tag.account_id == $input.account_id
          return = {type: "count"}
        } as $tag_count

        precondition ($tag_count < 200) {
          error_type = "inputerror"
          error = "This account already has 200 tags, the most allowed. Reuse or delete one first. (E-TAG-004)"
        }

        try_catch {
          try {
            db.add map_tag {
              data = {created_at: "now", updated_at: "now", account_id: $input.account_id, name: $shown, name_key: $key, created_by_user_id: $input.user_id}
            } as $new_tag

            var.update $created {
              value = true
            }
          }

          catch {
            var.update $created {
              value = false
            }
          }
        }

        db.query map_tag {
          where = $db.map_tag.account_id == $input.account_id && $db.map_tag.name_key == $key
          return = {type: "single"}
        } as $after

        var.update $tag_id {
          value = $after|get:"id":0
        }

        var.update $tag_name {
          value = $after|get:"name":""
        }
      }
    }

    precondition ($status == "suggest" || $tag_id != 0) {
      error_type = "standard"
      error = "The tag could not be saved. Try again. (E-TAG-006)"
    }

    conditional {
      if ($status != "suggest") {
        db.query journey_map_tag {
          where = $db.journey_map_tag.journey_map_id == $input.journey_map_id && $db.journey_map_tag.map_tag_id == $tag_id
          return = {type: "single"}
        } as $link

        var $link_id {
          value = $link|get:"id":0
        }

        conditional {
          if ($link_id != 0) {
            var.update $status {
              value = "already"
            }
          }

          else {
            db.query journey_map_tag {
              where = $db.journey_map_tag.journey_map_id == $input.journey_map_id
              return = {type: "count"}
            } as $on_map

            precondition ($on_map < 20) {
              error_type = "inputerror"
              error = "This map already has 20 tags, the most allowed. Remove one first. (E-TAG-003)"
            }

            try_catch {
              try {
                db.add journey_map_tag {
                  data = {created_at: "now", account_id: $input.account_id, journey_map_id: $input.journey_map_id, map_tag_id: $tag_id, added_by_user_id: $input.user_id}
                } as $new_link
              }

              catch {
                var.update $status {
                  value = "already"
                }
              }
            }
          }
        }
      }
    }

    conditional {
      if ($status == "added") {
        function.run "ops/log_event" {
          input = {feature: "TAG-1", step: "tag_added", outcome: "success", severity: "info", error_code: "", message: "A tag was added to a map.", user_id: $input.user_id, account_id: $input.account_id, entity_type: "journey_map", entity_id: $input.journey_map_id, correlation_id: "", duration_ms: 0, metadata: {map_tag_id: $tag_id, tag_created: $created}}
        } as $_ev
      }
    }
  }

  response = {status: $status, map_tag_id: $tag_id, name: $tag_name, created: $created, suggestions: $suggestions}
}
