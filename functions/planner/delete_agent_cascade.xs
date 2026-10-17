// PLN-5 (US-PLN-5-04) — Remove an agent from a plan, keeping the work.
//
// PUSHED 2026-10-16, on the founder's explicit approval, together with
// functions/planner/delete_timeline_cascade.xs and the two DELETE
// endpoints that call them. Approved specifically because neither of
// these two loses work: both only move tasks back to the backlog.
// STILL HELD, and deliberately not pushed with them:
//   functions/planner/delete_task.xs            (destroys work)
//   functions/planner/delete_workspace_cascade.xs (destroys a whole plan)
//   functions/planner/delete_model_guard.xs     (part of model delete)
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
// history — `planner/agent_has_history` is the gate, and the endpoint
// refuses before ever reaching here if it answers yes.
//
// The story says such an agent should be "deactivated instead", via
// `is_active = false`. THAT FEATURE DOES NOT EXIST: `is_active` is
// written once as `true` at creation (endpoint 535) and is never read,
// filtered on, or settable anywhere. So the endpoint refuses and points
// at hiding the agent — which is real and works — rather than naming a
// deactivation a planner cannot actually perform. Building deactivate
// properly (settable, and honoured by the roster and board reads) is
// its own small story, flagged in PLN-9's Test Results.
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

    // 5) Normalise the backlog to exactly 1..n. planner/resequence's
    // own rule is that EVERY mutation ends by resequencing each
    // container it touched; omitting it here is what left the backlog
    // on seq 0,1 and tripped PLN-8's SEQ_GAP_OR_DUP on this cascade's
    // first real run (2026-10-16). The agent's own timelines need no
    // resequence — they have just been deleted.
    function.run "planner/resequence" {
      input = {workspace_id: $input.workspace_id, timeline_id: 0}
    } as $backlog_reseq
  }

  response = {
    timelines_removed  : ($timelines|count)
    tasks_returned     : $tasks_returned
    assignments_cleared: ($assigned|count)
  }
}
