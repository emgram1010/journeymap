// COP-5 story 01 - THE one answer to "may a copilot conversation about THIS business touch THIS plan?". A plan has no business of its own; it accepts maps. So: the plan must be in the caller's account, and every map it accepts must be in the conversation's business. A plan that accepts no map yet is allowed only for the identity that created it (so the copilot can fill a plan it just made, and cannot adopt an empty plan someone else made). Never throws: returns ok + reason ("not_found", "other_business", "empty_not_yours") + the plan row's dates and archived flag; the calling tool does the refusing. Used by every copilot planner tool, so the rule lives here once.
function "copilot/plan_in_business" {
  input {
    int account_id?
    int workspace_id?
    int architecture_id?
    int user_id?
  }

  stack {
    db.query planner_workspace {
      where = $db.planner_workspace.id == $input.workspace_id
      return = {type: "single"}
      output = ["id", "account_id", "created_by", "name", "is_archived", "planning_window_start", "planning_window_end"]
    } as $plan

    var $plan_id {
      value = ($plan|get:"id":0) ?? 0
    }

    var $plan_account {
      value = ($plan|get:"account_id":0) ?? 0
    }

    var $plan_creator {
      value = ($plan|get:"created_by":0) ?? 0
    }

    var $found {
      value = ($plan_id != 0 && $input.account_id != 0 && $plan_account == $input.account_id)
    }

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id", "journey_map_id"]
    } as $links

    var $map_ids {
      value = [-1]
    }

    foreach ($links) {
      each as $l {
        array.push $map_ids {
          value = $l.journey_map_id
        }
      }
    }

    var $total {
      value = $links|count
    }

    db.query journey_map {
      where = $db.journey_map.id in $map_ids && $db.journey_map.journey_architecture == $input.architecture_id && $db.journey_map.account_id == $input.account_id
      return = {type: "count"}
    } as $inside

    var $reason {
      value = ""
    }

    conditional {
      if ($found == false) {
        var.update $reason {
          value = "not_found"
        }
      }

      elseif ($input.architecture_id == 0 || $inside != $total) {
        var.update $reason {
          value = "other_business"
        }
      }

      elseif ($total == 0 && ($plan_creator == 0 || $plan_creator != $input.user_id)) {
        var.update $reason {
          value = "empty_not_yours"
        }
      }
    }

    // Final review R14: on a miss nothing about the plan is returned - not even its name - so
    // another account's plan can never be read through this answer.
    var $safe_name {
      value = ""
    }

    var $safe_archived {
      value = false
    }

    var $safe_count {
      value = 0
    }

    conditional {
      if ($found == true) {
        var.update $safe_name {
          value = (($plan|get:"name":"") ?? "")
        }

        var.update $safe_archived {
          value = (($plan|get:"is_archived":false) ?? false)
        }

        var.update $safe_count {
          value = $total
        }
      }
    }
  }

  response = {
    ok         : ($reason == "")
    reason     : $reason
    map_count  : $safe_count
    is_archived: $safe_archived
    name       : $safe_name
  }
}
