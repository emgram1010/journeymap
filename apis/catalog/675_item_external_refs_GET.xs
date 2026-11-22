// SCALE-1 story 03 — the outside products this account has seen or linked: which catalog item each points at (0 = still to link), whether it is marked "not an item", its last seen name and how often it has appeared. Most-seen first, so the products that matter most are on top. to_link counts the ones that still need an answer. Only the caller's account.
query item_external_refs verb=GET {
  api_group = "catalog"
  auth = "user"

  input {
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    var $acct {
      value = $actor.account_id ?? 0
    }

    db.query item_external_ref {
      where = $db.item_external_ref.account_id == $acct && $acct != 0
      sort = {item_external_ref.seen_count: "desc"}
      return = {type: "list"}
    } as $refs

    var $rows {
      value = []
    }

    var $to_link {
      value = 0
    }

    foreach ($refs) {
      each as $r {
        array.push $rows {
          value = {ref_id: $r.id, source_system: $r.source_system, external_id: $r.external_id, external_name: $r.external_name, item_type_id: $r.item_type_id, not_an_item: $r.not_an_item, seen_count: $r.seen_count, last_seen_at: $r.last_seen_at}
        }

        conditional {
          if ($r.item_type_id == 0 && $r.not_an_item != true) {
            math.add $to_link {
              value = 1
            }
          }
        }
      }
    }
  }

  response = {refs: $rows, to_link: $to_link}
}
