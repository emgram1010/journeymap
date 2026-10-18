// O4 (2026-10-17) — Take a job step back off the schedule.
//
// THE OTHER HALF OF SCHED-1's `work_task/{id}/schedule`. That endpoint
// creates a `planner_task` slot and links it to the step; nothing had
// ever removed one. W1 then put a Schedule button in front of a
// planner, which turned a missing endpoint into a one-way door: a step
// placed on the wrong day could be MOVED to another day (planner_task
// place, which does not touch the link) but could never return to
// "waiting for a day", because `backlog_work` decides "unscheduled" by
// absence from this very link table. Found while writing up the gap
// list, not during the build.
//
// BOTH ROWS GO, AND ONLY THESE TWO. The link and the empty slot it
// created. The `work_task` itself is untouched — the step still exists,
// still belongs to its job, still reads its text from the job's pinned
// version. Nothing about the agreed work changes; only the claim on
// somebody's day is released.
//
// NO GUARDS HERE ON PURPOSE. Whether this is allowed (published day,
// work already started) is decided by the endpoint before it calls
// this, exactly as `delete_timeline_cascade` leaves the published check
// to endpoint 572. A cascade that second-guesses its caller ends up
// with two different ideas of the rule.
//
// The container is resequenced afterwards so `seq` stays 1..n and every
// later slot's derived start time closes up — the same ending every
// other mutation in PLN-7 has.
function "planner/unschedule_work_task" {
  input {
    int workspace_id filters=min:1
    int work_task_id filters=min:1
  }

  stack {
    // `work_task_id` is unique on this table, so "the first match" IS
    // the only match — the usual db.del caveat (CLAUDE.md) does not
    // bite here, and the index is what makes that true.
    db.get planner_task_work_task {
      field_name = "work_task_id"
      field_value = $input.work_task_id
    } as $link

    var $found {
      value = ($link != null)
    }

    var $planner_task_id {
      value = 0
    }

    var $container {
      value = 0
    }

    conditional {
      if ($found == true) {
        var.update $planner_task_id {
          value = $link.planner_task_id
        }

        db.get planner_task {
          field_name = "id"
          field_value = $link.planner_task_id
        } as $slot

        var.update $container {
          value = ($slot.timeline_id ?? 0)
        }

        db.del planner_task_work_task {
          field_name = "id"
          field_value = $link.id
        }

        db.del planner_task {
          field_name = "id"
          field_value = $link.planner_task_id
        }

        function.run "planner/resequence" {
          input = {workspace_id: $input.workspace_id, timeline_id: $container}
        } as $reseq
      }
    }
  }

  response = {
    found             : $found
    work_task_id      : $input.work_task_id
    removed_slot_id   : $planner_task_id
    container         : $container
  }
}
