// REPEAT-1 story 05 — THE one place a "needs review" mark is cleared. Write-only helper: no tenancy check, no logging, no refusal. The CALLER has already proved the actor is a person and the slot or day is theirs (a function cannot see $auth), and logs plan.review_cleared. Clears one slot's mark (planner_task_id), or every mark on a day's slots (timeline_id), or both. A cleared mark is KEPT as history (cleared_at, cleared_by, cleared_how); it is never deleted here. `how` is one | day | publish | moved. Only marks that are still open are touched: the query takes every mark for the slots, and the loop branches on the loop item's own cleared_at (a conditional that reads a var updated in the same pass silently loses its writes, CLAUDE.md). Each mark is patched by its own id (a patch by a non-unique field touches one row). Safe inside the caller's db.transaction (a write-only function.run rolls back with it, EXC-1), which is how Publish to live uses it. Every input is passed explicitly by callers: an omitted one silently inherits the caller's own input of the same name.
function "review/clear_marks" {
  input {
    int account_id
    int user_id
    text how filters=trim
    int planner_task_id?
    int timeline_id?
  }

  stack {
    var $slot_ids {
      value = [-1]
    }

    conditional {
      if ($input.planner_task_id != 0) {
        array.push $slot_ids {
          value = $input.planner_task_id
        }
      }
    }

    conditional {
      if ($input.timeline_id != 0) {
        db.query planner_task {
          where = $db.planner_task.timeline_id == $input.timeline_id
          return = {type: "list"}
          output = ["id"]
        } as $day_slots

        foreach ($day_slots) {
          each as $ds {
            array.push $slot_ids {
              value = $ds.id
            }
          }
        }
      }
    }

    db.query planner_task_review {
      where = $db.planner_task_review.planner_task_id in $slot_ids && $db.planner_task_review.account_id == $input.account_id
      return = {type: "list"}
      output = ["id", "planner_task_id", "cleared_at"]
    } as $marks

    var $now_ms {
      value = now|to_int
    }

    var $cleared_ids {
      value = []
    }

    foreach ($marks) {
      each as $m {
        conditional {
          if ($m.cleared_at == 0) {
            db.patch planner_task_review {
              field_name = "id"
              field_value = $m.id
              data = {cleared_at: $now_ms, cleared_by: $input.user_id, cleared_how: $input.how, updated_at: "now"}
            } as $_patched

            array.push $cleared_ids {
              value = $m.planner_task_id
            }
          }
        }
      }
    }
  }

  response = {cleared: ($cleared_ids|count), slot_ids: $cleared_ids}
}
