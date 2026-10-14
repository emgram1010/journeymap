// PLN-7 (US-PLN-7-07) — Delete a task and close the gap it leaves.
//
// ⚠️ NOT PUSHED TO XANO, and neither is the DELETE endpoint that calls
// it. CLAUDE.md requires the founder to approve any delete. Fifth and
// last of the held delete paths:
//   functions/planner/delete_workspace_cascade.xs
//   functions/planner/delete_agent_cascade.xs
//   functions/planner/delete_timeline_cascade.xs
//   functions/planner/delete_model_guard.xs
//
// THIS IS THE ONLY PLANNER DELETE THAT REALLY DESTROYS SOMETHING.
// Deleting a plan, an agent or a timeline all keep the tasks — only
// this one removes work outright, which is exactly why it is the one
// a person is most likely to regret. Worth a confirmation in the UI.
//
// The container is resequenced afterwards so `seq` stays 1..n and the
// derived start times of everything below it close up. That half is
// already proven: planner/resequence is pushed, tested and idempotent.
//
// Captured before the delete, because afterwards there is no row to
// read the container from.
function "planner/delete_task" {
  input {
    int workspace_id filters=min:1
    int task_id filters=min:1
  }

  stack {
    db.get planner_task {
      field_name = "id"
      field_value = $input.task_id
    } as $task

    var $container {
      value = $task.timeline_id
    }

    db.del planner_task {
      field_name = "id"
      field_value = $input.task_id
    }

    function.run "planner/resequence" {
      input = {workspace_id: $input.workspace_id, timeline_id: $container}
    } as $reseq
  }

  response = {
    deleted_task_id: $input.task_id
    container      : $container
    remaining      : $reseq.count
    order          : $reseq.order
  }
}
