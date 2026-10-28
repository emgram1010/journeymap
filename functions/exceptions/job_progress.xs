// EXC-2 (US-EXC-2-01) — One job's progress: how many of its steps are
// finished, whether any is blocked, and which stage is "now".
//
// Shared by exceptions/job_links for BOTH directions: a job's progress
// as a parent (seen from its child) and as a child (seen from its
// parent). Pulled into its own function (CLAUDE.md "one rule, one
// place") so job_links calls it once for the whole family instead of
// duplicating the tally per direction.
//
// finished = done OR skipped (D-4). "Current stage" = the stage of
// the LOWEST-POSITION unfinished step, where position is that job's
// OWN pinned snapshot.stages order (a child and its parent can be on
// different maps with different stage orders). A step whose stage key
// is missing from the snapshot sorts last (position 999999). All
// steps finished → current_stage_key = "".
//
// A stage at position 0 (the FIRST stage) is safe here even though it
// is read through `?? 999999`: XanoScript's `??` is strict, unlike its
// `==`/`!=`. Probed live 2026-10-27 (`0 ?? 999999` → 0) and confirmed
// on real data (jobs 125/126 correctly report s1, position 0).
//
// Every tally below is var.update + |get/|set + a plain ternary —
// never a conditional branching on a var updated earlier in the same
// foreach iteration (CLAUDE.md's silent-write-loss trap). Rows are
// built unconditionally in one pass over $tasks, then merged in a
// second unconditional pass, matching the de-dup pattern job_links.xs
// already uses for send_options.
function "exceptions/job_progress" {
  input {
    int[] work_item_ids
  }

  stack {
    db.query work_item {
      where = $db.work_item.id in $input.work_item_ids
      return = {type: "list"}
    } as $jobs

    // ── Seed every job's counters and record its version id ──────────
    var $task_count_by_job {
      value = {}
    }

    var $finished_count_by_job {
      value = {}
    }

    var $has_blocked_by_job {
      value = {}
    }

    var $min_pos_by_job {
      value = {}
    }

    var $min_stage_key_by_job {
      value = {}
    }

    var $job_version_by_id {
      value = {}
    }

    var $version_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j {
        var $j_key {
          value = "c:" ~ ($j.id|to_text)
        }

        var.update $task_count_by_job {
          value = $task_count_by_job|set:$j_key:0
        }

        var.update $finished_count_by_job {
          value = $finished_count_by_job|set:$j_key:0
        }

        var.update $has_blocked_by_job {
          value = $has_blocked_by_job|set:$j_key:false
        }

        var.update $min_pos_by_job {
          value = $min_pos_by_job|set:$j_key:999999999
        }

        var.update $min_stage_key_by_job {
          value = $min_stage_key_by_job|set:$j_key:""
        }

        var.update $job_version_by_id {
          value = $job_version_by_id|set:$j_key:$j.journey_map_version_id
        }

        array.push $version_ids {
          value = $j.journey_map_version_id
        }
      }
    }

    // ── Stage position + label, per version ───────────────────────────
    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $versions

    var $stage_pos_by_key {
      value = {}
    }

    var $stage_label_by_key {
      value = {}
    }

    var $pos_counter {
      value = 0
    }

    foreach ($versions) {
      each as $v {
        var.update $pos_counter {
          value = 0
        }

        foreach ($v.snapshot.stages ?? []) {
          each as $vs {
            var $vs_key {
              value = "v:" ~ ($v.id|to_text) ~ "::" ~ $vs.key
            }

            var.update $stage_pos_by_key {
              value = $stage_pos_by_key|set:$vs_key:$pos_counter
            }

            // `??` alone is not enough: it is STRICT (probed live 2026-10-27
            // — `0 ?? x` is 0, `"" ?? x` is ""), and an untouched label is ""
            // in live data, which would render "at " with nothing after it.
            // The `!= ""` test catches null too, because ==/!= ARE loose.
            var $vs_label_raw {
              value = $vs.label ?? ""
            }

            var $vs_label {
              value = ($vs_label_raw != "") ? $vs_label_raw : $vs.key
            }

            var.update $stage_label_by_key {
              value = $stage_label_by_key|set:$vs_key:$vs_label
            }

            var.update $pos_counter {
              value = $pos_counter + 1
            }
          }
        }
      }
    }

    // ── One row per task, unconditional ───────────────────────────────
    // SORTED, deliberately. Two owner rows at one stage share a position, so
    // without an order the winner of that tie is whatever order the rows came
    // back in — `current_stage_key` could differ between two identical calls.
    // Matches 555's own `work_task.id asc`.
    db.query work_task {
      where = $db.work_task.work_item_id in $input.work_item_ids
      sort = {work_task.id: "asc"}
      return = {type: "list"}
    } as $tasks

    var $task_rows {
      value = []
    }

    foreach ($tasks) {
      each as $t {
        var $row_job_key {
          value = "c:" ~ ($t.work_item_id|to_text)
        }

        var $row_finished_inc {
          value = (($t.status == "done" || $t.status == "skipped")|to_int)
        }

        var $row_blocked {
          value = ($t.status == "blocked")
        }

        var $row_ver_id {
          value = $job_version_by_id|get:$row_job_key:0
        }

        var $row_ver_text {
          value = $row_ver_id|to_text
        }

        var $row_stage_lookup {
          value = "v:" ~ $row_ver_text ~ "::" ~ $t.stage_key
        }

        var $row_pos_raw {
          value = $stage_pos_by_key|get:$row_stage_lookup:null
        }

        var $row_pos {
          value = $row_pos_raw ?? 999999
        }

        var $row_unfinished_pos {
          value = ($row_finished_inc == 1) ? 999999999 : $row_pos
        }

        array.push $task_rows {
          value = {
            job_key       : $row_job_key
            finished_inc  : $row_finished_inc
            blocked       : $row_blocked
            unfinished_pos: $row_unfinished_pos
            stage_key     : $t.stage_key
          }
        }
      }
    }

    // ── Merge rows into per-job totals — no conditional at all, only
    // var.update + |get/|set + a plain ternary ─────────────────────────
    foreach ($task_rows) {
      each as $row {
        var.update $task_count_by_job {
          value = $task_count_by_job|set:$row.job_key:(($task_count_by_job|get:$row.job_key:0) + 1)
        }

        var.update $finished_count_by_job {
          value = $finished_count_by_job|set:$row.job_key:(($finished_count_by_job|get:$row.job_key:0) + $row.finished_inc)
        }

        var $prev_blocked {
          value = $has_blocked_by_job|get:$row.job_key:false
        }

        var.update $has_blocked_by_job {
          value = $has_blocked_by_job|set:$row.job_key:($prev_blocked || $row.blocked)
        }

        var $prev_min {
          value = $min_pos_by_job|get:$row.job_key:999999999
        }

        var $is_new_min {
          value = ($row.unfinished_pos < $prev_min)
        }

        var $next_min {
          value = $is_new_min ? $row.unfinished_pos : $prev_min
        }

        var.update $min_pos_by_job {
          value = $min_pos_by_job|set:$row.job_key:$next_min
        }

        var $prev_stage {
          value = $min_stage_key_by_job|get:$row.job_key:""
        }

        var $next_stage {
          value = $is_new_min ? $row.stage_key : $prev_stage
        }

        var.update $min_stage_key_by_job {
          value = $min_stage_key_by_job|set:$row.job_key:$next_stage
        }
      }
    }

    // ── Build the final progress object per job ────────────────────────
    var $progress_by_job {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        var $out_key {
          value = "c:" ~ ($j.id|to_text)
        }

        var $out_task_count {
          value = $task_count_by_job|get:$out_key:0
        }

        var $out_finished_count {
          value = $finished_count_by_job|get:$out_key:0
        }

        var $out_has_blocked {
          value = $has_blocked_by_job|get:$out_key:false
        }

        var $out_min_pos {
          value = $min_pos_by_job|get:$out_key:999999999
        }

        var $out_all_finished {
          value = ($out_min_pos >= 999999999)
        }

        var $out_stage_key {
          value = $out_all_finished ? "" : ($min_stage_key_by_job|get:$out_key:"")
        }

        var $out_ver_id {
          value = $job_version_by_id|get:$out_key:0
        }

        var $out_ver_text {
          value = $out_ver_id|to_text
        }

        var $out_label_lookup {
          value = "v:" ~ $out_ver_text ~ "::" ~ $out_stage_key
        }

        var $out_label_raw {
          value = $stage_label_by_key|get:$out_label_lookup:null
        }

        var $out_label_safe {
          value = ($out_label_raw != "") ? $out_label_raw : $out_stage_key
        }

        var $out_stage_label {
          value = $out_all_finished ? "" : $out_label_safe
        }

        var $out_progress {
          value = {
            task_count         : $out_task_count
            finished_count     : $out_finished_count
            has_blocked        : $out_has_blocked
            current_stage_key  : $out_stage_key
            current_stage_label: $out_stage_label
          }
        }

        var.update $progress_by_job {
          value = $progress_by_job|set:$out_key:$out_progress
        }
      }
    }
  }

  response = {
    progress_by_job: $progress_by_job
  }
}
