// COP-5 story 04 (2026-11-15) — the copilot lists the jobs (work items) of THIS business: jobs whose
// pinned map version belongs to a map in the conversation's business, in the caller's account.
// Read-only. Newest first. Use with get_job_variance to answer "how did the plan go?".
tool list_business_jobs {
  instructions = "List the jobs (work items) of this business, newest first: id, title, status (open, in_progress, blocked, done...), started_at, finished_at and the map they came from. Optionally filter by status. Use get_job_variance on a job to see planned vs actual."

  input {
    text status? filters=trim

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "list_business_jobs", kind: "read"}
    } as $cop1_gate

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    db.query journey_map {
      where = $db.journey_map.journey_architecture == $pin && $db.journey_map.account_id == $cop1_gate.account_id
      return = {type: "list"}
      output = ["id", "title"]
    } as $maps

    var $map_ids {
      value = [-1]
    }

    var $titles {
      value = {}
    }

    foreach ($maps) {
      each as $m {
        array.push $map_ids {
          value = $m.id
        }

        var $tkey {
          value = "m" ~ ($m.id|to_text)
        }

        var.update $titles {
          value = $titles|set:$tkey:$m.title
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $map_ids
      return = {type: "list"}
      output = ["id", "journey_map_id"]
    } as $versions

    var $version_ids {
      value = [-1]
    }

    var $version_map {
      value = {}
    }

    foreach ($versions) {
      each as $v {
        array.push $version_ids {
          value = $v.id
        }

        var $vkey {
          value = "v" ~ ($v.id|to_text)
        }

        var.update $version_map {
          value = $version_map|set:$vkey:$v.journey_map_id
        }
      }
    }

    var $want_status {
      value = ($input.status != "")
    }

    db.query work_item {
      where = $db.work_item.journey_map_version_id in $version_ids && $db.work_item.account_id == $cop1_gate.account_id && (($want_status == false) || ($db.work_item.status == $input.status))
      sort = {created_at: "desc"}
      return = {type: "list"}
      output = ["id", "title", "status", "started_at", "finished_at", "journey_map_version_id", "parent_work_item_id"]
    } as $jobs

    var $rows {
      value = []
    }

    foreach ($jobs) {
      each as $j {
        var $jv {
          value = "v" ~ ($j.journey_map_version_id|to_text)
        }

        var $jmap {
          value = ($version_map|get:$jv:null) ?? 0
        }

        var $jm {
          value = "m" ~ ($jmap|to_text)
        }

        array.push $rows {
          value = {
            id         : $j.id
            title      : $j.title
            status     : $j.status
            started_at : $j.started_at
            finished_at: $j.finished_at
            map_id     : $jmap
            map_title  : (($titles|get:$jm:null) ?? "")
          }
        }
      }
    }
  }

  response = {journey_architecture_id: $pin, count: $rows|count, jobs: $rows}
}
