// JOB-1 (US-JOB-1-03) — One job, with every task hydrated from its
// PINNED version.
//
// THIS IS WHERE THE PINNING PAYS OFF. The task text, done-when, owner
// row and expected minutes are read out of the frozen snapshot the
// job was created against — never from the live map, and never from a
// newer version. Confirmed live: after version 3 was published with
// every label and task rewritten, a job pinned to version 2 still
// returned version 2's text, labels and minutes exactly.
//
// `work_task` stores no text at all, so there is nothing to drift.
// The row says WHICH cell and WHAT STATE; the version says what the
// cell means.
//
// `derived_status` is computed from the tasks every time and returned
// alongside the stored `status`. They should always agree — the
// stored one is a cache LOG-1 maintains — and GOV-1's audit compares
// them. Returning both makes a disagreement visible rather than
// something only a nightly job notices.
query "work_item/{work_item_id}" verb=GET {
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

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      sort = {work_task.id: "asc"}
      return = {type: "list"}
    } as $tasks

    // Index the pinned snapshot's cells and stages so hydration is
    // one pass, not a scan per task.
    var $key {
      value = ""
    }

    var $part_a {
      value = ""
    }

    var $part_b {
      value = ""
    }

    var $cell_map {
      value = {}
    }

    foreach ($version.snapshot.cells) {
      each as $c {
        var.update $part_a {
          value = $c.stage_key
        }

        var.update $part_b {
          value = $c.lens_key
        }

        var.update $key {
          value = $part_a ~ "~" ~ $part_b
        }

        var.update $cell_map {
          value = $cell_map|set:$key:$c
        }
      }
    }

    var $stage_labels {
      value = {}
    }

    foreach ($version.snapshot.stages) {
      each as $s {
        var.update $key {
          value = $s.key
        }

        var.update $stage_labels {
          value = $stage_labels|set:$key:$s.label
        }
      }
    }

    var $lens_labels {
      value = {}
    }

    foreach ($version.snapshot.lenses) {
      each as $l {
        var.update $key {
          value = $l.key
        }

        var.update $lens_labels {
          value = $lens_labels|set:$key:$l.label
        }
      }
    }

    var $hydrated {
      value = []
    }

    var $cell {
      value = null
    }

    var $stage_label {
      value = ""
    }

    var $lens_label {
      value = ""
    }

    foreach ($tasks) {
      each as $t {
        var.update $part_a {
          value = $t.stage_key
        }

        var.update $part_b {
          value = $t.lens_key
        }

        var.update $key {
          value = $part_a ~ "~" ~ $part_b
        }

        var.update $cell {
          value = $cell_map|get:$key:null
        }

        var.update $key {
          value = $t.stage_key
        }

        var.update $stage_label {
          value = $stage_labels|get:$key:null
        }

        var.update $key {
          value = $t.lens_key
        }

        var.update $lens_label {
          value = $lens_labels|get:$key:null
        }

        array.push $hydrated {
          value = {
            id              : $t.id
            stage_key       : $t.stage_key
            lens_key        : $t.lens_key
            status          : $t.status
            started_at      : $t.started_at
            completed_at    : $t.completed_at
            stage_label     : $stage_label
            owner_lens_label: $lens_label
            task            : ($cell.task ?? null)
            done_when       : ($cell.done_when ?? null)
            expected_minutes: ($cell.duration_minutes ?? null)
          }
        }
      }
    }

    // Derive the job's status from its tasks, the same rule as
    // jobModel.ts::deriveJobStatus. Cancelled is stored, not derived,
    // so it wins.
    var $any_blocked {
      value = false
    }

    var $all_finished {
      value = true
    }

    var $any_progress {
      value = false
    }

    foreach ($tasks) {
      each as $t {
        conditional {
          if ($t.status == "blocked") {
            var.update $any_blocked {
              value = true
            }
          }
        }

        conditional {
          if ($t.status != "done" && $t.status != "skipped") {
            var.update $all_finished {
              value = false
            }
          }
        }

        conditional {
          if ($t.status == "in_progress" || $t.status == "done" || $t.status == "skipped") {
            var.update $any_progress {
              value = true
            }
          }
        }
      }
    }

    var $derived {
      value = "open"
    }

    conditional {
      if ($any_progress == true) {
        var.update $derived {
          value = "in_progress"
        }
      }
    }

    conditional {
      if (($tasks|count) > 0 && $all_finished == true) {
        var.update $derived {
          value = "completed"
        }
      }
    }

    conditional {
      if ($any_blocked == true) {
        var.update $derived {
          value = "blocked"
        }
      }
    }

    conditional {
      if ($job.status == "cancelled") {
        var.update $derived {
          value = "cancelled"
        }
      }
    }
  }

  response = {
    work_item     : $job
    pinned_version: {id: $version.id, version_no: $version.version_no, title: $version.snapshot.title}
    derived_status: $derived
    status_matches: ($job.status == $derived)
    tasks         : $hydrated
  }
}
