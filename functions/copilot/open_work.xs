// COP-5 story 05 - the copilot's OPEN tasks (not started or in progress) in ONE business, out of a list of task ids already known to be assigned to it on published days. Returns how many and a fingerprint (the date plus each task id and status, in id order, plus how many held actions the owner has decided and the newest note) so a scheduled run can tell "nothing has changed since last time". The business filter is done by constraining the queries (maps of the business, their versions, their jobs), never by an if inside a loop.
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

    // Final review R6: the owner deciding a held action, or adding or editing a note, is new work
    // for the copilot even when no task changed, so both are part of the fingerprint.
    db.query copilot_action {
      where = $db.copilot_action.account_id == $input.account_id && $db.copilot_action.journey_architecture_id == $input.journey_architecture_id && $db.copilot_action.status in ["approved", "edited", "rejected", "executed"]
      return = {type: "count"}
    } as $decided

    db.query copilot_note {
      where = $db.copilot_note.account_id == $input.account_id && $db.copilot_note.journey_architecture_id == $input.journey_architecture_id
      sort = {copilot_note.updated_at: "desc"}
      return = {type: "list"}
      output = ["id", "updated_at"]
    } as $notes

    var $newest_note {
      value = $notes|slice:0:1
    }

    var $note_count {
      value = $notes|count
    }

    var $note_mark {
      value = ($note_count|to_text)
    }

    foreach ($newest_note) {
      each as $nn {
        var.update $note_mark {
          value = $note_mark ~ "@" ~ ($nn.id|to_text) ~ "@" ~ ($nn.updated_at|to_text)
        }
      }
    }

    var.update $fingerprint {
      value = $fingerprint ~ " a:" ~ ($decided|to_text) ~ " n:" ~ $note_mark
    }
  }

  response = {open_count: $open_count, fingerprint: $fingerprint}
}
