// PLN-3 (US-PLN-3-02) — The four counts shown against every plan.
//
// Four `return = {type: "count"}` queries, which Xano answers in SQL.
// US-PLN-3-02 explicitly forbids per-row loops here: a plan with 400
// tasks must cost the same as one with 4.
//
// This is the SINGLE-plan version, used by the read and update
// endpoints. The list endpoint does NOT call it per row — see
// apis/planner/524_workspace_GET.xs, which tallies all plans from four
// queries total.
//
// `backlog_count` is the subset of tasks with no timeline. There are no
// real nullable foreign keys in this workspace, so "no timeline" is
// `timeline_id == 0` — see docs/planner-data-model.md.
function "planner/workspace_counts" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $agent_count

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $timeline_count

    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $task_count

    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id && $db.planner_task.timeline_id == 0
      return = {type: "count"}
    } as $backlog_count
  }

  response = {
    agent_count   : $agent_count
    timeline_count: $timeline_count
    task_count    : $task_count
    backlog_count : $backlog_count
  }
}
