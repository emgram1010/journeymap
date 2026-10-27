//  JOB-1 (US-JOB-1-03) — One job, with every task hydrated from its
//  PINNED version.
//
//  THIS IS WHERE THE PINNING PAYS OFF. The task text, done-when, owner
//  row and expected minutes are read out of the frozen snapshot the
//  job was created against — never from the live map, and never from a
//  newer version. Publish version 3 tomorrow and this job still reads
//  version 2, because that is the work people actually agreed to do.
//
//  `work_task` stores no text at all, so there is nothing to drift.
//  The row says WHICH cell and WHAT STATE; the version says what the
//  cell means.
//
//  `derived_status` is computed from the tasks every time and returned
//  alongside the stored `status`. They should always agree — the
//  stored one is a cache LOG-1 maintains — and GOV-1's audit compares
//  them. Returning both makes a disagreement visible rather than
//  something only a nightly job notices.
//
//  EST-1 (US-EST-1-05) — on a map WITH an Items row, each task's
//  expected_minutes now comes from estimate/estimate_job's per-stage
//  total (baseline_minutes when that stage has a missing rate), not
//  straight from its own cell. Two guards, both added in the Opus
//  review pass (2026-10-25):
//    - the override only applies to the task whose lens_key equals
//      the stage's owner_lens_key — a SECOND actor at the same stage
//      keeps its own cell duration, never the combined stage number
//      (the earlier version applied it to every task at the stage
//      regardless of row, which would double-count a two-actor stage);
//    - a stage is also "incomplete" when the whole job is incomplete
//      for a reason that isn't about THIS stage specifically (no
//      lines at all) — not just when this stage's own `missing` is
//      non-empty — so a brand-new job with zero lines shows the badge
//      instead of looking finished.
//  A map with NO Items row is completely unchanged.
//
//  EXC-1 (US-EXC-1-05) — additive: `parent` (null, or where this job
//  came from and why) and `children[]` (jobs sent off it, plus any added
//  by hand under it), from exceptions/job_links.
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

    function.run "estimate/estimate_job" {
      input = {work_item_id: $input.work_item_id}
    } as $estimate

    var $stage_est_by_key {
      value = {}
    }

    foreach ($estimate.stages) {
      each as $es {
        var.update $stage_est_by_key {
          value = $stage_est_by_key|set:$es.stage_key:$es
        }
      }
    }

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

        var $expected_minutes {
          value = ($cell.duration_minutes ?? null)
        }

        var $estimate_status {
          value = "n/a"
        }

        var $estimate_source {
          value = "n/a"
        }

        conditional {
          if ($estimate.has_items_row == true) {
            var $stage_est {
              value = $stage_est_by_key|get:$t.stage_key:null
            }

            conditional {
              if ($stage_est != null && $stage_est.owner_lens_key == $t.lens_key) {
                var.update $estimate_source {
                  value = $stage_est.source
                }

                var $stage_incomplete {
                  value = (($stage_est.missing|count) > 0)
                }

                conditional {
                  if ($stage_est.scales_with != "per_order" && $estimate.complete == false) {
                    var.update $stage_incomplete {
                      value = true
                    }
                  }
                }

                conditional {
                  if ($stage_incomplete == true) {
                    var.update $expected_minutes {
                      value = $stage_est.baseline_minutes
                    }

                    var.update $estimate_status {
                      value = "incomplete"
                    }
                  }

                  else {
                    var.update $expected_minutes {
                      value = $stage_est.total_minutes
                    }

                    var.update $estimate_status {
                      value = "complete"
                    }
                  }
                }
              }
            }
          }
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
            expected_minutes: $expected_minutes
            estimate_status : $estimate_status
            estimate_source : $estimate_source
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
      if ($any_progress) {
        var.update $derived {
          value = "in_progress"
        }
      }
    }

    conditional {
      if (($tasks|count) > 0 && $all_finished) {
        var.update $derived {
          value = "completed"
        }
      }
    }

    conditional {
      if ($any_blocked) {
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

    // EXC-1 (US-EXC-1-05) — where this job came from, and what was sent
    // off it. One shared read (also used by the perform screen).
    function.run "exceptions/job_links" {
      input = {work_item_id: $input.work_item_id}
    } as $links
  }

  response = {
    work_item       : $job
    parent          : $links.parent
    children        : $links.children
    pinned_version  : {id: $version.id, version_no: $version.version_no, title: $version.snapshot.title}
    derived_status  : $derived
    status_matches  : ($job.status == $derived)
    tasks           : $hydrated
    estimate_summary: {has_items_row: $estimate.has_items_row, complete: $estimate.complete, total_minutes: $estimate.total_minutes, missing: $estimate.missing, reasons: $estimate.reasons}
  }
}
