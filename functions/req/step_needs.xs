// REQ-1 story 05 — THE one question "what does this step need?", answered from the FROZEN needs of ONE published map version, by stage key and row key. Every caller that wants a step's needs calls this function (a build test fails if any other file reads journey_map_version_requirement). A job reads its needs through the version it is pinned to, like everything else about its steps: an edit to the map's draft never changes work already planned. A version published before this feature has no rows, so it answers "no needs", and its jobs behave exactly as they do today. Read-only. Returns each need with its requirement's CURRENT name (a rename shows everywhere) and whether the requirement is archived now; the strength is the frozen one.
function "req/step_needs" {
  input {
    int journey_map_version_id filters=min:1
    text stage_key filters=trim
    text lens_key filters=trim
  }

  stack {
    db.query journey_map_version_requirement {
      where = $db.journey_map_version_requirement.journey_map_version_id == $input.journey_map_version_id && $db.journey_map_version_requirement.stage_key == $input.stage_key && $db.journey_map_version_requirement.lens_key == $input.lens_key
      return = {type: "list"}
    } as $rows

    var $req_ids {
      value = [-1]
    }

    foreach ($rows) {
      each as $r {
        array.push $req_ids {
          value = $r.requirement_id
        }
      }
    }

    db.query requirement {
      where = $db.requirement.id in $req_ids
      return = {type: "list"}
      output = ["id", "name", "is_active"]
    } as $reqs

    var $name_of {
      value = {}
    }

    var $active_of {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($reqs) {
      each as $q {
        var.update $t {
          value = $q.id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $name_of {
          value = $name_of|set:$k:$q.name
        }

        var.update $active_of {
          value = $active_of|set:$k:$q.is_active
        }
      }
    }

    var $needs {
      value = []
    }

    var $nm {
      value = ""
    }

    var $act {
      value = true
    }

    var $hard_n {
      value = 0
    }

    var $soft_n {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $t {
          value = $r.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $nm {
          value = ($name_of|get:$k:null) ?? ""
        }

        var.update $act {
          value = ($active_of|get:$k:null) ?? true
        }

        var.update $hard_n {
          value = $hard_n + (($r.strength == "hard")|to_int)
        }

        var.update $soft_n {
          value = $soft_n + (($r.strength == "soft")|to_int)
        }

        array.push $needs {
          value = {requirement_id: $r.requirement_id, name: $nm, strength: $r.strength, archived: ($act == false)}
        }
      }
    }
  }

  response = {needs: $needs, hard: $hard_n, soft: $soft_n}
}
