// PLAN-1 (US-PLAN-1-02) — The account's plan templates.
//
// Archived templates are hidden unless asked for, the same rule the
// plan list uses: the default answer is "what can I start a plan
// from", not "every row that has ever existed".
//
// Each template carries its attached map ids and their titles, from
// two queries for the whole list rather than one per template.
query "template" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    bool include_archived?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query plan_template {
      where = $db.plan_template.account_id == $actor.account_id && ($input.include_archived == true || $db.plan_template.is_active == true)
      sort = {plan_template.created_at: "desc"}
      return = {type: "list"}
    } as $templates

    var $ids {
      value = []
    }

    foreach ($templates) {
      each as $t {
        array.push $ids {
          value = $t.id
        }
      }
    }

    var $result {
      value = []
    }

    conditional {
      if (($ids|count) > 0) {
        db.query plan_template_map {
          where = $db.plan_template_map.plan_template_id in $ids
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

        // Group the links by template, seeded so every lookup hits an
        // existing key (`|get` with a variable key ignores its default
        // on a miss — CLAUDE.md).
        var $by_template {
          value = {}
        }

        foreach ($templates) {
          each as $t {
            var.update $key {
              value = $t.id|to_text
            }

            var.update $by_template {
              value = $by_template|set:$key:[]
            }
          }
        }

        var $bucket {
          value = []
        }

        foreach ($links) {
          each as $l {
            var.update $key {
              value = $l.plan_template_id|to_text
            }

            var.update $bucket {
              value = $by_template|get:$key:[]
            }

            array.push $bucket {
              value = {map_id: $l.journey_map_id, title: ($titles|get:($l.journey_map_id|to_text):null)}
            }

            var.update $by_template {
              value = $by_template|set:$key:$bucket
            }
          }
        }

        foreach ($templates) {
          each as $t {
            var.update $key {
              value = $t.id|to_text
            }

            array.push $result {
              value = {template: $t, maps: ($by_template|get:$key:[])}
            }
          }
        }
      }
    }
  }

  response = {templates: $result}
}
