// COP-5 story 03 — the copilot's own work for a day, in THIS business: the published items whose
// effective assignee is a plan person linked to the caller, read from the frozen publication (the
// same shared functions the performer app uses: perform/today_for, perform/resolve_agents,
// perform/collect_published_items). Nobody else's tasks, no draft days, no other business.
// The business filter is done by constraining the queries (maps of the pinned business -> their
// versions -> their jobs -> the tasks), never by an `if` inside a loop (CLAUDE.md).
tool list_my_tasks {
  instructions = "List the tasks assigned to you on published days, for one date (default: today), in this business: work_task_id, the job, the stage, and the status (not_started, in_progress, blocked, done, skipped). Use record_my_task_event to start, finish, block or skip one. You never see or touch another person's tasks."

  input {
    text date? filters=trim {
      description = "YYYY-MM-DD. Leave empty for today."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "list_my_tasks", kind: "read"}
    } as $cop1_gate

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin != 0 && $cop1_gate.user_id != 0 && $cop1_gate.account_id != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    var $date_ok {
      value = ($input.date == "") || ("/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$input.date)
    }

    precondition ($date_ok) {
      error_type = "inputerror"
      error = "Give the date as YYYY-MM-DD, or leave it empty for today."
    }

    function.run "perform/today_for" {
      input = {user_id: $cop1_gate.user_id, tz: ""}
    } as $today

    var $date {
      value = $today.date
    }

    conditional {
      if ($input.date != "") {
        var.update $date {
          value = $input.date
        }
      }
    }

    function.run "perform/resolve_agents" {
      input = {account_id: $cop1_gate.account_id, user_id: $cop1_gate.user_id}
    } as $resolved

    function.run "perform/collect_published_items" {
      input = {account_id: $cop1_gate.account_id, date: $date, agent_ids: $resolved.agent_ids}
    } as $collected

    var $wt_ids {
      value = [-1]
    }

    foreach ($collected.items) {
      each as $i {
        foreach ($i.work_task_ids) {
          each as $wid {
            array.push $wt_ids {
              value = $wid
            }
          }
        }
      }
    }

    // This business only: its maps -> their versions -> their jobs.
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $pin && $db.journey_map.account_id == $cop1_gate.account_id
      return = {type: "list"}
      output = ["id"]
    } as $maps

    var $map_ids {
      value = [-1]
    }

    foreach ($maps) {
      each as $m {
        array.push $map_ids {
          value = $m.id
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $map_ids
      return = {type: "list"}
      output = ["id"]
    } as $versions

    var $version_ids {
      value = [-1]
    }

    foreach ($versions) {
      each as $v {
        array.push $version_ids {
          value = $v.id
        }
      }
    }

    db.query work_item {
      where = $db.work_item.journey_map_version_id in $version_ids && $db.work_item.account_id == $cop1_gate.account_id
      return = {type: "list"}
      output = ["id", "title"]
    } as $jobs

    var $job_ids {
      value = [-1]
    }

    var $job_titles {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }

        var $jkey {
          value = "j" ~ ($j.id|to_text)
        }

        var.update $job_titles {
          value = $job_titles|set:$jkey:$j.title
        }
      }
    }

    db.query work_task {
      where = $db.work_task.id in $wt_ids && $db.work_task.work_item_id in $job_ids
      sort = {work_task.id: "asc"}
      return = {type: "list"}
      output = ["id", "work_item_id", "stage_key", "lens_key", "status"]
    } as $mine

    var $rows {
      value = []
    }

    foreach ($mine) {
      each as $t {
        var $tk {
          value = "j" ~ ($t.work_item_id|to_text)
        }

        array.push $rows {
          value = {
            work_task_id: $t.id
            job_id      : $t.work_item_id
            job_title   : (($job_titles|get:$tk:null) ?? "")
            stage_key   : $t.stage_key
            lens_key    : $t.lens_key
            status      : $t.status
          }
        }
      }
    }
  }

  response = {date: $date, journey_architecture_id: $pin, count: ($rows|count), tasks: $rows}
}
