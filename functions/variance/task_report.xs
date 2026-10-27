// VAR-1 (US-VAR-1-03, MVP slice) — Per-job variance report. For every
// task in the job: its own activity log replayed through
// `variance/compute_task_variance`, with expected minutes from the
// PINNED version, and scheduled minutes + planned start from the
// PUBLISHED snapshot if (and only if) that task's slot has been
// published — exactly the "three durations, three owners" rule the
// epic states. A task never scheduled, or scheduled but not yet
// published, correctly gets `scheduled_minutes: null` rather than a
// guess.
//
// READ-ONLY. Nothing here writes anything — not the log, not the
// version, not the publication.
//
// One `activity_log` query PER TASK, same accepted shape as
// `ops/audit_execution`'s per-task replay: fine for a job's task
// count (single digits in practice), not something to put behind a
// high-traffic path without revisiting.
function "variance/task_report" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      sort = {work_task.id: "asc"}
      return = {type: "list"}
    } as $tasks

    // EST-1 (US-EST-1-05/FT-EST-1-09) — on a map WITH an Items row,
    // "expected" is the real per-stage estimate (baseline only when
    // that stage has a missing rate), not the raw cell duration. One
    // call for the whole job; a map with no Items row is unchanged.
    function.run "estimate/estimate_job" {
      input = {work_item_id: $input.work_item_id}
    } as $job_estimate

    var $stage_est_by_key {
      value = {}
    }

    foreach ($job_estimate.stages) {
      each as $jes {
        var.update $stage_est_by_key {
          value = $stage_est_by_key|set:$jes.stage_key:$jes
        }
      }
    }

    // Expected minutes, keyed by "stage_key::lens_key" from the pinned version.
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

    var $task_ids {
      value = []
    }

    foreach ($tasks) {
      each as $t {
        array.push $task_ids {
          value = $t.id
        }
      }
    }

    // Which scheduled slot (if any) does each task sit on?
    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id in $task_ids
      return = {type: "list"}
    } as $links

    var $slot_by_wt {
      value = {}
    }

    var $slot_ids {
      value = []
    }

    foreach ($links) {
      each as $l {
        var.update $key {
          value = $l.work_task_id|to_text
        }

        var.update $slot_by_wt {
          value = $slot_by_wt|set:$key:$l.planner_task_id
        }

        array.push $slot_ids {
          value = $l.planner_task_id
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.id in $slot_ids
      return = {type: "list"}
    } as $slots

    var $timeline_by_slot {
      value = {}
    }

    var $timeline_ids {
      value = []
    }

    foreach ($slots) {
      each as $s {
        var.update $key {
          value = $s.id|to_text
        }

        var.update $timeline_by_slot {
          value = $timeline_by_slot|set:$key:$s.timeline_id
        }

        array.push $timeline_ids {
          value = $s.timeline_id
        }
      }
    }

    db.query planner_timeline {
      where = $db.planner_timeline.id in $timeline_ids
      return = {type: "list"}
    } as $timelines

    var $timeline_meta {
      value = {}
    }

    foreach ($timelines) {
      each as $tl {
        var.update $key {
          value = $tl.id|to_text
        }

        var.update $timeline_meta {
          value = $timeline_meta|set:$key:{planned_date: $tl.planned_date, start_time: $tl.start_time}
        }
      }
    }

    db.query plan_publication {
      where = $db.plan_publication.timeline_id in $timeline_ids
      return = {type: "list"}
    } as $pubs

    var $pub_by_timeline {
      value = {}
    }

    foreach ($pubs) {
      each as $p {
        var.update $key {
          value = $p.timeline_id|to_text
        }

        var.update $pub_by_timeline {
          value = $pub_by_timeline|set:$key:$p.snapshot
        }
      }
    }

    // Per-task results.
    var $results {
      value = []
    }

    var $outlier_count {
      value = 0
    }

    var $warning_count {
      value = 0
    }

    var $cell {
      value = null
    }

    var $expected {
      value = null
    }

    var $slot_id {
      value = null
    }

    var $timeline_id {
      value = null
    }

    var $pub_snapshot {
      value = null
    }

    var $scheduled {
      value = null
    }

    var $planned_start {
      value = null
    }

    var $matched_item {
      value = null
    }

    var $base_start_ms {
      value = null
    }

    var $cumulative {
      value = 0
    }

    var $meta {
      value = null
    }

    foreach ($tasks) {
      each as $t {
        // Expected, from the pinned version.
        var.update $key {
          value = $t.stage_key ~ "::" ~ $t.lens_key
        }

        var.update $cell {
          value = $cell_map|get:$key:null
        }

        var.update $expected {
          value = ($cell.duration_minutes ?? null)
        }

        // EST-1 Opus review fixes (2026-10-25), mirrored from 555/560/
        // 583: the override only applies to the task whose lens_key is
        // the stage's OWNER — a second actor at the same stage keeps
        // the raw cell duration, never the combined stage total
        // (double-counting otherwise). And a stage also counts as
        // incomplete when the WHOLE job is incomplete for a reason
        // that isn't this stage's own (no lines at all), not only
        // when this stage's own `missing` is non-empty. Reads
        // `$job_estimate.complete` directly (one job, no map), so
        // `== false` is a plain, safe comparison.
        conditional {
          if ($job_estimate.has_items_row == true) {
            var $var_stage_est {
              value = $stage_est_by_key|get:$t.stage_key:null
            }

            conditional {
              if ($var_stage_est != null && $var_stage_est.owner_lens_key == $t.lens_key) {
                var $var_incomplete {
                  value = (($var_stage_est.missing|count) > 0)
                }

                conditional {
                  if ($var_stage_est.scales_with != "per_order" && $job_estimate.complete == false) {
                    var.update $var_incomplete {
                      value = true
                    }
                  }
                }

                conditional {
                  if ($var_incomplete == true) {
                    var.update $expected {
                      value = $var_stage_est.baseline_minutes
                    }
                  }

                  else {
                    var.update $expected {
                      value = $var_stage_est.total_minutes
                    }
                  }
                }
              }
            }
          }
        }

        // Scheduled + planned start, only if this task's slot has been published.
        var.update $scheduled {
          value = null
        }

        var.update $planned_start {
          value = null
        }

        var.update $key {
          value = $t.id|to_text
        }

        var.update $slot_id {
          value = $slot_by_wt|get:$key:null
        }

        conditional {
          if ($slot_id != null) {
            var.update $key {
              value = $slot_id|to_text
            }

            var.update $timeline_id {
              value = $timeline_by_slot|get:$key:null
            }

            var.update $key {
              value = $timeline_id|to_text
            }

            var.update $pub_snapshot {
              value = $pub_by_timeline|get:$key:null
            }

            conditional {
              if ($pub_snapshot != null) {
                var.update $matched_item {
                  value = null
                }

                foreach ($pub_snapshot.items) {
                  each as $i {
                    conditional {
                      if ($i.planner_task_id == $slot_id) {
                        var.update $matched_item {
                          value = $i
                        }
                      }
                    }
                  }
                }

                conditional {
                  if ($matched_item != null) {
                    var.update $scheduled {
                      value = $matched_item.scheduled_minutes
                    }

                    var.update $meta {
                      value = $timeline_meta|get:$key:null
                    }

                    var.update $cumulative {
                      value = 0
                    }

                    foreach ($pub_snapshot.items) {
                      each as $i2 {
                        conditional {
                          if ($i2.seq < $matched_item.seq) {
                            var.update $cumulative {
                              value = $cumulative + $i2.scheduled_minutes
                            }
                          }
                        }
                      }
                    }

                    var.update $base_start_ms {
                      value = ($meta.planned_date ~ " " ~ $meta.start_time ~ ":00")|parse_timestamp:"Y-m-d H:i:s":"UTC"
                    }

                    var.update $planned_start {
                      value = ($base_start_ms|to_int)|add_secs_to_timestamp:($cumulative * 60)
                    }
                  }
                }
              }
            }
          }
        }

        db.query activity_log {
          where = $db.activity_log.work_task_id == $t.id
          sort = {occurred_at: "asc", id: "asc"}
          return = {type: "list"}
        } as $events

        var $plain_events {
          value = []
        }

        foreach ($events) {
          each as $ev {
            array.push $plain_events {
              value = {event_type: $ev.event_type, occurred_at: $ev.occurred_at}
            }
          }
        }

        function.run "variance/compute_task_variance" {
          input = {
            events           : $plain_events
            expected_minutes : $expected
            scheduled_minutes: $scheduled
            planned_start_at : $planned_start
          }
        } as $v

        conditional {
          if ($v.is_outlier) {
            var.update $outlier_count {
              value = $outlier_count + 1
            }
          }
        }

        var.update $warning_count {
          value = $warning_count + ($v.warnings|count)
        }

        array.push $results {
          value = {
            work_task_id          : $t.id
            stage_key             : $t.stage_key
            lens_key              : $t.lens_key
            status                : $t.status
            expected_minutes      : $expected
            scheduled_minutes     : $scheduled
            actual_minutes        : $v.actual_minutes
            blocked_minutes       : $v.blocked_minutes
            expected_gap_minutes  : $v.expected_gap_minutes
            expected_gap_pct      : $v.expected_gap_pct
            scheduled_gap_minutes : $v.scheduled_gap_minutes
            scheduled_gap_pct     : $v.scheduled_gap_pct
            start_lateness_minutes: $v.start_lateness_minutes
            is_outlier            : $v.is_outlier
            warnings              : $v.warnings
          }
        }
      }
    }
  }

  response = {
    work_item_id  : $input.work_item_id
    task_count    : $tasks|count
    outlier_count : $outlier_count
    warning_count : $warning_count
    tasks         : $results
  }
}
