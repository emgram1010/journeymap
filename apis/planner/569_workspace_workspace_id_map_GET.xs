// PLN-9 (US-PLN-9-06) — Which maps has this plan accepted?
//
// Needed because nothing else exposes it: `workspace/{id}/board` and
// `workspace/{id}` return agents/timelines/tasks/counts, never the
// accepted-map list a plan was created with (template/instance only
// returns a count at creation time). Without this read, the frontend
// has no way to show "maps already in this plan" before offering to
// add another one — exactly the gap AUTH-1's side-table lesson warns
// about (CLAUDE.md: a write path with no matching read leaves the UI
// silently blind to its own data).
//
// Same shape as `GET template`'s per-template map list, for one
// workspace instead of all of an account's templates.
query "workspace/{workspace_id}/map" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $links

    var $map_ids {
      value = []
    }

    foreach ($links) {
      each as $l {
        array.push $map_ids {
          value = $l.journey_map_id
        }
      }
    }

    var $titles {
      value = {}
    }

    var $key {
      value = ""
    }

    conditional {
      if (($map_ids|count) > 0) {
        db.query journey_map {
          where = $db.journey_map.id in $map_ids
          return = {type: "list"}
        } as $maps

        foreach ($maps) {
          each as $m {
            var.update $key {
              value = $m.id|to_text
            }

            var.update $titles {
              value = $titles|set:$key:$m.title
            }
          }
        }
      }
    }

    var $result {
      value = []
    }

    foreach ($links) {
      each as $l {
        var.update $key {
          value = $l.journey_map_id|to_text
        }

        array.push $result {
          value = {map_id: $l.journey_map_id, title: ($titles|get:$key:null)}
        }
      }
    }
  }

  response = {maps: $result}
}
