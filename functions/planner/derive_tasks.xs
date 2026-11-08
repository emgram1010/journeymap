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
//
// SCHED-2 (2026-11-05) — START TIMES NOW COME FROM `planner/start_minutes`,
// the one shared "pin + flow" rule: a task with a manual override
// (`planner_task_start_override`, one query for the whole container)
// starts at that time and everything after it flows on from there. With no
// overrides the output is byte-identical to before (verified on a 23:00
// day that wraps past midnight). `start_override` is returned per task
// ("" = none) so the planner UI can say "manually set".
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

    var $day_start {
      value = "00:00"
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

        var.update $day_start {
          value = $timeline.start_time
        }
      }
    }

    // --- SCHED-2: overrides, then the shared start rule ---------------
    // Every task key is pre-seeded with "" so a read never misses (`|get`
    // with a variable key drops its default on a miss — CLAUDE.md).
    var $task_ids {
      value = [-1]
    }

    var $ov_by_key {
      value = {}
    }

    var $k {
      value = ""
    }

    foreach ($tasks) {
      each as $t0 {
        array.push $task_ids {
          value = $t0.id
        }

        var.update $k {
          value = "k:" ~ ($t0.id|to_text)
        }

        var.update $ov_by_key {
          value = $ov_by_key|set:$k:""
        }
      }
    }

    db.query planner_task_start_override {
      where = $db.planner_task_start_override.planner_task_id in $task_ids
      return = {type: "list"}
    } as $overrides

    foreach ($overrides) {
      each as $o {
        var.update $k {
          value = "k:" ~ ($o.planner_task_id|to_text)
        }

        var.update $ov_by_key {
          value = $ov_by_key|set:$k:$o.start_time
        }
      }
    }

    var $start_items {
      value = []
    }

    foreach ($tasks) {
      each as $t1 {
        var.update $k {
          value = "k:" ~ ($t1.id|to_text)
        }

        var $ov1 {
          value = $ov_by_key|get:$k:""
        }

        array.push $start_items {
          value = {key: $k, minutes: $t1.duration_minutes, override: $ov1}
        }
      }
    }

    function.run "planner/start_minutes" {
      input = {day_start: $day_start, items: $start_items}
    } as $start_rule

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

    var $start_min {
      value = 0
    }

    var $start_override {
      value = ""
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

        var.update $k {
          value = "k:" ~ ($t.id|to_text)
        }

        var.update $start_min {
          value = $start_rule.starts|get:$k:0
        }

        var.update $start_override {
          value = $ov_by_key|get:$k:""
        }

        var.update $norm {
          value = (($start_min % 1440) + 1440) % 1440
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
            start_override    : $start_override
            effective_assignee: {agent_id: $eff_id, name: $eff_name}
          }
        }
      }
    }
  }

  response = {tasks: $result}
}
