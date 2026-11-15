// COP-5 story 05 - the copilot's OPEN tasks (not started or in progress) in ONE business, out of a list of task ids already known to be assigned to it on published days. Returns how many and a fingerprint (the date plus each task id and status, in id order) so a scheduled run can tell "nothing has changed since last time". The business filter is done by constraining the queries (maps of the business, their versions, their jobs), never by an if inside a loop.
function "copilot/open_work" {
  input {
    int account_id
    int journey_architecture_id
    int[] work_task_ids
    text date? filters=trim
  }

  stack {
    var $wt_ids {
      value = [-1]
    }

    foreach ($input.work_task_ids) {
      each as $w {
        array.push $wt_ids {
          value = $w
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.journey_architecture == $input.journey_architecture_id && $db.journey_map.account_id == $input.account_id
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
      where = $db.work_item.journey_map_version_id in $version_ids && $db.work_item.account_id == $input.account_id
      return = {type: "list"}
      output = ["id"]
    } as $jobs

    var $job_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }
      }
    }

    db.query work_task {
      where = $db.work_task.id in $wt_ids && $db.work_task.work_item_id in $job_ids && ($db.work_task.status == "not_started" || $db.work_task.status == "in_progress")
      sort = {work_task.id: "asc"}
      return = {type: "list"}
      output = ["id", "status"]
    } as $open

    var $fingerprint {
      value = $input.date
    }

    foreach ($open) {
      each as $t {
        var.update $fingerprint {
          value = $fingerprint ~ " " ~ ($t.id|to_text) ~ ":" ~ $t.status
        }
      }
    }

    var $open_count {
      value = $open|count
    }
  }

  response = {open_count: $open_count, fingerprint: $fingerprint}
}
