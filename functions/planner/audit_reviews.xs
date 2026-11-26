// REPEAT-1 (US-REPEAT-1-05) — The "needs review" marks must never outlive their slot. Read-only. Code: ORPHAN_REVIEW — a mark whose planner_task no longer exists (a slot deleted without its mark), or whose plan belongs to a different account than the mark says. Every delete path that removes a slot removes its mark in the same transaction (planner/unschedule_work_task live; planner/delete_task held with the other delete paths); this is what proves it. Reports ids, never repairs. Every branch is on a loop item's own field, with the lookups recorded as fields in a first pass.
function "planner/audit_reviews" {
  input {
    int account_id filters=min:1
  }

  stack {
    db.query planner_task_review {
      where = $db.planner_task_review.account_id == $input.account_id
      return = {type: "list"}
      output = ["id", "planner_task_id", "workspace_id"]
    } as $marks

    var $slot_ids {
      value = [-1]
    }

    foreach ($marks) {
      each as $m {
        array.push $slot_ids {
          value = $m.planner_task_id
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.id in $slot_ids
      return = {type: "list"}
      output = ["id", "workspace_id"]
    } as $slots

    var $slot_ws {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($slots) {
      each as $s {
        var.update $key {
          value = "k:" ~ ($s.id|to_text)
        }

        var.update $slot_ws {
          value = $slot_ws|set:$key:$s.workspace_id
        }
      }
    }

    var $checks {
      value = []
    }

    var $found_ws {
      value = null
    }

    foreach ($marks) {
      each as $m {
        var.update $key {
          value = "k:" ~ ($m.planner_task_id|to_text)
        }

        var.update $found_ws {
          value = $slot_ws|get:$key:null
        }

        array.push $checks {
          value = {id: $m.id, planner_task_id: $m.planner_task_id, slot_ws: $found_ws, mark_ws: $m.workspace_id}
        }
      }
    }

    var $violations {
      value = []
    }

    foreach ($checks) {
      each as $c {
        conditional {
          if ($c.slot_ws == null) {
            array.push $violations {
              value = {code: "ORPHAN_REVIEW", entity: "planner_task_review", id: $c.id, detail: $c.planner_task_id}
            }
          }
        }

        conditional {
          if ($c.slot_ws != null && $c.slot_ws != $c.mark_ws) {
            array.push $violations {
              value = {code: "ORPHAN_REVIEW", entity: "planner_task_review", id: $c.id, detail: $c.planner_task_id}
            }
          }
        }
      }
    }
  }

  response = {violations: $violations}
}
