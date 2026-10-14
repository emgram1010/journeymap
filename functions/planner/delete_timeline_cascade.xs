// PLN-6 (US-PLN-6-05) — Delete a timeline, keeping its tasks.
//
// ⚠️ NOT PUSHED TO XANO, and neither is the DELETE endpoint that calls
// it. CLAUDE.md requires the founder to approve any delete. Fourth and
// last of the held delete paths, with:
//   functions/planner/delete_workspace_cascade.xs
//   functions/planner/delete_agent_cascade.xs
//   functions/planner/delete_model_guard.xs
//
// The whole job is two steps, and the first one is already proven:
// `planner/return_tasks_to_backlog` is pushed and tested (it contains
// no delete), and it is what guarantees no task is lost and the
// backlog keeps a sensible order. All that is unverified here is the
// single `db.del` that follows.
//
// P3A-1 (US-P3A-1-04): a PUBLISHED timeline cannot be deleted at all.
// That check belongs to the endpoint, before this runs — publishing is
// on hold in PLN-6, so every timeline is currently `draft` and the
// check is a guard against a future state, not a live one.
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
  }

  response = {
    tasks_returned: $moved.tasks_returned
    moved_ids     : $moved.moved_ids
  }
}
