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

    var $version_ids {
      value = []
    }

    var $key {
      value = ""
    }

    var $job_by_id {
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

        db.query journey_map_version {
          where = $db.journey_map_version.id in $version_ids
          return = {type: "list"}
        } as $versions

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
                expected_minutes: ($cell.duration_minutes ?? null)
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
                      }
                    }

                    array.push $ids {
                      value = $step.work_task_id
                    }

                    var.update $minutes {
                      value = $minutes + ($step.expected_minutes ?? 0)
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

            array.push $cards {
              value = {
                card_key         : $card.card_key
                work_item_id     : $card.work_item_id
                job_title        : $card.job_title
                lens_key         : $card.lens_key
                lens_label       : $lens_label
                step_count       : ($steps|count)
                expected_minutes : $minutes
                first_stage_label: ($first_step|get:"stage_label":"")
                last_stage_label : $last_label
                work_task_ids    : $ids
                steps            : $steps
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
