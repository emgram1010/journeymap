// PLN-5 (US-PLN-5-04) — Remove an agent from a plan, keeping the work.
//
// ⚠️ NOT PUSHED TO XANO, and neither is the DELETE endpoint that calls
// it. CLAUDE.md requires the founder to approve any delete. Held for
// review with the other two: functions/planner/delete_workspace_cascade.xs
// and functions/planner/delete_model_guard.xs.
//
// NO TASK IS EVER DELETED HERE. That is the shipped behaviour of the
// localStorage planner's `handleDeleteAgent` and the acceptance
// criterion of US-PLN-5-04: losing someone from a plan must not lose
// the work that was assigned to them. Only the agent and their now-empty
// timelines go.
//
// Order matters, and it is the reverse of intuition — the tasks are
// moved out FIRST, so that by the time a timeline is deleted it is
// already empty and no task is ever briefly pointing at a timeline
// that no longer exists:
//   1. every task on each of the agent's timelines → backlog
//      (planner/return_tasks_to_backlog, which preserves order)
//   2. every task elsewhere whose assignee_agent_id is this agent →
//      cleared to 0, so it falls back to its timeline's own agent
//   3. the agent's timelines
//   4. the agent
//
// Steps 2–4 loop and patch/delete by id: `db.patch` and `db.del` with a
// non-unique field_name only ever touch the FIRST match (CLAUDE.md,
// confirmed live via PLN-5's bulk-visibility endpoint). A single
// `db.del planner_timeline { field_name = "agent_id" ... }` would
// delete ONE timeline and silently leave the rest orphaned.
//
// Tenancy (planner/assert_agent) and P3A-1's history check are the
// caller's job, not this function's.
//
// P3A-1 (US-P3A-1-03): this cascade only runs for an agent with NO
// history. An agent with a published timeline or log events is
// deactivated (`is_active = false`) instead, and never reaches here.
function "planner/delete_agent_cascade" {
  input {
    int workspace_id filters=min:1
    int agent_id filters=min:1
  }

  stack {
    db.query planner_timeline {
      where = $db.planner_timeline.agent_id == $input.agent_id
      return = {type: "list"}
    } as $timelines

    // 1) Empty each timeline into the backlog, in order.
    var $tasks_returned {
      value = 0
    }

    foreach ($timelines) {
      each as $tl {
        function.run "planner/return_tasks_to_backlog" {
          input = {workspace_id: $input.workspace_id, timeline_id: $tl.id}
        } as $moved

        var.update $tasks_returned {
          value = $tasks_returned + $moved.tasks_returned
        }
      }
    }

    // 2) Clear per-task assignment overrides pointing at this agent.
    db.query planner_task {
      where = $db.planner_task.assignee_agent_id == $input.agent_id
      return = {type: "list"}
    } as $assigned

    db.transaction {
      stack {
        foreach ($assigned) {
          each as $t {
            db.patch planner_task {
              field_name = "id"
              field_value = $t.id
              data = {assignee_agent_id: 0, updated_at: "now"}
            } as $cleared
          }
        }

        // 3) The timelines, now empty.
        foreach ($timelines) {
          each as $tl {
            db.del planner_timeline {
              field_name = "id"
              field_value = $tl.id
            }
          }
        }

        // 4) The agent.
        db.del planner_agent {
          field_name = "id"
          field_value = $input.agent_id
        }
      }
    }
  }

  response = {
    timelines_removed  : ($timelines|count)
    tasks_returned     : $tasks_returned
    assignments_cleared: ($assigned|count)
  }
}
