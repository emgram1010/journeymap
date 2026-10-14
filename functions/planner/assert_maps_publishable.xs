// PLAN-1 (US-PLAN-1-02) — May these maps be attached to a template?
//
// TWO CONDITIONS, AND THE SECOND IS THE INTERESTING ONE:
//   1. the map belongs to this account (otherwise it is "not found",
//      the same answer a nonexistent id gets);
//   2. the map has at least one PUBLISHED version in
//      `journey_map_version` (PUB-1's table).
//
// A draft map has no frozen content, so a plan that accepted one
// would be promising work that does not exist yet and could change
// under it at any moment. PUB-1 exists precisely so there is a
// version to point at; this is the rule that makes the planner use it.
//
// Returns the first offending map and its title, so the caller can
// say "Publish 'Leads to Sales' first" rather than naming an id.
//
// Two passes (CLAUDE.md): pass 1 records each lookup as a field, pass
// 2 branches on the loop item.
function "planner/assert_maps_publishable" {
  input {
    int account_id filters=min:1
    json map_ids
  }

  stack {
    var $requested {
      value = $input.map_ids
    }

    var $ok {
      value = true
    }

    var $bad_reason {
      value = ""
    }

    var $bad_map_id {
      value = 0
    }

    var $bad_map_title {
      value = ""
    }

    conditional {
      if (($requested|count) > 0) {
        db.query journey_map {
          where = $db.journey_map.id in $requested && $db.journey_map.account_id == $input.account_id
          return = {type: "list"}
        } as $maps

        db.query journey_map_version {
          where = $db.journey_map_version.journey_map_id in $requested
          return = {type: "list"}
        } as $versions

        var $key {
          value = ""
        }

        var $owned {
          value = {}
        }

        foreach ($maps) {
          each as $m {
            var.update $key {
              value = $m.id|to_text
            }

            var.update $owned {
              value = $owned|set:$key:$m.title
            }
          }
        }

        var $published {
          value = {}
        }

        foreach ($versions) {
          each as $v {
            var.update $key {
              value = $v.journey_map_id|to_text
            }

            var.update $published {
              value = $published|set:$key:1
            }
          }
        }

        var $checks {
          value = []
        }

        foreach ($requested) {
          each as $mid {
            var.update $key {
              value = $mid|to_text
            }

            array.push $checks {
              value = {
                map_id     : $mid
                title      : ($owned|get:$key:null)
                has_version: ($published|get:$key:null)
              }
            }
          }
        }

        foreach ($checks) {
          each as $c {
            conditional {
              if ($c.title == null && $ok == true) {
                var.update $ok {
                  value = false
                }

                var.update $bad_reason {
                  value = "not_found"
                }

                var.update $bad_map_id {
                  value = $c.map_id
                }
              }
            }

            conditional {
              if ($c.title != null && $c.has_version == null && $ok == true) {
                var.update $ok {
                  value = false
                }

                var.update $bad_reason {
                  value = "not_published"
                }

                var.update $bad_map_id {
                  value = $c.map_id
                }

                var.update $bad_map_title {
                  value = $c.title
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    ok           : $ok
    reason       : $bad_reason
    map_id       : $bad_map_id
    map_title    : $bad_map_title
    checked_count: ($requested|count)
  }
}
