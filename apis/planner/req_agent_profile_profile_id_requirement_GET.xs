// REQ-1 story 02 — What one person holds, on the lasting profile. Any member of the account may read. Another account's profile is "not found" (planner/assert_agent_profile resolves the profile's account through its login for a person, or its own column for an AI). Each holding carries the state ON `on_date` (a plain date, default today; the answer is for THAT day, never a clock) from req/holding_state, and whether its requirement is archived (an archived requirement still shows where it is already held). `on_date` is text: an optional date input that is left out does not exist at all (CLAUDE.md).
query "agent-profile/{agent_profile_id}/requirement" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int agent_profile_id filters=min:1
    text on_date? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_agent_profile" {
      input = {account_id: $actor.account_id, profile_id: $input.agent_profile_id}
    } as $guard

    var $today {
      value = now|format_timestamp:"Y-m-d":"UTC"
    }

    var $day {
      value = (($input.on_date != "") ? $input.on_date : $today)
    }

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.agent_profile_id == $input.agent_profile_id && $db.agent_profile_requirement.account_id == $actor.account_id
      return = {type: "list"}
    } as $holdings

    var $req_ids {
      value = [-1]
    }

    foreach ($holdings) {
      each as $h {
        array.push $req_ids {
          value = $h.requirement_id
        }
      }
    }

    db.query requirement {
      where = $db.requirement.id in $req_ids && $db.requirement.account_id == $actor.account_id
      return = {type: "list"}
      output = ["id", "name", "is_active"]
    } as $reqs

    var $names {
      value = {}
    }

    var $archived {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($reqs) {
      each as $r {
        var.update $t {
          value = $r.id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $names {
          value = $names|set:$k:$r.name
        }

        var.update $archived {
          value = $archived|set:$k:($r.is_active == false)
        }
      }
    }

    var $out {
      value = []
    }

    var $nm {
      value = ""
    }

    var $arch {
      value = false
    }

    foreach ($holdings) {
      each as $h {
        function.run "req/holding_state" {
          input = {held_until: $h.held_until, on_date: $day}
        } as $st

        var.update $t {
          value = $h.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $nm {
          value = ($names|get:$k:null) ?? ""
        }

        var.update $arch {
          value = ($archived|get:$k:null) ?? false
        }

        array.push $out {
          value = {requirement_id: $h.requirement_id, name: $nm, archived: $arch, held_until: $h.held_until, held: $st.held, ends_soon: $st.ends_soon, days_left: $st.days_left}
        }
      }
    }
  }

  response = {agent_profile_id: $input.agent_profile_id, on_date: $day, holdings: $out}
}
