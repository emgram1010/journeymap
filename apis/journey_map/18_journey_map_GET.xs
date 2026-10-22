// Query journey_map records owned by the authenticated user.
// Architecture-scoped listing is handled by GET /journey_architecture/{id}/bundle.
//
// GAP-FIX W7 (2026-10-17) — each row now also carries
// `published_version_no` and `last_published_at`.
//
// WHY HERE AND NOT IN A NEW ENDPOINT: the planner's "add a map to this
// plan" picker was offering every `status == "active"` map and then
// watching the server refuse half of them with E-PLAN-004, because
// attaching a map requires a PUBLISHED VERSION and nothing in the list
// said which maps had one. The account-scoped, published-only search
// built for exactly this (endpoint 210) is permanently unreachable —
// `journey_map/{journey_map_id}` shadows the literal segment "search"
// (see CLAUDE.md) — so the fact is added to the list the picker can
// actually reach. The map editor's own list reads the same rows and
// ignores the two new fields.
//
// `null` means never published, and that is what a MISS returns here on
// purpose: `|get` with a variable key throws its default away on a miss
// (CLAUDE.md), and null is the answer we want, so the quirk is harmless
// by intent rather than by luck.
//
// The versions are fetched in ONE query for the whole list and sorted
// ASCENDING, so the last write into the tally map is the highest
// version number. No conditional is involved, which keeps it clear of
// the "branch on a var set earlier in the same iteration" trap.
query journey_map verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    db.query journey_map {
      where = $db.journey_map.owner_user == $auth.id
      return = {type: "list"}
    } as $model

    var $map_ids {
      value = []
    }

    foreach ($model) {
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

    var $out {
      value = []
    }

    var $vno {
      value = null
    }

    var $vat {
      value = null
    }

    var $row {
      value = null
    }

    foreach ($model) {
      each as $m2 {
        var.update $key {
          value = $m2.id|to_text
        }

        var.update $vno {
          value = $latest_no|get:$key:null
        }

        var.update $vat {
          value = $latest_at|get:$key:null
        }

        var.update $row {
          value = $m2|set:"published_version_no":$vno
        }

        var.update $row {
          value = $row|set:"last_published_at":$vat
        }

        array.push $out {
          value = $row
        }
      }
    }
  }

  response = $out
}
