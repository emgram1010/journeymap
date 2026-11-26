// REQ-1 story 04 — Every need on a map's steps, in ONE read, for the map screen: a dedicated read for the SIDE table journey_cell_requirement (the cell read does not include it, so the screen would never show needs: the AUTH-1 lesson). Any member of the account who can open the map may read; another account's map is "not found". Each need carries the step (cell id, stage key, row key), the requirement's name and whether it is archived, and hard or soft. Also, per requirement used on this map, how many ACTIVE people hold it RIGHT NOW (profiles that may be put on a roster, the holding not yet ended on today's date): zero is shown as a plain warning on the step, never a block (the designer may be setting up before the people are recorded). The date of the work does not exist here, so "now" is today, from the date rule in req/holding_state. No branch reads a value set earlier in the same pass.
query "journey_map/{journey_map_id}/requirement" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/assert_map_owner" {
      input = {journey_map_id: $input.journey_map_id, caller_account_id: $actor.account_id, user_id: $auth.id, step: "map_needs_read"}
    } as $_owner

    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $rows

    var $cell_ids {
      value = [-1]
    }

    var $req_ids {
      value = [-1]
    }

    foreach ($rows) {
      each as $r {
        array.push $cell_ids {
          value = $r.journey_cell_id
        }

        array.push $req_ids {
          value = $r.requirement_id
        }
      }
    }

    db.query journey_cell {
      where = $db.journey_cell.id in $cell_ids
      return = {type: "list"}
      output = ["id", "stage", "lens"]
    } as $cells

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
      output = ["id", "key"]
    } as $stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
      output = ["id", "key"]
    } as $lenses

    db.query requirement {
      where = $db.requirement.id in $req_ids && $db.requirement.account_id == $actor.account_id
      return = {type: "list"}
      output = ["id", "name", "is_active"]
    } as $reqs

    var $stage_key {
      value = {}
    }

    var $lens_key {
      value = {}
    }

    var $cell_stage {
      value = {}
    }

    var $cell_lens {
      value = {}
    }

    var $req_name {
      value = {}
    }

    var $req_active {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($stages) {
      each as $s {
        var.update $t {
          value = $s.id|to_text
        }

        var.update $k {
          value = "s:" ~ $t
        }

        var.update $stage_key {
          value = $stage_key|set:$k:$s.key
        }
      }
    }

    foreach ($lenses) {
      each as $l {
        var.update $t {
          value = $l.id|to_text
        }

        var.update $k {
          value = "l:" ~ $t
        }

        var.update $lens_key {
          value = $lens_key|set:$k:$l.key
        }
      }
    }

    foreach ($cells) {
      each as $c {
        var.update $t {
          value = $c.id|to_text
        }

        var.update $k {
          value = "c:" ~ $t
        }

        var.update $cell_stage {
          value = $cell_stage|set:$k:$c.stage
        }

        var.update $cell_lens {
          value = $cell_lens|set:$k:$c.lens
        }
      }
    }

    foreach ($reqs) {
      each as $q {
        var.update $t {
          value = $q.id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $req_name {
          value = $req_name|set:$k:$q.name
        }

        var.update $req_active {
          value = $req_active|set:$k:$q.is_active
        }
      }
    }

    // People who hold each requirement used here: ACTIVE profiles, not ended today.
    var $today {
      value = now|format_timestamp:"Y-m-d":"UTC"
    }

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.requirement_id in $req_ids && $db.agent_profile_requirement.account_id == $actor.account_id
      return = {type: "list"}
    } as $holdings

    var $holder_profile_ids {
      value = [-1]
    }

    foreach ($holdings) {
      each as $h {
        array.push $holder_profile_ids {
          value = $h.agent_profile_id
        }
      }
    }

    db.query agent_profile {
      where = $db.agent_profile.id in $holder_profile_ids && $db.agent_profile.is_eligible == true
      return = {type: "list"}
      output = ["id"]
    } as $eligible

    var $eligible_set {
      value = {}
    }

    foreach ($eligible) {
      each as $e {
        var.update $t {
          value = $e.id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $eligible_set {
          value = $eligible_set|set:$k:1
        }
      }
    }

    var $now_count {
      value = {}
    }

    foreach ($req_ids) {
      each as $rid {
        var.update $t {
          value = $rid|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $now_count {
          value = $now_count|set:$k:0
        }
      }
    }

    var $is_elig {
      value = 0
    }

    var $n {
      value = 0
    }

    foreach ($holdings) {
      each as $h {
        function.run "req/holding_state" {
          input = {held_until: $h.held_until, on_date: $today}
        } as $st

        var.update $t {
          value = $h.agent_profile_id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $is_elig {
          value = ($eligible_set|get:$k:null) ?? 0
        }

        var.update $t {
          value = $h.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $n {
          value = (($now_count|get:$k:null) ?? 0) + ($is_elig * ($st.held|to_int))
        }

        var.update $now_count {
          value = $now_count|set:$k:$n
        }
      }
    }

    var $needs {
      value = []
    }

    var $cstage {
      value = 0
    }

    var $clens {
      value = 0
    }

    var $sk {
      value = ""
    }

    var $lk {
      value = ""
    }

    var $rn {
      value = ""
    }

    var $ra {
      value = true
    }

    var $holders {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $t {
          value = $r.journey_cell_id|to_text
        }

        var.update $k {
          value = "c:" ~ $t
        }

        var.update $cstage {
          value = ($cell_stage|get:$k:null) ?? 0
        }

        var.update $clens {
          value = ($cell_lens|get:$k:null) ?? 0
        }

        var.update $t {
          value = $cstage|to_text
        }

        var.update $k {
          value = "s:" ~ $t
        }

        var.update $sk {
          value = ($stage_key|get:$k:null) ?? ""
        }

        var.update $t {
          value = $clens|to_text
        }

        var.update $k {
          value = "l:" ~ $t
        }

        var.update $lk {
          value = ($lens_key|get:$k:null) ?? ""
        }

        var.update $t {
          value = $r.requirement_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t
        }

        var.update $rn {
          value = ($req_name|get:$k:null) ?? ""
        }

        var.update $ra {
          value = ($req_active|get:$k:null) ?? true
        }

        var.update $holders {
          value = ($now_count|get:$k:null) ?? 0
        }

        array.push $needs {
          value = {
            journey_cell_id: $r.journey_cell_id
            stage_key      : $sk
            lens_key       : $lk
            requirement_id : $r.requirement_id
            name           : $rn
            archived       : ($ra == false)
            strength       : $r.strength
            holders_now    : $holders
          }
        }
      }
    }
  }

  response = {journey_map_id: $input.journey_map_id, on_date: $today, needs: $needs}
}
