// SCHED-1 (US-SCHED-1-03) — Put a job step onto a day.
//
// THE RULE LIVES IN ONE PLACE: `planner_ops/schedule_work_task` (4-C,
// 2026-11-17). This endpoint signs the caller in, resolves who they are,
// works out whether a duration was SENT (only the endpoint can see the
// raw body) and hands every input over explicitly (an input left out of
// function.run silently takes this endpoint's value of the same name).
// The copilot tool `plan_schedule_step` calls the same function, so a
// step scheduled by a person and one scheduled by the copilot go through
// the same checks, writes and events. Replay before vs after:
// c4_560_replay.py.
//
// What the function does, unchanged from this endpoint's old inline copy:
//   - creates a `planner_task` slot on the day and links it to the step,
//     in one db.transaction; the slot carries NO title (reference, do not
//     copy — the board reads it through the link, GAP-FIX W1);
//   - the default duration is the step's EXPECTED minutes from the pinned
//     version (EST-1's stage estimate on a map with an Items row, for the
//     stage's owner only); a SUPPLIED duration is held to 1..1440
//     (E-SCHED-002) and only an ABSENT one falls back (to expected, and to
//     30 only when there is no estimate at all);
//   - the day must be in the job's plan, an assignee override must be in
//     it too, and a switched-off copilot's column is refused (E-COP-059);
//   - a step already on the schedule is refused (E-SCHED-001), a
//     cancelled job's steps are refused (E-SCHED-008).
// UNDOING THIS is `DELETE work_task/{id}/schedule` (api 576, O4).
query "work_task/{work_task_id}/schedule" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_task_id filters=min:1
    int timeline_id filters=min:1
    int duration_minutes?
    int assignee_agent_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    // "Was a duration sent?" — an omitted optional int arrives as 0, so
    // only the raw body can tell an explicit 0 (refused) from nothing.
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = true
    } as $raw_input

    var $caller_set_duration {
      value = $raw_input|has:"duration_minutes"
    }

    function.run "planner_ops/schedule_work_task" {
      input = {
        actor               : $actor
        work_task_id        : $input.work_task_id
        timeline_id         : $input.timeline_id
        duration_minutes    : $input.duration_minutes
        has_duration_minutes: $caller_set_duration
        assignee_agent_id   : $input.assignee_agent_id
        correlation_id      : $input.correlation_id
      }
    } as $scheduled
  }

  response = {
    planner_task     : $scheduled.planner_task
    work_task_id     : $scheduled.work_task_id
    expected_minutes : $scheduled.expected_minutes
    scheduled_minutes: $scheduled.scheduled_minutes
    is_tweaked       : $scheduled.is_tweaked
  }
}
