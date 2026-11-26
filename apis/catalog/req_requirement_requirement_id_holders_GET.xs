// REQ-1 story 02 — See a requirement from the other side: everyone who holds it, and who holds it only until a date. Any account member may read. Another account's requirement is "not found" (E-REQ-006). Each holder carries the state on `on_date` (a plain date, default today; the answer is for THAT day, never a clock) from req/holding_state: held or not, ends soon (within 30 days), days left. `on_date` is text: an optional date input that is left out does not exist at all (CLAUDE.md). Profiles are looked up in the caller's account only. The loop only calls a function and pushes; its values come from the loop item.
query "requirement/{requirement_id}/holders" verb=GET {
  api_group = "catalog"
  auth = "user"

  input {
    int requirement_id filters=min:1
    text on_date? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $guard

    var $today {
      value = now|format_timestamp:"Y-m-d":"UTC"
    }

    var $day {
      value = (($input.on_date != "") ? $input.on_date : $today)
    }

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.requirement_id == $input.requirement_id && $db.agent_profile_requirement.account_id == $actor.account_id
      return = {type: "list"}
    } as $holdings

    var $profile_ids {
      value = [-1]
    }

    foreach ($holdings) {
      each as $h {
        array.push $profile_ids {
          value = $h.agent_profile_id
        }
      }
    }

    db.query agent_profile {
      where = $db.agent_profile.id in $profile_ids
      return = {type: "list"}
      output = ["id", "name", "kind", "is_eligible"]
    } as $profiles

    var $names {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($profiles) {
      each as $p {
        var.update $t {
          value = $p.id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $names {
          value = $names|set:$k:$p.name
        }
      }
    }

    var $out {
      value = []
    }

    var $nm {
      value = ""
    }

    foreach ($holdings) {
      each as $h {
        function.run "req/holding_state" {
          input = {held_until: $h.held_until, on_date: $day}
        } as $st

        var.update $t {
          value = $h.agent_profile_id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $nm {
          value = ($names|get:$k:null) ?? ""
        }

        array.push $out {
          value = {agent_profile_id: $h.agent_profile_id, name: $nm, held_until: $h.held_until, held: $st.held, ends_soon: $st.ends_soon, days_left: $st.days_left}
        }
      }
    }
  }

  response = {requirement: $guard.requirement, on_date: $day, holders: $out}
}
