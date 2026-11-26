// REQ-1 story 01 — The account's list of requirements, with how many places use each (steps of a map, people, published versions). Any account member may read; archived ones are left out unless `include_archived` is true (an omitted bool reads as false, which is the safe default here). The three usage tallies are three queries for the whole account, summed by id in a map pre-seeded with zero (a `|get` with a variable key ignores its default), never one query per row. Another account's list is never visible: every query is scoped by the caller's account.
query "requirement" verb=GET {
  api_group = "catalog"
  auth = "user"

  input {
    bool include_archived?
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query requirement {
      where = $db.requirement.account_id == $actor.account_id && ($input.include_archived == true || $db.requirement.is_active == true)
      sort = {requirement.name_key: "asc"}
      return = {type: "list"}
    } as $rows

    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.account_id == $actor.account_id
      return = {type: "list"}
      output = ["requirement_id"]
    } as $step_rows

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.account_id == $actor.account_id
      return = {type: "list"}
      output = ["requirement_id"]
    } as $holding_rows

    db.query journey_map_version_requirement {
      where = $db.journey_map_version_requirement.account_id == $actor.account_id
      return = {type: "list"}
      output = ["requirement_id"]
    } as $frozen_rows

    var $steps {
      value = {}
    }

    var $people {
      value = {}
    }

    var $versions {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    var $n {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $t {
          value = $r.id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $steps {
          value = $steps|set:$k:0
        }

        var.update $people {
          value = $people|set:$k:0
        }

        var.update $versions {
          value = $versions|set:$k:0
        }
      }
    }

    foreach ($step_rows) {
      each as $s {
        var.update $t {
          value = $s.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $n {
          value = (($steps|get:$k:null) ?? 0) + 1
        }

        var.update $steps {
          value = $steps|set:$k:$n
        }
      }
    }

    foreach ($holding_rows) {
      each as $h {
        var.update $t {
          value = $h.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $n {
          value = (($people|get:$k:null) ?? 0) + 1
        }

        var.update $people {
          value = $people|set:$k:$n
        }
      }
    }

    foreach ($frozen_rows) {
      each as $f {
        var.update $t {
          value = $f.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $n {
          value = (($versions|get:$k:null) ?? 0) + 1
        }

        var.update $versions {
          value = $versions|set:$k:$n
        }
      }
    }

    var $out {
      value = []
    }

    var $ns {
      value = 0
    }

    var $np {
      value = 0
    }

    var $nv {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $t {
          value = $r.id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $ns {
          value = ($steps|get:$k:null) ?? 0
        }

        var.update $np {
          value = ($people|get:$k:null) ?? 0
        }

        var.update $nv {
          value = ($versions|get:$k:null) ?? 0
        }

        array.push $out {
          value = {id: $r.id, name: $r.name, description: $r.description, is_active: $r.is_active, used_by_steps: $ns, held_by_people: $np, in_versions: $nv}
        }
      }
    }
  }

  response = {requirements: $out, limit: 200}
}
