// PLN-6 (US-PLN-6-02) — The plan's timelines, with everything derived.
//
// NOTHING HERE IS STORED. `agent_name`, `label`, `task_count`,
// `total_minutes` and `out_of_window` are all computed on read. That is
// the point of PLN-1's normalization: rename an agent and every label
// changes on the next read, with no timeline row written. The old
// localStorage planner stored the assignee's name on the timeline and
// had to rewrite them all.
//
// `out_of_window` is likewise computed against the plan's CURRENT
// window, so moving the window re-flags existing timelines without
// touching them (US-PLN-3-03 requires a window change to destroy
// nothing).
//
// Counts come from ONE task query for the whole list, tallied in
// memory — never one query per timeline. The tallies are pre-seeded
// with zeros because `|get` with a variable key ignores its default on
// a miss (CLAUDE.md).
//
// ⚠️ THE TASK QUERY IS SCOPED TO THE LISTED TIMELINE IDS, and that is
// load-bearing, not an optimisation. It guarantees every task's key is
// one of the seeded ones, so the tally loop needs NO `if` to skip
// unknown keys. A conditional would break it: a `conditional` whose
// condition reads a variable updated earlier in the SAME foreach
// iteration silently discards everything the branch writes (confirmed
// live — the first version of this endpoint reported task_count 0 for
// every timeline). See CLAUDE.md.
//
// ⚠️ THE DATE FILTERS ARE `text`, NOT `date`, ON PURPOSE. An omitted
// optional `date` input does not default to "" the way text and int do
// — it does not exist at all, and referencing it in a where clause
// fails at runtime with "Unable to locate input: date_from". And on a
// GET there is no JSON body, so `util.get_raw_input|has:` cannot tell
// whether it was sent either. Text inputs default to "" and are
// testable, so the bounds widen to sentinels when absent.
query "workspace/{workspace_id}/timeline" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text date_from? filters=trim
    text date_to? filters=trim
    int agent_id?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    var $from {
      value = "0001-01-01"
    }

    conditional {
      if ($input.date_from != "") {
        var.update $from {
          value = $input.date_from
        }
      }
    }

    var $to {
      value = "9999-12-31"
    }

    conditional {
      if ($input.date_to != "") {
        var.update $to {
          value = $input.date_to
        }
      }
    }

    var $has_agent {
      value = ($input.agent_id != 0)
    }

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id && $db.planner_timeline.planned_date >= $from && $db.planner_timeline.planned_date <= $to && (($has_agent == false) || ($db.planner_timeline.agent_id == $input.agent_id))
      sort = {planner_timeline.planned_date: "asc", planner_timeline.id: "asc"}
      return = {type: "list"}
    } as $timelines

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $agents

    var $agent_names {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($agents) {
      each as $a {
        var.update $key {
          value = $a.id|to_text
        }

        var.update $agent_names {
          value = $agent_names|set:$key:$a.name
        }
      }
    }

    var $tl_ids {
      value = []
    }

    var $count_tally {
      value = {}
    }

    var $minutes_tally {
      value = {}
    }

    foreach ($timelines) {
      each as $t {
        array.push $tl_ids {
          value = $t.id
        }

        var.update $key {
          value = $t.id|to_text
        }

        var.update $count_tally {
          value = $count_tally|set:$key:0
        }

        var.update $minutes_tally {
          value = $minutes_tally|set:$key:0
        }
      }
    }

    var $cur {
      value = 0
    }

    var $next {
      value = 0
    }

    conditional {
      if (($tl_ids|count) > 0) {
        db.query planner_task {
          where = $db.planner_task.timeline_id in $tl_ids
          return = {type: "list"}
        } as $tasks

        foreach ($tasks) {
          each as $tk {
            var.update $key {
              value = $tk.timeline_id|to_text
            }

            var.update $cur {
              value = $count_tally|get:$key:0
            }

            var.update $next {
              value = $cur + 1
            }

            var.update $count_tally {
              value = $count_tally|set:$key:$next
            }

            var.update $cur {
              value = $minutes_tally|get:$key:0
            }

            var.update $next {
              value = $cur + $tk.duration_minutes
            }

            var.update $minutes_tally {
              value = $minutes_tally|set:$key:$next
            }
          }
        }
      }
    }

    var $result {
      value = []
    }

    var $agent_name {
      value = ""
    }

    var $label {
      value = ""
    }

    var $oow {
      value = false
    }

    foreach ($timelines) {
      each as $t {
        var.update $key {
          value = $t.agent_id|to_text
        }

        var.update $agent_name {
          value = $agent_names|get:$key:""
        }

        var.update $label {
          value = ($t.planned_date|format_timestamp:"M j":"UTC") ~ " — " ~ $agent_name
        }

        var.update $oow {
          value = ($t.planned_date < $guard.workspace.planning_window_start || $t.planned_date > $guard.workspace.planning_window_end)
        }

        var.update $key {
          value = $t.id|to_text
        }

        array.push $result {
          value = {
            id           : $t.id
            workspace_id : $t.workspace_id
            agent_id     : $t.agent_id
            agent_name   : $agent_name
            label        : $label
            planned_date : $t.planned_date
            start_time   : $t.start_time
            status       : $t.status
            task_count   : ($count_tally|get:$key:0)
            total_minutes: ($minutes_tally|get:$key:0)
            out_of_window: $oow
          }
        }
      }
    }
  }

  response = {timelines: $result}
}
