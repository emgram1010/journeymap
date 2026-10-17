// PLN-7 (US-PLN-7-03) — Move a task to a position in any container of
// the same plan: another agent's day, another date, or the backlog.
//
// HOW THE INSERT WORKS, AND WHY IT LOOKS INDIRECT. Inserting "at index
// 2" normally means a loop that counts positions and branches when it
// reaches the target — but a `conditional` inside a `foreach` whose
// condition reads a counter updated in that same iteration silently
// discards its writes (CLAUDE.md, found in PLN-6). So instead:
//
//   1. every other task in the destination is spaced out: 10, 20, 30…
//   2. the moved task is given `index * 10 + 5`, which lands it in
//      exactly one gap — 5 before the first, 15 between 10 and 20, and
//      so on past the end
//   3. planner/resequence then flattens the container to 1..n
//
// No branching inside any loop, and the ordering is decided by
// arithmetic rather than by control flow.
//
// LANDING IN A TIMELINE CLEARS `needs_info`. That mirrors the shipped
// `recomputeTimelineTaskTimes`: scheduling a task is the act of saying
// it is ready to do. Moving to the BACKLOG changes nothing else —
// un-scheduling is not a judgement about the task.
//
// THE ASSIGNEE OVERRIDE IS NEVER TOUCHED. Dragging a task onto someone
// else's day does not silently reassign a task that was explicitly
// given to a named person; the override outranks the timeline.
function "planner/place_task" {
  input {
    int workspace_id filters=min:1
    int task_id filters=min:1
    int dest_timeline_id
    int index
  }

  stack {
    db.get planner_task {
      field_name = "id"
      field_value = $input.task_id
    } as $task

    var $source_timeline_id {
      value = $task.timeline_id
    }

    // Space the destination's other tasks 10 apart.
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id && $db.planner_task.timeline_id == $input.dest_timeline_id && $db.planner_task.id != $input.task_id
      sort = {planner_task.seq: "asc", planner_task.id: "asc"}
      return = {type: "list"}
    } as $dest_others

    var $n {
      value = $dest_others|count
    }

    // Clamp past-the-end to the end. A negative index is rejected by
    // the endpoint before this runs.
    var $idx {
      value = $input.index
    }

    conditional {
      if ($input.index > $n) {
        var.update $idx {
          value = $n
        }
      }
    }

    var $pos {
      value = 0
    }

    var $landing_seq {
      value = ($idx * 10) + 5
    }

    var $to_timeline {
      value = ($input.dest_timeline_id != 0)
    }

    var $next_status {
      value = $task.status
    }

    var $next_reason {
      value = $task.needs_info_reason
    }

    conditional {
      if ($to_timeline == true) {
        var.update $next_status {
          value = "planned"
        }

        var.update $next_reason {
          value = ""
        }
      }
    }

    db.transaction {
      stack {
        foreach ($dest_others) {
          each as $d {
            var.update $pos {
              value = $pos + 10
            }

            db.patch planner_task {
              field_name = "id"
              field_value = $d.id
              data = {seq: $pos, updated_at: "now"}
            } as $spaced
          }
        }

        db.patch planner_task {
          field_name = "id"
          field_value = $input.task_id
          data = {
            timeline_id      : $input.dest_timeline_id
            seq              : $landing_seq
            status           : $next_status
            needs_info_reason: $next_reason
            updated_at       : "now"
          }
        } as $moved
      }
    }

    function.run "planner/resequence" {
      input = {workspace_id: $input.workspace_id, timeline_id: $input.dest_timeline_id}
    } as $dest_reseq

    // Only when the task actually left a different container.
    var $source_reseq {
      value = null
    }

    conditional {
      if ($source_timeline_id != $input.dest_timeline_id) {
        function.run "planner/resequence" {
          input = {workspace_id: $input.workspace_id, timeline_id: $source_timeline_id}
        } as $src

        var.update $source_reseq {
          value = $src
        }
      }
    }
  }

  response = {
    task_id           : $input.task_id
    source_timeline_id: $source_timeline_id
    dest_timeline_id  : $input.dest_timeline_id
    clamped_index     : $idx
    destination       : $dest_reseq
    source            : $source_reseq
  }
}
