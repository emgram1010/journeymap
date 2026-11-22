// TAG-1 story 01 — a cloned map carries the same tags as its source. Only links in the given account are copied, so a clone can never pick up another account's tag. Never throws for a missing source: it copies nothing.
function "tags/copy_links" {
  input {
    int account_id
    int user_id
    int source_map_id
    int new_map_id
  }

  stack {
    db.query journey_map_tag {
      where = $db.journey_map_tag.journey_map_id == $input.source_map_id && $db.journey_map_tag.account_id == $input.account_id && $input.account_id != 0 && $input.new_map_id != 0
      return = {type: "list"}
    } as $links

    foreach ($links) {
      each as $l {
        try_catch {
          try {
            db.add journey_map_tag {
              data = {created_at: "now", account_id: $input.account_id, journey_map_id: $input.new_map_id, map_tag_id: $l.map_tag_id, added_by_user_id: $input.user_id}
            } as $copy
          }

          catch {
            var $skipped {
              value = true
            }
          }
        }
      }
    }
  }

  response = {copied: ($links|count)}
}
