// EXC-1 (US-EXC-1-05) — A job's family: where it came from (`parent`)
// and what was sent off it (`children`). Read-only, logs nothing.
//
// Read from work_item.parent_work_item_id (the link) plus
// work_item_exception (the why: stage, reason, note, counts). A child
// added by hand under a parent (554 with parent_work_item_id) has no
// exception row; it still shows, with `via = "manual"`.
//
// `send_options` — for each step of this job, the maps its stage can send
// work to: `exception` links from the job's PINNED version (never the
// live map), any row of the stage (D-10), one per (step, target), with
// the target's title and whether it has a published version (an
// unpublished one is shown disabled; the server refuses it anyway).
// The planner's job detail and the performer's step screen both read
// this one list (US-EXC-1-05/06).
//
// Every per-row lookup is computed into a var and read with `??`; the
// only branches compare loop items to loop items (CLAUDE.md).
//
// EXC-2 (US-EXC-2-01) — additive: each of `parent` and `children[]`
// also carries a `progress` summary (task_count, finished_count,
// has_blocked, current_stage_key/label), computed once for the whole
// family by exceptions/job_progress and merged on below.
function "exceptions/job_links" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    precondition ($job != null) {
      error_type = "notfound"
      error = "Job not found"
    }

    // ── Parent ───────────────────────────────────────────────────────
    var $parent {
      value = null
    }

    conditional {
      if ($job.parent_work_item_id != 0) {
        db.get work_item {
          field_name = "id"
          field_value = $job.parent_work_item_id
        } as $parent_job

        db.query work_item_exception {
          where = $db.work_item_exception.child_work_item_id == $job.id
          return = {type: "single"}
        } as $parent_exc

        db.get journey_map_version {
          field_name = "id"
          field_value = $parent_job.journey_map_version_id
        } as $parent_version

        var $parent_stage_key {
          value = $parent_exc.stage_key ?? ""
        }

        var $parent_stage_label {
          value = $parent_stage_key
        }

        foreach ($parent_version.snapshot.stages ?? []) {
          each as $ps {
            conditional {
              if ($ps.key == $parent_stage_key) {
                var.update $parent_stage_label {
                  value = $ps.label ?? $parent_stage_key
                }
              }
            }
          }
        }

        var $parent_via {
          value = (($parent_exc|get:"id":0) == 0) ? "manual" : "exception"
        }

        var.update $parent {
          value = {
            work_item_id: $job.parent_work_item_id
            title       : $parent_job.title ?? ""
            status      : $parent_job.status ?? ""
            stage_key   : $parent_stage_key
            stage_label : $parent_stage_label
            reason_code : $parent_exc.reason_code ?? ""
            note        : $parent_exc.note ?? ""
            moved_lines : $parent_exc.moved_lines ?? []
            created_at  : $parent_exc.created_at ?? $job.created_at
            via         : $parent_via
          }
        }
      }
    }

    // ── Children ─────────────────────────────────────────────────────
    db.query work_item {
      where = $db.work_item.parent_work_item_id == $job.id
      sort = {work_item.id: "asc"}
      return = {type: "list"}
    } as $child_jobs

    db.query work_item_exception {
      where = $db.work_item_exception.parent_work_item_id == $job.id
      return = {type: "list"}
    } as $child_excs

    var $exc_by_child {
      value = {}
    }

    foreach ($child_excs) {
      each as $ce {
        var $ce_key {
          value = $ce.child_work_item_id|to_text
        }

        var.update $exc_by_child {
          value = $exc_by_child|set:$ce_key:$ce
        }
      }
    }

    var $child_version_ids {
      value = [-1]
    }

    // EXC-2 (US-EXC-2-01) — every id whose progress we need: the parent
    // (if any) plus every child, so ONE job_progress call covers the
    // whole family (CLAUDE.md: one query, never one per child).
    var $progress_target_ids {
      value = [-1]
    }

    conditional {
      if ($job.parent_work_item_id != 0) {
        array.push $progress_target_ids {
          value = $job.parent_work_item_id
        }
      }
    }

    foreach ($child_jobs) {
      each as $cjv {
        array.push $child_version_ids {
          value = $cjv.journey_map_version_id
        }

        array.push $progress_target_ids {
          value = $cjv.id
        }
      }
    }

    function.run "exceptions/job_progress" {
      input = {work_item_ids: $progress_target_ids}
    } as $progress_result

    conditional {
      if ($job.parent_work_item_id != 0) {
        var $parent_progress_key {
          value = "c:" ~ ($job.parent_work_item_id|to_text)
        }

        var $parent_progress_value {
          value = $progress_result.progress_by_job|get:$parent_progress_key:null
        }

        var.update $parent {
          value = $parent|set:"progress":$parent_progress_value
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id in $child_version_ids
      return = {type: "list"}
    } as $child_versions

    var $title_by_version {
      value = {}
    }

    foreach ($child_versions) {
      each as $cv {
        var $cv_key {
          value = $cv.id|to_text
        }

        var.update $title_by_version {
          value = $title_by_version|set:$cv_key:($cv.snapshot.title ?? "")
        }
      }
    }

    // The parent's stage labels, for "sent from <stage>". Keys are
    // prefixed with "k:" so a lookup key is never "" — `|get:""` returns
    // the WHOLE object, not null (found live: a manual child, which has
    // no stage, got every label as its stage_label).
    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $own_version

    var $own_stage_labels {
      value = {}
    }

    foreach ($own_version.snapshot.stages ?? []) {
      each as $os {
        var $os_key {
          value = "k:" ~ $os.key
        }

        var.update $own_stage_labels {
          value = $own_stage_labels|set:$os_key:($os.label ?? $os.key)
        }
      }
    }

    // ── What each step can send, from the PINNED version ─────────────
    var $exc_links {
      value = []
    }

    var $target_ids {
      value = [-1]
    }

    foreach ($own_version.snapshot.links ?? []) {
      each as $ol {
        conditional {
          if ($ol.link_type == "exception" && $ol.target_map_id > 0) {
            array.push $exc_links {
              value = $ol
            }

            array.push $target_ids {
              value = $ol.target_map_id
            }
          }
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $target_ids
      return = {type: "list"}
    } as $target_maps

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $target_ids
      return = {type: "list"}
    } as $target_versions

    var $target_title_by_id {
      value = {}
    }

    foreach ($target_maps) {
      each as $tm {
        var $tm_key {
          value = "m:" ~ ($tm.id|to_text)
        }

        var.update $target_title_by_id {
          value = $target_title_by_id|set:$tm_key:$tm.title
        }
      }
    }

    var $published_by_id {
      value = {}
    }

    foreach ($target_versions) {
      each as $tv {
        var $tv_key {
          value = "m:" ~ ($tv.journey_map_id|to_text)
        }

        var.update $published_by_id {
          value = $published_by_id|set:$tv_key:true
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id == $job.id
      sort = {work_task.id: "asc"}
      return = {type: "list"}
    } as $own_tasks

    var $send_seen {
      value = {}
    }

    var $send_rows {
      value = []
    }

    foreach ($own_tasks) {
      each as $ot {
        foreach ($exc_links) {
          each as $el {
            conditional {
              if ($el.stage_key == $ot.stage_key) {
                array.push $send_rows {
                  value = {work_task_id: $ot.id, stage_key: $ot.stage_key, target_map_id: $el.target_map_id}
                }
              }
            }
          }
        }
      }
    }

    // Second pass: de-duplicate (a target linked from two rows of one
    // stage is ONE option) and resolve titles — the duplicate test is a
    // FIELD computed before the seen-map is updated, then filtered on.
    var $send_marked {
      value = []
    }

    foreach ($send_rows) {
      each as $sr {
        var $sr_key {
          value = ($sr.work_task_id|to_text) ~ "::" ~ ($sr.target_map_id|to_text)
        }

        var $sr_dup {
          value = (($send_seen|get:$sr_key:null) != null)
        }

        var.update $send_seen {
          value = $send_seen|set:$sr_key:true
        }

        array.push $send_marked {
          value = $sr|set:"dup":$sr_dup
        }
      }
    }

    var $send_options {
      value = []
    }

    foreach ($send_marked) {
      each as $sm {
        conditional {
          if ($sm.dup == false) {
            var $sm_map_key {
              value = "m:" ~ ($sm.target_map_id|to_text)
            }

            var $sm_stage_lookup {
              value = "k:" ~ $sm.stage_key
            }

            var $sm_title {
              value = ($target_title_by_id|get:$sm_map_key:null) ?? "that map"
            }

            var $sm_published {
              value = (($published_by_id|get:$sm_map_key:null) ?? false) == true
            }

            var $sm_stage_label {
              value = ($own_stage_labels|get:$sm_stage_lookup:null) ?? $sm.stage_key
            }

            array.push $send_options {
              value = {
                work_task_id    : $sm.work_task_id
                stage_key       : $sm.stage_key
                stage_label     : $sm_stage_label
                target_map_id   : $sm.target_map_id
                target_map_title: $sm_title
                published       : $sm_published
              }
            }
          }
        }
      }
    }

    var $children {
      value = []
    }

    foreach ($child_jobs) {
      each as $ch {
        var $ch_key {
          value = $ch.id|to_text
        }

        var $ch_exc {
          value = $exc_by_child|get:$ch_key:null
        }

        var $ch_version_key {
          value = $ch.journey_map_version_id|to_text
        }

        var $ch_target_title {
          value = ($title_by_version|get:$ch_version_key:null) ?? ""
        }

        var $ch_stage_key {
          value = $ch_exc.stage_key ?? ""
        }

        var $ch_stage_lookup {
          value = "k:" ~ $ch_stage_key
        }

        var $ch_stage_label {
          value = ($own_stage_labels|get:$ch_stage_lookup:null) ?? $ch_stage_key
        }

        var $ch_via {
          value = (($ch_exc|get:"id":0) == 0) ? "manual" : "exception"
        }

        var $ch_progress_key {
          value = "c:" ~ $ch_key
        }

        var $ch_progress {
          value = $progress_result.progress_by_job|get:$ch_progress_key:null
        }

        array.push $children {
          value = {
            work_item_id    : $ch.id
            title           : $ch.title
            status          : $ch.status
            target_map_title: $ch_target_title
            stage_key       : $ch_stage_key
            stage_label     : $ch_stage_label
            reason_code     : $ch_exc.reason_code ?? ""
            note            : $ch_exc.note ?? ""
            moved_lines     : $ch_exc.moved_lines ?? []
            parent_blocked  : $ch_exc.parent_blocked ?? false
            created_at      : $ch_exc.created_at ?? $ch.created_at
            via             : $ch_via
            progress        : $ch_progress
          }
        }
      }
    }
  }

  response = {parent: $parent, children: $children, send_options: $send_options}
}
