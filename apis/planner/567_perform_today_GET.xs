// APP-1 (US-APP-1-02) — "My work today."
//
// Returns the caller's items from the FROZEN publication snapshot for
// their agent(s), for one date, plus the live status (and hydrated
// task text) for every work_task those items reference. NEVER reads
// the live plan (D-23) — a planner rearranging a published day after
// the fact changes nothing this returns; LIVE-1's own change log is
// where that history lives, not here.
//
// TWO SEPARATE THINGS COME BACK ON PURPOSE: `snapshot` is what was
// PLANNED (frozen, never touched after publish) and `statuses` is
// what's HAPPENING NOW (live work_task rows). The frontend's
// `toPerformerItems(snapshot, statuses)` merges them; this endpoint
// does not pre-merge them itself, so that merge stays one pure,
// independently tested function instead of logic repeated on both
// sides.
//
// `date` is optional and defaults to today AS THE SERVER SEES IT
// (`perform/today_for` — the timezone seam, learning-fixes.md flag
// #4). The device's own clock is never trusted for "what day is it".
//
// NOTHING IS SCHEDULED is not an error: an empty `items` array with a
// 200 is the correct, ordinary answer for a quiet day.
query "perform/today" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    text date? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    var $date {
      value = $input.date
    }

    conditional {
      if ($date == "") {
        function.run "perform/today_for" {
          input = {user_id: $actor.user_id}
        } as $today

        var.update $date {
          value = $today.date
        }
      }
    }

    function.run "perform/resolve_agents" {
      input = {account_id: $actor.account_id, user_id: $actor.user_id}
    } as $resolved

    function.run "perform/collect_published_items" {
      input = {account_id: $actor.account_id, date: $date, agent_ids: $resolved.agent_ids}
    } as $collected

    var $wt_ids {
      value = []
    }

    foreach ($collected.items) {
      each as $i {
        foreach ($i.work_task_ids) {
          each as $id {
            array.push $wt_ids {
              value = $id
            }
          }
        }
      }
    }

    function.run "perform/hydrate_statuses" {
      input = {work_task_ids: $wt_ids}
    } as $hydrated
  }

  response = {
    date      : $date
    agent_ids : $resolved.agent_ids
    snapshot  : {date: $date, items: $collected.items}
    statuses  : $hydrated.statuses
  }
}
