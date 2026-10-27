// SCHED-1 (US-SCHED-1-03) — The job work waiting to be scheduled.
//
// Everything in this plan's jobs that has no slot on the schedule
// yet, with its text and expected minutes read from each job's
// PINNED version — so the backlog shows what was agreed, not what
// the live map says today.
//
// CANCELLED JOBS ARE EXCLUDED. Their steps are history, not work
// waiting to happen, and offering them for scheduling would put
// abandoned work back in front of the planner.
//
// BLK-1 (US-BLK-1-01, 2026-10-21) — ONE ROW IS NOW ONE CARD, NOT ONE
// STEP. A card is one job's unscheduled steps FOR ONE ACTOR ROW, which
// is the unit a person actually picks up. Before this, a customer's
// return arrived as eight separate rows.
//
// WHY THE ACTOR ROW IS PART OF THE KEY. Checked live before building:
// 7 of 23 existing jobs have steps across two rows (`sales` and
// `ops`). Grouping by job alone would offer a card mixing two roles,
// and whoever took it would be handed somebody else's work. For a
// single-row map the two are identical.
//
// STEP ORDER COMES FROM THE SNAPSHOT'S `stages` ARRAY, walked in
// order, rather than from sorting the tasks afterwards. ORD-1 made
// stage order mutable, so a job pinned to v2 must use v2's order and
// not the live map's — and there is no array sort to get wrong.
//
// "Unscheduled" is decided by absence from `planner_task_work_task`.
// Two passes, as everywhere in this codebase: the link lookup is
// recorded as a FIELD first, then filtered on a loop item's own
// field, because branching on a variable set earlier in the same
// iteration silently loses the write (CLAUDE.md). The grouping itself
// copies `functions/ops/group_issues.xs` exactly — a fresh `var`
// inside the iteration, an order-tracking array alongside the map.
query "workspace/{workspace_id}/backlog_work" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id && $db.work_item.status != "cancelled"
      return = {type: "list"}
    } as $jobs

    var $job_ids {
      value = []
    }

    // EST-1 Opus review fix — seeded with a sentinel (CLAUDE.md: `in`
    // against an empty array is untested; `in [-1]` correctly matches
    // nothing). Needed now because the schema-version pre-check below
    // runs this `in $version_ids` query UNCONDITIONALLY, including for
    // a plan with zero jobs — the original code only ever queried
    // $versions inside the `$job_ids|count > 0` guard.
    var $version_ids {
      value = [-1]
    }

    var $key {
      value = ""
    }

    var $job_by_id {
      value = {}
    }

    // EST-1 (US-EST-1-05) — one estimate per job (not per task), looked
    // up below by "job_id::stage_key" so Pass 1 can override a job's
    // raw cell duration with its real per-stage estimate when the
    // job's map has an Items row. A map with no Items row is untouched:
    // $items_row_by_job stays false and nothing downstream changes.
    var $items_row_by_job {
      value = {}
    }

    // EST-1 Opus review fix — job_id -> estimate.complete, so a stage
    // can be marked incomplete for a job-wide reason (no lines at all)
    // and not only for its own `missing`. Read with `|has` to test
    // presence, never `== null`/`!= null` — `complete` is legitimately
    // `false` for an incomplete job, and this engine's null comparison
    // is PHP-style loose equality where `false == null` is TRUE
    // (CLAUDE.md), so a null-check here would silently discard every
    // real `false`. Defaults to "complete" (true) for any job this map
    // was never built for (i.e. its map has no Items row).
    var $job_complete_by_job {
      value = {}
    }

    var $stage_est_by_jobstage {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }

        array.push $version_ids {
          value = $j.journey_map_version_id
        }

        var.update $key {
          value = $j.id|to_text
        }

        var.update $job_by_id {
          value = $job_by_id|set:$key:$j
        }
      }
    }

    // EXC-1 (US-EXC-1-05) — how many open child jobs each job has. The
    // children are in $jobs already (same plan, not cancelled). The branch
    // reads only the loop item; the lookup's null (a variable-key |get
    // ignores its default — CLAUDE.md) is turned into 0 with ??.
    var $child_counts {
      value = {}
    }

    foreach ($jobs) {
      each as $cj {
        conditional {
          if ($cj.parent_work_item_id != 0) {
            var $cj_parent_key {
              value = $cj.parent_work_item_id|to_text
            }

            var $cj_prev {
              value = ($child_counts|get:$cj_parent_key:null) ?? 0
            }

            var.update $child_counts {
              value = $child_counts|set:$cj_parent_key:($cj_prev + 1)
            }
          }
        }
      }
    }

    // CHEAP PRE-CHECK before paying for `estimate/estimate_job` (which
    // re-reads the same version plus the job's lines): read just
    // schema_version for every distinct version this plan's jobs point
    // at, ONE query, and only call the real formula for a job whose map
    // actually has an Items row. In a plan with many jobs and few (or
    // no) Items-row maps — true of every plan that predates RATE-1 —
    // this keeps the backlog's cost close to what it was before EST-1,
    // instead of one extra round trip per job regardless of need.
    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $prelim_versions

    var $schema_version_by_version_id {
      value = {}
    }

    foreach ($prelim_versions) {
      each as $pv {
        var $pv_id_key {
          value = $pv.id|to_text
        }

        var.update $schema_version_by_version_id {
          value = $schema_version_by_version_id|set:$pv_id_key:($pv.snapshot.schema_version ?? 1)
        }
      }
    }

    foreach ($jobs) {
      each as $j3 {
        var $j3_key {
          value = $j3.id|to_text
        }

        var $j3_version_key {
          value = $j3.journey_map_version_id|to_text
        }

        var $j3_schema_version {
          value = $schema_version_by_version_id|get:$j3_version_key:1
        }

        conditional {
          if ($j3_schema_version >= 2) {
            function.run "estimate/estimate_job" {
              input = {work_item_id: $j3.id}
            } as $job_estimate

            var.update $items_row_by_job {
              value = $items_row_by_job|set:$j3_key:$job_estimate.has_items_row
            }

            var.update $job_complete_by_job {
              value = $job_complete_by_job|set:$j3_key:$job_estimate.complete
            }

            foreach ($job_estimate.stages) {
              each as $jes {
                var $jobstage_key {
                  value = $j3_key ~ "::" ~ $jes.stage_key
                }

                var.update $stage_est_by_jobstage {
                  value = $stage_est_by_jobstage|set:$jobstage_key:$jes
                }
              }
            }
          }
        }
      }
    }

    var $cards {
      value = []
    }

    conditional {
      if (($job_ids|count) > 0) {
        db.query work_task {
          where = $db.work_task.work_item_id in $job_ids
          sort = {work_task.id: "asc"}
          return = {type: "list"}
        } as $work_tasks

        // Reuses $prelim_versions (queried above for the schema-version
        // pre-check) instead of a second, identical query.
        var $versions {
          value = $prelim_versions
        }

        // Cell text and minutes, keyed version~stage~lens.
        var $cell_map {
          value = {}
        }

        // The stage list of each version, in order, keyed by version id.
        var $stages_by_version {
          value = {}
        }

        // Row labels, keyed version~lens.
        var $lens_label_map {
          value = {}
        }

        var $part_a {
          value = ""
        }

        var $part_b {
          value = ""
        }

        foreach ($versions) {
          each as $v {
            var.update $key {
              value = $v.id|to_text
            }

            var.update $stages_by_version {
              value = $stages_by_version|set:$key:$v.snapshot.stages
            }

            foreach ($v.snapshot.lenses) {
              each as $ln {
                var.update $part_a {
                  value = ($v.id|to_text) ~ "~" ~ ($ln|get:"key":"")
                }

                var.update $lens_label_map {
                  value = $lens_label_map|set:$part_a:($ln|get:"label":"")
                }
              }
            }

            foreach ($v.snapshot.cells) {
              each as $c {
                var.update $part_a {
                  value = ($v.id|to_text) ~ "~" ~ $c.stage_key
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
          }
        }

        // Which work tasks already have a slot.
        db.query planner_task_work_task {
          return = {type: "list"}
        } as $links

        var $linked {
          value = {}
        }

        foreach ($links) {
          each as $l {
            var.update $key {
              value = $l.work_task_id|to_text
            }

            var.update $linked {
              value = $linked|set:$key:1
            }
          }
        }

        // Pass 1 — candidates carrying their lookups as fields.
        var $candidates {
          value = []
        }

        var $job {
          value = null
        }

        var $cell {
          value = null
        }

        foreach ($work_tasks) {
          each as $wt {
            var.update $key {
              value = $wt.work_item_id|to_text
            }

            var.update $job {
              value = $job_by_id|get:$key:null
            }

            var.update $part_a {
              value = ($job.journey_map_version_id|to_text) ~ "~" ~ $wt.stage_key
            }

            var.update $part_b {
              value = $wt.lens_key
            }

            var.update $key {
              value = $part_a ~ "~" ~ $part_b
            }

            var.update $cell {
              value = $cell_map|get:$key:null
            }

            var.update $key {
              value = $wt.id|to_text
            }

            // EST-1 (US-EST-1-05) — override the raw cell duration with
            // the job's real per-stage estimate, only when its map has
            // an Items row. $job_item_key was set above when the job
            // was indexed, before this (or any) task loop started.
            var $job_item_key {
              value = $wt.work_item_id|to_text
            }

            var $job_has_items_row {
              value = $items_row_by_job|get:$job_item_key:false
            }

            var $cand_expected_minutes {
              value = ($cell.duration_minutes ?? null)
            }

            var $cand_estimate_status {
              value = "n/a"
            }

            var $cand_estimate_source {
              value = "n/a"
            }

            // EST-1 Opus review fixes (2026-10-25): the override only
            // applies to the task whose lens_key is the stage's OWNER
            // — a second actor at the same stage keeps its own cell
            // duration, never the combined number (double-counting
            // otherwise). And a stage also counts as incomplete when
            // the WHOLE job is incomplete for a reason that isn't this
            // stage's own (no lines at all), not just when this
            // stage's own `missing` is non-empty.
            conditional {
              if ($job_has_items_row == true) {
                var $jobstage_lookup {
                  value = $job_item_key ~ "::" ~ $wt.stage_key
                }

                var $cand_stage_est {
                  value = $stage_est_by_jobstage|get:$jobstage_lookup:null
                }

                conditional {
                  if ($cand_stage_est != null && $cand_stage_est.owner_lens_key == $wt.lens_key) {
                    var.update $cand_estimate_source {
                      value = $cand_stage_est.source
                    }

                    // EST-1 Opus review fix, round 2 — `$x != null` is
                    // unsafe here: `complete` can legitimately be `false`,
                    // and this engine's `==`/`!=` against `null` is
                    // PHP-style loose equality where `false == null` is
                    // TRUE (CLAUDE.md). That made the first version of
                    // this check silently skip the update whenever a job
                    // was genuinely incomplete, leaving the default
                    // `true` in place. `|has` checks presence without
                    // ever comparing the value itself to `null`.
                    var $cand_job_complete {
                      value = true
                    }

                    conditional {
                      if ($job_complete_by_job|has:$job_item_key) {
                        var.update $cand_job_complete {
                          value = $job_complete_by_job|get:$job_item_key:true
                        }
                      }
                    }

                    var $cand_incomplete {
                      value = (($cand_stage_est.missing|count) > 0)
                    }

                    conditional {
                      if ($cand_stage_est.scales_with != "per_order" && $cand_job_complete == false) {
                        var.update $cand_incomplete {
                          value = true
                        }
                      }
                    }

                    conditional {
                      if ($cand_incomplete == true) {
                        var.update $cand_expected_minutes {
                          value = $cand_stage_est.baseline_minutes
                        }

                        var.update $cand_estimate_status {
                          value = "incomplete"
                        }
                      }

                      else {
                        var.update $cand_expected_minutes {
                          value = $cand_stage_est.total_minutes
                        }

                        var.update $cand_estimate_status {
                          value = "complete"
                        }
                      }
                    }
                  }
                }
              }
            }

            array.push $candidates {
              value = {
                work_task_id    : $wt.id
                work_item_id    : $wt.work_item_id
                version_id      : $job.journey_map_version_id
                job_title       : $job.title
                stage_key       : $wt.stage_key
                lens_key        : $wt.lens_key
                status          : $wt.status
                task            : ($cell.task ?? null)
                done_when       : ($cell.done_when ?? null)
                expected_minutes: $cand_expected_minutes
                estimate_status : $cand_estimate_status
                estimate_source : $cand_estimate_source
                is_linked       : ($linked|get:$key:null)
              }
            }
          }
        }

        // Pass 2 — keep only the unscheduled ones, indexed for the walk
        // below by job::lens::stage, and remember which cards exist.
        var $step_index {
          value = {}
        }

        var $card_seen {
          value = {}
        }

        var $card_order {
          value = []
        }

        foreach ($candidates) {
          each as $c {
            conditional {
              if ($c.is_linked == null) {
                var $card_key {
                  value = ($c.work_item_id|to_text) ~ "::" ~ $c.lens_key
                }

                var $step_key {
                  value = $card_key ~ "::" ~ $c.stage_key
                }

                var.update $step_index {
                  value = $step_index|set:$step_key:$c
                }

                var $already {
                  value = $card_seen|get:$card_key:null
                }

                conditional {
                  if ($already == null) {
                    var.update $card_seen {
                      value = $card_seen|set:$card_key:1
                    }

                    array.push $card_order {
                      value = {
                        card_key    : $card_key
                        work_item_id: $c.work_item_id
                        version_id  : $c.version_id
                        job_title   : $c.job_title
                        lens_key    : $c.lens_key
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // Pass 3 — build each card by walking its version's stages IN
        // ORDER and picking up whichever of its steps are unscheduled.
        var $stage_list {
          value = []
        }

        var $steps {
          value = []
        }

        var $ids {
          value = []
        }

        var $minutes {
          value = 0
        }

        var $card_any_incomplete {
          value = false
        }

        var $card_any_estimated {
          value = false
        }

        var $first_step {
          value = null
        }

        var $last_label {
          value = ""
        }

        var $hit {
          value = null
        }

        var $lens_label {
          value = ""
        }

        foreach ($card_order) {
          each as $card {
            var.update $key {
              value = $card.version_id|to_text
            }

            var.update $stage_list {
              value = $stages_by_version|get:$key:[]
            }

            var.update $part_a {
              value = ($card.version_id|to_text) ~ "~" ~ $card.lens_key
            }

            var.update $lens_label {
              value = $lens_label_map|get:$part_a:""
            }

            var.update $steps {
              value = []
            }

            var.update $ids {
              value = []
            }

            var.update $minutes {
              value = 0
            }

            var.update $card_any_incomplete {
              value = false
            }

            var.update $card_any_estimated {
              value = false
            }

            var.update $first_step {
              value = null
            }

            var.update $last_label {
              value = ""
            }

            foreach ($stage_list) {
              each as $sg {
                var $lookup {
                  value = $card.card_key ~ "::" ~ ($sg|get:"key":"")
                }

                var $step {
                  value = $step_index|get:$lookup:null
                }

                conditional {
                  if ($step != null) {
                    array.push $steps {
                      value = {
                        work_task_id    : $step.work_task_id
                        stage_key       : $step.stage_key
                        stage_label     : ($sg|get:"label":"")
                        status          : $step.status
                        task            : $step.task
                        done_when       : $step.done_when
                        expected_minutes: $step.expected_minutes
                        estimate_status : $step.estimate_status
                        estimate_source : $step.estimate_source
                      }
                    }

                    array.push $ids {
                      value = $step.work_task_id
                    }

                    var.update $minutes {
                      value = $minutes + ($step.expected_minutes ?? 0)
                    }

                    conditional {
                      if ($step.estimate_status == "incomplete") {
                        var.update $card_any_incomplete {
                          value = true
                        }
                      }
                    }

                    conditional {
                      if ($step.estimate_status != "n/a") {
                        var.update $card_any_estimated {
                          value = true
                        }
                      }
                    }

                    var.update $last_label {
                      value = ($sg|get:"label":"")
                    }
                  }
                }
              }
            }

            // |first on a plain (non-paged) list is confirmed working; the
            // result is hoisted into a var before any field is read, and
            // read with a literal-key |get so an empty card cannot crash
            // the whole backlog.
            var.update $first_step {
              value = $steps|first
            }

            var $card_estimate_status {
              value = "n/a"
            }

            conditional {
              if ($card_any_estimated == true) {
                var.update $card_estimate_status {
                  value = "complete"
                }

                conditional {
                  if ($card_any_incomplete == true) {
                    var.update $card_estimate_status {
                      value = "incomplete"
                    }
                  }
                }
              }
            }

            // EXC-1 (US-EXC-1-05) — the link both ways, on the card.
            var $card_job_key {
              value = $card.work_item_id|to_text
            }

            var $card_job {
              value = $job_by_id|get:$card_job_key:null
            }

            var $card_parent_id {
              value = $card_job.parent_work_item_id ?? 0
            }

            var $card_child_count {
              value = ($child_counts|get:$card_job_key:null) ?? 0
            }

            array.push $cards {
              value = {
                card_key         : $card.card_key
                work_item_id     : $card.work_item_id
                job_title        : $card.job_title
                lens_key         : $card.lens_key
                lens_label       : $lens_label
                step_count       : ($steps|count)
                expected_minutes : $minutes
                estimate_status  : $card_estimate_status
                first_stage_label: ($first_step|get:"stage_label":"")
                last_stage_label : $last_label
                work_task_ids    : $ids
                steps            : $steps
                parent_work_item_id: $card_parent_id
                child_count      : $card_child_count
              }
            }
          }
        }
      }
    }
  }

  response = {
    workspace_id: $input.workspace_id
    count       : ($cards|count)
    backlog     : $cards
  }
}
