// REPEAT-1 story 06 — Where a plan came from, and what was made from it. Read-only. `repeated_from` is null for a plan that was not made by a repeat; otherwise it names the source, with `exists: false` when that plan has since been deleted (the link is a plain number in plan_repeat, never a blocker, so the repeated plan still opens). `repeated_to` lists the plans that still exist and were repeated from this one, earliest first, each with how many of its copied slots still need a look. Another account's plan is "not found" (planner/assert_workspace), and every plan_repeat row is read scoped to the caller's account. No conditional inside a loop: the open-mark tally is a map lookup on the loop item.
function "repeat/history" {
  input {
    int account_id
    int workspace_id
  }

  stack {
    function.run "planner/assert_workspace" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query plan_repeat {
      where = $db.plan_repeat.new_workspace_id == $input.workspace_id && $db.plan_repeat.account_id == $input.account_id
      return = {type: "single"}
    } as $made

    var $from_id {
      value = $made|get:"source_workspace_id":0
    }

    var $repeated_from {
      value = null
    }

    var $from_name {
      value = ""
    }

    var $from_exists {
      value = false
    }

    conditional {
      if ($from_id != 0) {
        db.query planner_workspace {
          where = $db.planner_workspace.id == $from_id && $db.planner_workspace.account_id == $input.account_id
          return = {type: "list"}
          output = ["id", "name"]
        } as $src_rows

        foreach ($src_rows) {
          each as $sr {
            var.update $from_name {
              value = $sr.name
            }

            var.update $from_exists {
              value = true
            }
          }
        }

        var.update $repeated_from {
          value = {workspace_id: $from_id, name: $from_name, exists: $from_exists}
        }
      }
    }

    db.query plan_repeat {
      where = $db.plan_repeat.source_workspace_id == $input.workspace_id && $db.plan_repeat.account_id == $input.account_id
      return = {type: "list"}
      output = ["new_workspace_id"]
    } as $children

    var $child_ids {
      value = [-1]
    }

    foreach ($children) {
      each as $c {
        array.push $child_ids {
          value = $c.new_workspace_id
        }
      }
    }

    db.query planner_workspace {
      where = $db.planner_workspace.id in $child_ids && $db.planner_workspace.account_id == $input.account_id
      return = {type: "list"}
      output = ["id", "name", "planning_window_start", "planning_window_end"]
      sort = {planner_workspace.planning_window_start: "asc", planner_workspace.id: "asc"}
    } as $child_ws

    db.query planner_task_review {
      where = $db.planner_task_review.workspace_id in $child_ids && $db.planner_task_review.account_id == $input.account_id
      return = {type: "list"}
      output = ["workspace_id", "cleared_at"]
    } as $marks

    var $open_by_ws {
      value = {}
    }

    var $key {
      value = ""
    }

    var $n {
      value = 0
    }

    foreach ($marks) {
      each as $m {
        var.update $key {
          value = "w:" ~ ($m.workspace_id|to_text)
        }

        var.update $n {
          value = (($open_by_ws|get:$key:null) ?? 0) + (($m.cleared_at == 0)|to_int)
        }

        var.update $open_by_ws {
          value = $open_by_ws|set:$key:$n
        }
      }
    }

    var $repeated_to {
      value = []
    }

    var $open_n {
      value = 0
    }

    foreach ($child_ws) {
      each as $w {
        var.update $key {
          value = "w:" ~ ($w.id|to_text)
        }

        var.update $open_n {
          value = ($open_by_ws|get:$key:null) ?? 0
        }

        array.push $repeated_to {
          value = {workspace_id: $w.id, name: $w.name, start_date: $w.planning_window_start, end_date: $w.planning_window_end, needs_review: $open_n}
        }
      }
    }
  }

  response = {
    repeated_from: $repeated_from
    repeated_to  : $repeated_to
  }
}
