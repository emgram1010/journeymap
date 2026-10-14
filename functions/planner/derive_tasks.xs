// PLN-7 (US-PLN-7-06) — The ONE implementation of a task's derived
// fields. Used by the task list, the single read, and PLN-8's hydrate.
//
// START TIMES ARE NEVER STORED. `planned_start` is the timeline's
// start plus the durations of every task before it. That is why there
// is no `planned_start` column and why changing one task's duration
// shifts everything after it with no other row written.
//
// The wrap matches `formatMinutesToTime` in the planner frontend
// exactly — `((m % 1440) + 1440) % 1440` — so a day running past
// midnight shows the same time on both sides. Verified live: a 23:00
// day with 45/60/90-minute tasks derives 23:00, 23:45, 00:45, 02:15.
//
// Backlog tasks have no timeline and therefore no start at all:
// `planned_start` is null, not "00:00", because "unscheduled" and
// "midnight" are different facts.
//
// EFFECTIVE ASSIGNEE is the task's own `assignee_agent_id` when set,
// otherwise the timeline's agent, otherwise nobody. `0` means "not
// set" (no real nullable FKs here), so an override of 0 correctly
// falls through to the timeline's agent.
//
// Agent names are resolved with one query for the whole container,
// never one per task.
function "planner/derive_tasks" {
  input {
    int workspace_id filters=min:1
    int timeline_id
  }

  stack {
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id && $db.planner_task.timeline_id == $input.timeline_id
      sort = {planner_task.seq: "asc", planner_task.id: "asc"}
      return = {type: "list"}
    } as $tasks

    var $is_backlog {
      value = ($input.timeline_id == 0)
    }

    var $cursor {
      value = 0
    }

    var $timeline_agent_id {
      value = 0
    }

    conditional {
      if ($is_backlog == false) {
        db.get planner_timeline {
          field_name = "id"
          field_value = $input.timeline_id
        } as $timeline

        var.update $timeline_agent_id {
          value = $timeline.agent_id
        }

        var $hh {
          value = ($timeline.start_time|substr:0:2)|to_int
        }

        var $mm {
          value = ($timeline.start_time|substr:3:2)|to_int
        }

        var.update $cursor {
          value = ($hh * 60) + $mm
        }
      }
    }

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

    var $result {
      value = []
    }

    var $norm {
      value = 0
    }

    var $h {
      value = 0
    }

    var $m {
      value = 0
    }

    var $hs {
      value = ""
    }

    var $ms {
      value = ""
    }

    var $planned_start {
      value = null
    }

    var $eff_id {
      value = 0
    }

    var $eff_name {
      value = null
    }

    foreach ($tasks) {
      each as $t {
        // --- derived start -------------------------------------------
        var.update $planned_start {
          value = null
        }

        var.update $norm {
          value = (($cursor % 1440) + 1440) % 1440
        }

        var.update $h {
          value = ($norm - ($norm % 60)) / 60
        }

        var.update $m {
          value = $norm % 60
        }

        var.update $hs {
          value = ("0" ~ ($h|to_text))|substr:-2:2
        }

        var.update $ms {
          value = ("0" ~ ($m|to_text))|substr:-2:2
        }

        conditional {
          if ($is_backlog == false) {
            var.update $planned_start {
              value = $hs ~ ":" ~ $ms
            }
          }
        }

        var.update $cursor {
          value = $cursor + $t.duration_minutes
        }

        // --- effective assignee --------------------------------------
        var.update $eff_id {
          value = $timeline_agent_id
        }

        conditional {
          if ($t.assignee_agent_id != 0) {
            var.update $eff_id {
              value = $t.assignee_agent_id
            }
          }
        }

        var.update $eff_name {
          value = null
        }

        var.update $key {
          value = $eff_id|to_text
        }

        conditional {
          if ($eff_id != 0) {
            var.update $eff_name {
              value = $agent_names|get:$key:null
            }
          }
        }

        array.push $result {
          value = {
            id                : $t.id
            workspace_id      : $t.workspace_id
            timeline_id       : $t.timeline_id
            seq               : $t.seq
            title             : $t.title
            duration_minutes  : $t.duration_minutes
            notes             : $t.notes
            status            : $t.status
            needs_info_reason : $t.needs_info_reason
            tweak_reason      : $t.tweak_reason
            assignee_agent_id : $t.assignee_agent_id
            planned_start     : $planned_start
            effective_assignee: {agent_id: $eff_id, name: $eff_name}
          }
        }
      }
    }
  }

  response = {tasks: $result}
}
