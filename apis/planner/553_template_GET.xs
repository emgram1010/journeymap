// PLAN-1 (US-PLAN-1-02) — The account's plan templates.
// PLAN-3 (US-PLAN-3-02) — now also carries each template's agent
// roster, same two-query-for-the-whole-list shape as the maps below.
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

        // PLAN-3 — same shape, one level down, for the agent roster.
        db.query plan_template_agent {
          where = $db.plan_template_agent.plan_template_id in $ids
          return = {type: "list"}
        } as $agent_links

        var $profile_ids {
          value = []
        }

        foreach ($agent_links) {
          each as $al {
            array.push $profile_ids {
              value = $al.agent_profile_id
            }
          }
        }

        var $profile_names {
          value = {}
        }

        var $puid {
          value = ""
        }

        conditional {
          if (($profile_ids|count) > 0) {
            db.query agent_profile {
              where = $db.agent_profile.id in $profile_ids
              return = {type: "list"}
            } as $profiles

            var $puser_ids {
              value = []
            }

            foreach ($profiles) {
              each as $p {
                conditional {
                  if ($p.user_id != 0) {
                    array.push $puser_ids {
                      value = $p.user_id
                    }
                  }
                }
              }
            }

            var $user_names {
              value = {}
            }

            conditional {
              if (($puser_ids|count) > 0) {
                db.query user {
                  where = $db.user.id in $puser_ids
                  return = {type: "list"}
                } as $owners

                foreach ($owners) {
                  each as $u {
                    var.update $puid {
                      value = $u.id|to_text
                    }

                    var.update $user_names {
                      value = $user_names|set:$puid:$u.name
                    }
                  }
                }
              }
            }

            var $pname {
              value = ""
            }

            foreach ($profiles) {
              each as $p {
                var.update $key {
                  value = $p.id|to_text
                }

                var.update $pname {
                  value = $p.name
                }

                conditional {
                  if ($p.user_id != 0) {
                    var.update $puid {
                      value = $p.user_id|to_text
                    }

                    var.update $pname {
                      value = ($user_names|get:$puid:"")
                    }
                  }
                }

                var.update $profile_names {
                  value = $profile_names|set:$key:$pname
                }
              }
            }
          }
        }

        var $by_template_agents {
          value = {}
        }

        foreach ($templates) {
          each as $t {
            var.update $key {
              value = $t.id|to_text
            }

            var.update $by_template_agents {
              value = $by_template_agents|set:$key:[]
            }
          }
        }

        var $abucket {
          value = []
        }

        foreach ($agent_links) {
          each as $al {
            var.update $key {
              value = $al.plan_template_id|to_text
            }

            var.update $abucket {
              value = $by_template_agents|get:$key:[]
            }

            var.update $puid {
              value = $al.agent_profile_id|to_text
            }

            array.push $abucket {
              value = {profile_id: $al.agent_profile_id, name: ($profile_names|get:$puid:null)}
            }

            var.update $by_template_agents {
              value = $by_template_agents|set:$key:$abucket
            }
          }
        }

        foreach ($templates) {
          each as $t {
            var.update $key {
              value = $t.id|to_text
            }

            array.push $result {
              value = {template: $t, maps: ($by_template|get:$key:[]), agents: ($by_template_agents|get:$key:[])}
            }
          }
        }
      }
    }
  }

  response = {templates: $result}
}
