// W3 (2026-10-17) — What the people doing the work actually reported.
//
// THE LOOP WAS ONE-WAY. `activity_log` has recorded every start, finish,
// block, skip and note since LOG-1, and until now NOTHING read any of
// it back — grep for `activity_log` across the planner and the only
// hits were the endpoint that WRITES it and three deletes checking
// whether a row exists. A performer could be blocked twice, leave a
// note explaining exactly why, and the planner had no screen that
// could ever show it. That is the gap W3 names: work gets done and
// the information dies there.
//
// This is the read half. Not variance — endpoint 568 already computes
// planned-vs-actual from these same rows — but the HUMAN half: what
// was said, by whom, and when.
//
// HYDRATED THE SAME WAY EVERYTHING ELSE IS: the step's wording comes
// from the job's PINNED version, never the live map, so a note reads
// against the text the person actually saw. Two extra queries for the
// whole list (the version, and the performers' names), never one per
// row.
//
// NOTES AND REASONS ARE THE POINT, so `event_type` is returned raw and
// unfiltered — a caller that wants only the notes can filter, but a
// planner looking at a job needs the whole sequence to make sense of
// it ("blocked, then a note, then unblocked" is a story; the note
// alone is not).
query "work_item/{work_item_id}/activity" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    db.query activity_log {
      where = $db.activity_log.work_item_id == $input.work_item_id
      sort = {activity_log.occurred_at: "asc", activity_log.id: "asc"}
      return = {type: "list"}
    } as $rows

    // Step text, keyed stage::lens off the job's pinned version.
    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    var $cell_map {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($version.snapshot.cells) {
      each as $c {
        var.update $key {
          value = $c.stage_key ~ "::" ~ $c.lens_key
        }

        var.update $cell_map {
          value = $cell_map|set:$key:$c
        }
      }
    }

    // Which step each row belongs to.
    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      return = {type: "list"}
    } as $work_tasks

    var $wt_by_id {
      value = {}
    }

    foreach ($work_tasks) {
      each as $wt {
        var.update $key {
          value = $wt.id|to_text
        }

        var.update $wt_by_id {
          value = $wt_by_id|set:$key:$wt
        }
      }
    }

    // Who reported it. One query for every performer on the list.
    var $user_ids {
      value = []
    }

    foreach ($rows) {
      each as $r0 {
        array.push $user_ids {
          value = $r0.performer_user_id
        }
      }
    }

    db.query user {
      where = $db.user.id in $user_ids
      return = {type: "list"}
    } as $users

    var $user_names {
      value = {}
    }

    foreach ($users) {
      each as $u {
        var.update $key {
          value = $u.id|to_text
        }

        var.update $user_names {
          value = $user_names|set:$key:$u.name
        }
      }
    }

    var $events {
      value = []
    }

    var $wt {
      value = null
    }

    var $cell {
      value = null
    }

    var $who {
      value = null
    }

    var $note_count {
      value = 0
    }

    var $blocked_count {
      value = 0
    }

    var $skipped_count {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $key {
          value = $r.work_task_id|to_text
        }

        var.update $wt {
          value = $wt_by_id|get:$key:null
        }

        var.update $key {
          value = ($wt.stage_key ?? "") ~ "::" ~ ($wt.lens_key ?? "")
        }

        var.update $cell {
          value = $cell_map|get:$key:null
        }

        var.update $key {
          value = $r.performer_user_id|to_text
        }

        var.update $who {
          value = $user_names|get:$key:null
        }

        array.push $events {
          value = {
            id            : $r.id
            work_task_id  : $r.work_task_id
            step_title    : ($cell.task ?? null)
            stage_key     : ($wt.stage_key ?? null)
            event_type    : $r.event_type
            reason_code   : $r.reason_code
            note          : $r.note
            occurred_at   : $r.occurred_at
            performer_name: $who
            source        : $r.source
          }
        }
      }
    }

    // Tallies read the LOOP ITEM, never a var set in the same
    // iteration, so the branch writes survive (CLAUDE.md).
    foreach ($rows) {
      each as $r2 {
        conditional {
          if ($r2.event_type == "blocked") {
            var.update $blocked_count {
              value = $blocked_count + 1
            }
          }
        }

        conditional {
          if ($r2.event_type == "skipped") {
            var.update $skipped_count {
              value = $skipped_count + 1
            }
          }
        }

        conditional {
          if ($r2.note != "" && $r2.note != null) {
            var.update $note_count {
              value = $note_count + 1
            }
          }
        }
      }
    }
  }

  response = {
    work_item_id : $input.work_item_id
    job_title    : $job.title
    event_count  : $events|count
    note_count   : $note_count
    blocked_count: $blocked_count
    skipped_count: $skipped_count
    events       : $events
  }
}
