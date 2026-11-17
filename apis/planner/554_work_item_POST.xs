// JOB-1 (US-JOB-1-02) — Add a job to a plan; its tasks appear
// automatically from the published map version.
//
// THE RULE LIVES IN ONE PLACE: `planner_ops/create_work_item` (4-C,
// 2026-11-17). This endpoint signs the caller in, resolves who they are
// and hands every input over explicitly (an input left out of
// function.run silently takes this endpoint's value of the same name).
// The copilot tool `plan_add_job` calls the same function, so a job made
// by a person and one made by the copilot go through the same checks,
// writes and events. Replay before vs after: c4_554_replay.py.
//
// What the function does, unchanged from this endpoint's old inline copy:
//   - THE JOB IS PINNED TO THE LATEST PUBLISHED VERSION AT THIS MOMENT,
//     and that pin never moves (later publishes or live edits cannot
//     change this job's content);
//   - the plan must accept the map (E-JOB-002) and the map must have a
//     published version (E-JOB-003); the messages name the map;
//   - the job row and all its tasks are one db.transaction;
//   - EXC-1 (US-EXC-1-04): an optional parent_work_item_id puts this job
//     UNDER another one; the parent must be in this account AND this plan
//     (E-EXC-009) and not cancelled (E-EXC-001). 0 / omitted = an
//     ordinary job.
query "work_item" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int journey_map_id filters=min:1
    text title filters=trim
    json attributes?
    // EXC-1 — 0 (omitted) = no parent. An optional int arrives as 0, never null.
    int parent_work_item_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner_ops/create_work_item" {
      input = {
        actor              : $actor
        workspace_id       : $input.workspace_id
        journey_map_id     : $input.journey_map_id
        title              : $input.title
        attributes         : $input.attributes
        parent_work_item_id: $input.parent_work_item_id
        correlation_id     : $input.correlation_id
      }
    } as $created
  }

  response = {
    work_item     : $created.work_item
    pinned_version: $created.pinned_version
    task_count    : $created.task_count
    tasks         : $created.tasks
    skipped_stages: $created.skipped_stages
  }
}
