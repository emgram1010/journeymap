// Gap-fix #1 (PLAN-3) — Would this template roster produce two agents
// with the same name in one plan?
//
// `planner_agent` is unique by (workspace_id, name). Instance creation
// copies each roster profile into a planner_agent under its display
// name (person: user.name; AI: the profile's own name), so two roster
// entries resolving to the same name would make "New plan from
// template" fail with a raw database error. This catches it at the
// moment someone adds the agent to the template, with a clear message.
//
// Names compare trimmed and lower-cased, matching how a person reads
// them. Ids are de-duplicated first (a profile already on the roster
// and passed again must not count twice).
//
// No conditional here reads a variable set earlier in the same loop
// iteration (CLAUDE.md): counts are seeded, then incremented, then
// read back into a plain array, and only the last loop branches — on
// its loop item.
function "planner/assert_roster_names_unique" {
  input {
    json existing_profile_ids
    json add_profile_ids
  }

  stack {
    var $idmap {
      value = {}
    }

    var $ikey {
      value = ""
    }

    foreach ($input.existing_profile_ids) {
      each as $pid {
        var.update $ikey {
          value = "p" ~ ($pid|to_text)
        }

        var.update $idmap {
          value = $idmap|set:$ikey:$pid
        }
      }
    }

    foreach ($input.add_profile_ids) {
      each as $pid {
        var.update $ikey {
          value = "p" ~ ($pid|to_text)
        }

        var.update $idmap {
          value = $idmap|set:$ikey:$pid
        }
      }
    }

    var $ids {
      value = $idmap|values
    }

    var $ok {
      value = true
    }

    var $duplicate_name {
      value = ""
    }

    conditional {
      if (($ids|count) > 1) {
        db.query agent_profile {
          where = $db.agent_profile.id in $ids
          return = {type: "list"}
        } as $profiles

        var $user_ids {
          value = []
        }

        foreach ($profiles) {
          each as $p {
            conditional {
              if ($p.user_id != 0) {
                array.push $user_ids {
                  value = $p.user_id
                }
              }
            }
          }
        }

        var $user_names {
          value = {}
        }

        var $ukey {
          value = ""
        }

        conditional {
          if (($user_ids|count) > 0) {
            db.query user {
              where = $db.user.id in $user_ids
              return = {type: "list"}
            } as $owners

            foreach ($owners) {
              each as $u {
                var.update $ukey {
                  value = $u.id|to_text
                }

                var.update $user_names {
                  value = $user_names|set:$ukey:$u.name
                }
              }
            }
          }
        }

        // Pass 1: each profile's display name and its comparison key.
        var $names {
          value = []
        }

        var $resolved {
          value = ""
        }

        var $nkey {
          value = ""
        }

        foreach ($profiles) {
          each as $p {
            var.update $resolved {
              value = $p.name
            }

            var.update $ukey {
              value = $p.user_id|to_text
            }

            conditional {
              if ($p.user_id != 0) {
                var.update $resolved {
                  value = ($user_names|get:$ukey:"")
                }
              }
            }

            var.update $nkey {
              value = "n:" ~ ($resolved|trim|lower)
            }

            array.push $names {
              value = {key: $nkey, display: $resolved}
            }
          }
        }

        // Pass 2: seed every key to 0, so the increment below always
        // reads an existing key (`|get` with a variable key drops its
        // default on a miss — CLAUDE.md).
        var $counts {
          value = {}
        }

        foreach ($names) {
          each as $n {
            var.update $counts {
              value = $counts|set:$n.key:0
            }
          }
        }

        var $prev {
          value = 0
        }

        var $next {
          value = 0
        }

        foreach ($names) {
          each as $n {
            var.update $prev {
              value = $counts|get:$n.key:0
            }

            var.update $next {
              value = $prev + 1
            }

            var.update $counts {
              value = $counts|set:$n.key:$next
            }
          }
        }

        // Pass 3: read the counts into a plain array.
        var $checks {
          value = []
        }

        foreach ($names) {
          each as $n {
            array.push $checks {
              value = {display: $n.display, count: ($counts|get:$n.key:0)}
            }
          }
        }

        // Pass 4: branch on the loop item only.
        foreach ($checks) {
          each as $c {
            conditional {
              if ($c.count > 1 && $ok == true) {
                var.update $ok {
                  value = false
                }

                var.update $duplicate_name {
                  value = $c.display
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    ok            : $ok
    duplicate_name: $duplicate_name
  }
}
