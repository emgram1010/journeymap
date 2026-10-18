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
// (`perform/today_for`). The device's own CLOCK is still never
// trusted; GAP-FIX W8 adds `tz`, an IANA zone name the client knows
// about itself, which that function reads the server's clock in. A
// junk or missing zone falls back to UTC.
//
// NOTHING IS SCHEDULED is not an error: an empty `items` array with a
// 200 is the correct, ordinary answer for a quiet day.
//
// GAP-FIX W4/W5 — `my_dates` lists every date this performer has
// published work on. One sentence ("Nothing is scheduled for you
// today.") used to cover four unrelated causes, and the screen had no
// data to tell them apart; `agent_ids` already distinguished "no
// login linked", and this distinguishes "nothing published at all"
// from "work exists, on another day". The same list is what day
// navigation steps through, so "next day with work" is a real jump
// and not a guess.
query "perform/today" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    text date? filters=trim
    text tz? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "perform/today_for" {
      input = {user_id: $actor.user_id, tz: $input.tz}
    } as $today

    var $date {
      value = $input.date
    }

    conditional {
      if ($date == "") {
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

    function.run "perform/published_dates_for" {
      input = {account_id: $actor.account_id, agent_ids: $resolved.agent_ids}
    } as $calendar

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
    today     : $today.date
    zone      : $today.zone
    agent_ids : $resolved.agent_ids
    my_dates  : $calendar.dates
    snapshot  : {date: $date, items: $collected.items}
    statuses  : $hydrated.statuses
  }
}
