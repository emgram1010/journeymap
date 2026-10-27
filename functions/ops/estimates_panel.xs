// EST-1 (US-EST-1-07) — Health page "Estimates" panel: open jobs whose
// LATEST EST-1 event is `estimate_incomplete`, not a later
// `estimate_computed` that resolved it. Plain language, built for the
// product manager, same spirit as ops/group_issues.
//
// "Latest wins" is tracked the same way ops/group_issues.xs builds its
// accumulator: a fresh `var` lookup against a map built in an earlier,
// already-finished pass of THIS SAME loop (not a var.update read back
// in the same iteration) — the proven-safe shape (CLAUDE.md).
function "ops/estimates_panel" {
  input {
    text since? filters=trim {
      description = "ISO timestamp lower bound. Defaults to 30 days ago when omitted."
    }
  }

  stack {
    var $since {
      value = now|transform_timestamp:"30 days ago":"UTC"
    }

    conditional {
      if ($input.since != null && $input.since != "") {
        var.update $since {
          value = $input.since
        }
      }
    }

    db.query event_log {
      where = $db.event_log.feature == "EST-1" && ($db.event_log.step == "estimate_incomplete" || $db.event_log.step == "estimate_computed") && $db.event_log.created_at >= $since
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $events

    // Walk in ascending time order so the LAST write per job wins.
    var $latest_by_job {
      value = {}
    }

    foreach ($events) {
      each as $ev {
        var $job_key {
          value = $ev.entity_id|to_text
        }

        var.update $latest_by_job {
          value = $latest_by_job|set:$job_key:$ev
        }
      }
    }

    // Which jobs are still incomplete, in a stable order (oldest finding first).
    var $incomplete_job_ids {
      value = [-1]
    }

    var $incomplete_events {
      value = []
    }

    foreach ($events) {
      each as $ev2 {
        var $job_key2 {
          value = $ev2.entity_id|to_text
        }

        var $latest {
          value = $latest_by_job|get:$job_key2:null
        }

        conditional {
          if ($latest != null && $latest.id == $ev2.id && $latest.step == "estimate_incomplete") {
            array.push $incomplete_job_ids {
              value = $ev2.entity_id
            }

            array.push $incomplete_events {
              value = $ev2
            }
          }
        }
      }
    }

    db.query work_item {
      where = $db.work_item.id in $incomplete_job_ids
      return = {type: "list"}
    } as $jobs

    var $job_by_id {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        var $jk {
          value = $j.id|to_text
        }

        var.update $job_by_id {
          value = $job_by_id|set:$jk:$j
        }
      }
    }

    var $version_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j2 {
        array.push $version_ids {
          value = $j2.journey_map_version_id
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $versions

    var $version_by_id {
      value = {}
    }

    foreach ($versions) {
      each as $v {
        var $vk {
          value = $v.id|to_text
        }

        var.update $version_by_id {
          value = $version_by_id|set:$vk:$v
        }
      }
    }

    var $rows {
      value = []
    }

    foreach ($incomplete_events) {
      each as $iev {
        var $rk {
          value = $iev.entity_id|to_text
        }

        var $row_job {
          value = $job_by_id|get:$rk:null
        }

        conditional {
          if ($row_job != null && $row_job.status != "cancelled" && $row_job.status != "completed") {
            var $rvk {
              value = $row_job.journey_map_version_id|to_text
            }

            var $row_version {
              value = $version_by_id|get:$rvk:null
            }

            array.push $rows {
              value = {
                work_item_id  : $row_job.id
                job_title     : $row_job.title
                job_status    : $row_job.status
                map_title     : ($row_version.snapshot.title ?? "")
                version_no    : ($row_version.version_no ?? null)
                missing       : ($iev.metadata.missing ?? [])
                reasons       : ($iev.metadata.reasons ?? [])
                found_at      : $iev.created_at
              }
            }
          }
        }
      }
    }
  }

  response = {
    since: $since
    count: ($rows|count)
    jobs : $rows
  }
}
