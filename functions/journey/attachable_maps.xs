// The maps a plan in this person's ACCOUNT could attach. Extracted 2026-11-14 (USR-2) from endpoint 578 so the Planner can read it from its OWN API group: once the Intelligent Layer is gated, a Planner-only person would otherwise be refused the list they need to attach a map. One body, two doors (journey-map 578 and the planner group's copy) — never two copies of the rule. Logic is 578's, unchanged: archived and soft-deleted maps are dropped; a draft is returned with published_version_no null so the picker can say "publish it first".
function "journey/attachable_maps" {
  input {
    int user_id filters=min:1
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $input.user_id
    } as $actor

    var $account_id {
      value = ($actor.account_id ?? 0)
    }

    precondition ($account_id != 0) {
      error_type = "notfound"
      error = "This login is not attached to an account yet."
    }

    db.query journey_map {
      where = $db.journey_map.account_id == $account_id && $db.journey_map.status != "archived"
      sort = {journey_map.title: "asc"}
      return = {type: "list"}
    } as $maps

    function.run "journey/deleted_map_ids" as $deleted

    var $map_ids {
      value = []
    }

    foreach ($maps) {
      each as $m {
        array.push $map_ids {
          value = $m.id
        }
      }
    }

    var $latest_no {
      value = {}
    }

    var $latest_at {
      value = {}
    }

    var $key {
      value = ""
    }

    // Sorted ASCENDING so the last write per map is its highest
    // version — no conditional, so nothing can silently discard it.
    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $map_ids
      sort = {journey_map_version.version_no: "asc"}
      return = {type: "list"}
    } as $versions

    foreach ($versions) {
      each as $v {
        var.update $key {
          value = $v.journey_map_id|to_text
        }

        var.update $latest_no {
          value = $latest_no|set:$key:$v.version_no
        }

        var.update $latest_at {
          value = $latest_at|set:$key:$v.published_at
        }
      }
    }

    var $results {
      value = []
    }

    var $vno {
      value = null
    }

    var $vat {
      value = null
    }

    var $is_deleted {
      value = null
    }

    foreach ($maps) {
      each as $m2 {
        var.update $key {
          value = $m2.id|to_text
        }

        // A miss returns null, which is the answer we want here —
        // `|get` with a variable key throws its default away
        // (CLAUDE.md), harmless by intent rather than by luck.
        var.update $vno {
          value = $latest_no|get:$key:null
        }

        var.update $vat {
          value = $latest_at|get:$key:null
        }

        var.update $is_deleted {
          value = $deleted.set|get:$key:null
        }

        conditional {
          if ($is_deleted == null) {
            array.push $results {
              value = {
                map_id              : $m2.id
                title               : $m2.title
                status              : $m2.status
                owner_user          : $m2.owner_user
                published_version_no: $vno
                last_published_at   : $vat
              }
            }
          }
        }
      }
    }
  }

  response = {
    account_id: $account_id
    count     : $results|count
    maps      : $results
  }
}
