// REPEAT-2 story 03 (rewrites the held PLN-3 draft, which knew 3 of the 13 tables a plan now owns) — Delete a plan and everything that hangs off it, in ONE all-or-nothing transaction. WRITE-ONLY HELPER: it does not decide whether deleting is allowed. The caller proves the plan is the caller's (planner/assert_workspace), that the caller is an admin person, and that the plan has no history (planner/delete_check). History tables (plan_publication, plan_change_log, live_day_addition, activity_log, work_item_origin, work_item_exception, work_item_unmatched_line, order_route) are never touched here: a plan that has any of them is refused before this runs. EVERY ROW IS DELETED BY ITS OWN ID: a delete by a shared field removes only the first match (CLAUDE.md, confirmed on db.patch), which would orphan every other child. Every list is read first, outside the transaction, from the query's real rows; no id list with a -1 seed is ever looped over by a delete (the seeded lists below are only used inside `in` filters). Children first, the plan last, so nothing ever points at a row that is already gone. The plan's own plan_repeat row (it is a repeated copy) goes too, which frees that date for a new repeat; rows where this plan is the SOURCE stay, so its copies still know where they came from (repeat/history shows the original as gone). Returns how many rows of each kind were deleted.
function "planner/delete_workspace_cascade" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $tasks

    var $task_ids {
      value = [-1]
    }

    foreach ($tasks) {
      each as $t {
        array.push $task_ids {
          value = $t.id
        }
      }
    }

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $jobs

    var $job_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id in $job_ids
      return = {type: "list"}
      output = ["id"]
    } as $steps

    var $step_ids {
      value = [-1]
    }

    foreach ($steps) {
      each as $s {
        array.push $step_ids {
          value = $s.id
        }
      }
    }

    db.query planner_task_review {
      where = $db.planner_task_review.workspace_id == $input.workspace_id || $db.planner_task_review.planner_task_id in $task_ids
      return = {type: "list"}
      output = ["id"]
    } as $reviews

    db.query planner_task_start_override {
      where = $db.planner_task_start_override.planner_task_id in $task_ids
      return = {type: "list"}
      output = ["id"]
    } as $overrides

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.planner_task_id in $task_ids || $db.planner_task_work_task.work_task_id in $step_ids
      return = {type: "list"}
      output = ["id"]
    } as $links

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $timelines

    db.query work_item_line {
      where = $db.work_item_line.work_item_id in $job_ids
      return = {type: "list"}
      output = ["id"]
    } as $lines

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id in $job_ids
      return = {type: "list"}
      output = ["id"]
    } as $windows

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $agents

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $maps

    db.query plan_repeat {
      where = $db.plan_repeat.new_workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $repeats

    db.transaction {
      stack {
        foreach ($reviews) {
          each as $r {
            db.del planner_task_review {
              field_name = "id"
              field_value = $r.id
            }
          }
        }

        foreach ($overrides) {
          each as $o {
            db.del planner_task_start_override {
              field_name = "id"
              field_value = $o.id
            }
          }
        }

        foreach ($links) {
          each as $l {
            db.del planner_task_work_task {
              field_name = "id"
              field_value = $l.id
            }
          }
        }

        foreach ($tasks) {
          each as $t {
            db.del planner_task {
              field_name = "id"
              field_value = $t.id
            }
          }
        }

        foreach ($timelines) {
          each as $tl {
            db.del planner_timeline {
              field_name = "id"
              field_value = $tl.id
            }
          }
        }

        foreach ($lines) {
          each as $ln {
            db.del work_item_line {
              field_name = "id"
              field_value = $ln.id
            }
          }
        }

        foreach ($windows) {
          each as $w {
            db.del work_item_time_window {
              field_name = "id"
              field_value = $w.id
            }
          }
        }

        foreach ($steps) {
          each as $s {
            db.del work_task {
              field_name = "id"
              field_value = $s.id
            }
          }
        }

        foreach ($jobs) {
          each as $j {
            db.del work_item {
              field_name = "id"
              field_value = $j.id
            }
          }
        }

        foreach ($agents) {
          each as $a {
            db.del planner_agent {
              field_name = "id"
              field_value = $a.id
            }
          }
        }

        foreach ($maps) {
          each as $m {
            db.del planner_workspace_map {
              field_name = "id"
              field_value = $m.id
            }
          }
        }

        foreach ($repeats) {
          each as $pr {
            db.del plan_repeat {
              field_name = "id"
              field_value = $pr.id
            }
          }
        }

        db.del planner_workspace {
          field_name = "id"
          field_value = $input.workspace_id
        }
      }
    }

    var $deleted {
      value = {reviews: ($reviews|count), start_overrides: ($overrides|count), slot_links: ($links|count), slots: ($tasks|count), days: ($timelines|count), lines: ($lines|count), windows: ($windows|count), steps: ($steps|count), jobs: ($jobs|count), people: ($agents|count), maps: ($maps|count), repeat_rows: ($repeats|count)}
    }
  }

  response = {deleted: $deleted}
}
