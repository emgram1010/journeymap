// P3A-1 (US-P3A-1-03) — Has this agent actually done anything yet?
//
// The single gate deciding whether an agent may be REMOVED from a plan
// or must be kept. Two things count as history, exactly as the story
// defines them:
//   1. a PUBLISHED timeline of theirs — someone was told to do that
//      day's work, and LIVE-1's frozen publication still points at it;
//   2. an `activity_log` event performed as this agent — they really
//      did the work, and LOG-1's history must keep referring to a row
//      that exists.
//
// ⚠️ UNLIKE `planner/workspace_has_history`, THIS ONE ACTUALLY ANSWERS.
// That function still returns "no history" for everything, because it
// was written before `work_item`, `plan_publication` and `activity_log`
// existed and its TODOs were never filled in once they did. All three
// tables are live now, so a plan with real recorded work would today
// pass its check — which is exactly why plan delete stays held. Both
// tables this function reads exist, so this answer is true today.
//
// Counts only, never loads rows: `planner_timeline(agent_id)` and
// `activity_log(performer_agent_id)` are both indexed.
function "planner/agent_has_history" {
  input {
    int agent_id filters=min:1
  }

  stack {
    db.query planner_timeline {
      where = $db.planner_timeline.agent_id == $input.agent_id && $db.planner_timeline.status == "published"
      return = {type: "count"}
    } as $published_days

    db.query activity_log {
      where = $db.activity_log.performer_agent_id == $input.agent_id
      return = {type: "count"}
    } as $logged_events

    // Hoisted rather than written inline in the response: a compound
    // boolean inside an object literal is the shape that has bitten
    // this codebase before (CLAUDE.md).
    var $has_history {
      value = ($published_days > 0 || $logged_events > 0)
    }
  }

  response = {
    has_history   : $has_history
    published_days: $published_days
    logged_events : $logged_events
  }
}
