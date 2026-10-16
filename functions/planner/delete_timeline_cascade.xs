// PLN-6 (US-PLN-6-05) — Delete a timeline, keeping its tasks.
//
// PUSHED 2026-10-16, on the founder's explicit approval, together with
// functions/planner/delete_agent_cascade.xs and the two DELETE
// endpoints that call them. Approved specifically because neither of
// these two loses work: both only move tasks back to the backlog.
// STILL HELD, and deliberately not pushed with them:
//   functions/planner/delete_task.xs            (destroys work)
//   functions/planner/delete_workspace_cascade.xs (destroys a whole plan)
//   functions/planner/delete_model_guard.xs     (part of model delete)
//
// The whole job is two steps, and the first one is already proven:
// `planner/return_tasks_to_backlog` is pushed and tested (it contains
// no delete), and it is what guarantees no task is lost and the
// backlog keeps a sensible order. All that is unverified here is the
// single `db.del` that follows.
//
// P3A-1 (US-P3A-1-04): a PUBLISHED timeline cannot be deleted at all.
// That check belongs to the endpoint, before this runs. It was written
// when publishing was still on hold in PLN-6 and every timeline was
// `draft`, which made it a guard against a future state — LIVE-1 has
// shipped since, real published timelines exist, and it is now a live
// rule protecting a frozen publication from losing the row it points
// at.
function "planner/delete_timeline_cascade" {
  input {
    int workspace_id filters=min:1
    int timeline_id filters=min:1
  }

  stack {
    function.run "planner/return_tasks_to_backlog" {
      input = {workspace_id: $input.workspace_id, timeline_id: $input.timeline_id}
    } as $moved

    db.del planner_timeline {
      field_name = "id"
      field_value = $input.timeline_id
    }

    // The backlog just grew, so it gets normalised to exactly 1..n —
    // planner/resequence's own rule is that EVERY mutation ends by
    // resequencing each container it touched. Skipping it is what left
    // the backlog on seq 0,1 and tripped PLN-8's SEQ_GAP_OR_DUP on the
    // first real run of this cascade (2026-10-16). The deleted
    // timeline needs none: it no longer exists.
    function.run "planner/resequence" {
      input = {workspace_id: $input.workspace_id, timeline_id: 0}
    } as $backlog_reseq
  }

  response = {
    tasks_returned: $moved.tasks_returned
    moved_ids     : $moved.moved_ids
  }
}
