// BLK-1 (US-BLK-1-02, 2026-10-21) — Put a whole card onto a day.
//
// A CARD IS ONE JOB'S UNSCHEDULED STEPS FOR ONE ACTOR ROW. One
// `planner_task` is created and linked to every one of them, in the
// pinned version's stage order, with `position` 1..n. The link table
// has been many-to-one since SCHED-1 precisely so this needed no
// migration.
//
// WHY THE ACTOR ROW IS PART OF THE KEY. Checked live before building:
// 7 of 23 existing jobs have steps across two rows. Scheduling "the
// whole job" would put one role's work on another person's card.
//
// THE CALLER NAMES THE CARD; THE SERVER DERIVES THE STEPS. This is a
// deliberate improvement on the epic, which had the client send a
// list of step ids for the server to re-derive and compare. Taking
// `work_item_id` + `lens_key` instead removes that whole class of
// "the list was nearly right" failure: there is no list to be wrong,
// and no way to express a card spanning two jobs or two rows, so the
// epic's second refusal code was never needed.
//
// SCHEDULING ANY STEP TWICE IS IMPOSSIBLE, not merely checked:
// `planner_task_work_task.work_task_id` is unique. The check below
// turns that into a sentence instead of a database error, and the
// index is what makes it true under a race.
//
// ORDER COMES FROM THE SNAPSHOT'S `stages` ARRAY, walked in order.
// ORD-1 made stage order mutable, so a job pinned to v2 must use v2's
// order and not the live map's.
//
// Modelled on `work_task/{id}/schedule` (560), including its duration
// rule: a supplied duration is validated, and only an absent one
// falls back to the expected sum.
query "card/schedule" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
    text lens_key filters=trim
    int timeline_id filters=min:1
    int duration_minutes?
    int assignee_agent_id?
    text correlation_id? filters=trim
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

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $job.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "BLK-1"
        step       : "schedule_card"
        entity_type: "work_item"
        entity_id  : $input.work_item_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $tl_guard

    function.run "planner/assert_same_workspace" {
      input = {workspace_id_a: $job.workspace_id, workspace_id_b: $tl_guard.timeline.workspace_id}
    }

    conditional {
      if ($input.assignee_agent_id != 0) {
        function.run "planner/assert_agent" {
          input = {account_id: $actor.account_id, agent_id: $input.assignee_agent_id}
        } as $ag_guard

        function.run "planner/assert_same_workspace" {
          input = {workspace_id_a: $job.workspace_id, workspace_id_b: $ag_guard.agent.workspace_id}
        }
      }
    }

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    // Expected minutes for this row, keyed by stage.
    var $minutes_by_stage {
      value = {}
    }

    foreach ($version.snapshot.cells) {
      each as $c {
        conditional {
          if ($c.lens_key == $input.lens_key) {
            var.update $minutes_by_stage {
              value = $minutes_by_stage|set:$c.stage_key:($c.duration_minutes ?? 0)
            }
          }
        }
      }
    }

    // EST-1 (US-EST-1-05) — on a map WITH an Items row, every stage's
    // minutes are overridden to its real estimate (baseline only when
    // that stage has a missing rate). A map with no Items row keeps
    // the raw per-cell minutes above untouched.
    //
    // EST-1 Opus review fixes (2026-10-25), mirrored from 555/560: a
    // stage's estimate is only applied when THIS CARD's `lens_key` is
    // that stage's OWNER — on a two-actor map, the other row's card
    // at the same stage keeps the raw per-cell minutes already seeded
    // above, never this stage's combined total (double-counting
    // otherwise; the old version applied every stage's estimate here
    // regardless of which row owned it). And a stage also counts as
    // incomplete when the WHOLE job is incomplete for a reason that
    // isn't this stage's own (no lines at all), not only when this
    // stage's own `missing` is non-empty. Reads `$card_estimate.complete`
    // directly (not through a map), so `== false` is a plain, safe
    // comparison (unlike 559's job_complete map, which needs `|has`).
    function.run "estimate/estimate_job" {
      input = {work_item_id: $input.work_item_id}
    } as $card_estimate

    conditional {
      if ($card_estimate.has_items_row == true) {
        foreach ($card_estimate.stages) {
          each as $ce {
            conditional {
              if ($ce.owner_lens_key == $input.lens_key) {
                var $ce_incomplete {
                  value = (($ce.missing|count) > 0)
                }

                conditional {
                  if ($ce.scales_with != "per_order" && $card_estimate.complete == false) {
                    var.update $ce_incomplete {
                      value = true
                    }
                  }
                }

                var $ce_minutes {
                  value = $ce.baseline_minutes
                }

                conditional {
                  if ($ce_incomplete == false) {
                    var.update $ce_minutes {
                      value = $ce.total_minutes
                    }
                  }
                }

                var.update $minutes_by_stage {
                  value = $minutes_by_stage|set:$ce.stage_key:$ce_minutes
                }
              }
            }
          }
        }
      }
    }

    // This row's steps, indexed by stage key.
    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id && $db.work_task.lens_key == $input.lens_key
      return = {type: "list"}
    } as $row_tasks

    var $task_ids {
      value = [-1]
    }

    var $task_by_stage {
      value = {}
    }

    foreach ($row_tasks) {
      each as $t {
        array.push $task_ids {
          value = $t.id
        }

        var.update $task_by_stage {
          value = $task_by_stage|set:$t.stage_key:$t
        }
      }
    }

    // Which of them already hold a slot.
    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id in $task_ids
      return = {type: "count"}
    } as $already

    // Walk the version's stages IN ORDER and collect this row's steps.
    // The condition reads a `var` declared fresh inside the iteration —
    // the shape proven in functions/ops/group_issues.xs — never an outer
    // variable updated earlier in the same pass (CLAUDE.md).
    var $ordered_ids {
      value = []
    }

    var $expected {
      value = 0
    }

    foreach ($version.snapshot.stages) {
      each as $sg {
        var $stage_key {
          value = $sg|get:"key":""
        }

        var $hit {
          value = $task_by_stage|get:$stage_key:null
        }

        conditional {
          if ($hit != null) {
            array.push $ordered_ids {
              value = $hit.id
            }

            var $mins {
              value = $minutes_by_stage|get:$stage_key:0
            }

            var.update $expected {
              value = $expected + ($mins ?? 0)
            }
          }
        }
      }
    }

    var $step_count {
      value = $ordered_ids|count
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $caller_set_duration {
      value = $raw_input|has:"duration_minutes"
    }

    var $duration {
      value = $expected
    }

    conditional {
      if ($caller_set_duration == false && $expected < 1) {
        var.update $duration {
          value = 30
        }
      }
    }

    conditional {
      if ($caller_set_duration) {
        var.update $duration {
          value = $input.duration_minutes
        }
      }
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($step_count < 1) {
        var.update $reject_code {
          value = "E-BLK-001"
        }

        var.update $reject_msg {
          value = "That card has no steps waiting to be scheduled. Refresh and try again. (E-BLK-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $already > 0) {
        var.update $reject_code {
          value = "E-SCHED-001"
        }

        var.update $reject_msg {
          value = "Part of this card is already on the schedule, so none of it was added. Take it off the day first. (E-SCHED-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($duration < 1 || $duration > 1440)) {
        var.update $reject_code {
          value = "E-SCHED-002"
        }

        var.update $reject_msg {
          value = "Enter a duration between 1 and 1,440 minutes. (E-SCHED-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $job.status == "cancelled") {
        var.update $reject_code {
          value = "E-SCHED-008"
        }

        var.update $reject_msg {
          value = "That job is cancelled, so its steps can't be scheduled. (E-SCHED-008)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "BLK-1"
            step          : "schedule_card"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Card schedule refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.query planner_task {
      where = $db.planner_task.workspace_id == $job.workspace_id && $db.planner_task.timeline_id == $input.timeline_id
      return = {type: "count"}
    } as $existing_count

    var $append_seq {
      value = $existing_count + 1
    }

    // One slot, then one link per step, every write inside the
    // transaction. A half-written card would leave steps claimed by a
    // slot that does not cover them, and the unique index makes that
    // permanent until somebody unpicks it by hand.
    db.transaction {
      stack {
        db.add planner_task {
          data = {
            workspace_id     : $job.workspace_id
            timeline_id      : $input.timeline_id
            assignee_agent_id: $input.assignee_agent_id
            title            : ""
            seq              : $append_seq
            duration_minutes : $duration
            notes            : ""
            status           : "planned"
            needs_info_reason: ""
            tweak_reason     : ""
          }
        } as $slot

        var $pos {
          value = 0
        }

        foreach ($ordered_ids) {
          each as $wtid {
            var.update $pos {
              value = $pos + 1
            }

            db.add planner_task_work_task {
              data = {planner_task_id: $slot.id, work_task_id: $wtid, position: $pos}
            } as $link
          }
        }
      }
    }

    function.run "planner/resequence" {
      input = {workspace_id: $job.workspace_id, timeline_id: $input.timeline_id}
    } as $reseq

    function.run "ops/log_event" {
      input = {
        feature       : "BLK-1"
        step          : "schedule_card"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $slot.id
        correlation_id: $input.correlation_id
        message       : "Card scheduled."
        metadata      : {
          work_item_id     : $input.work_item_id
          lens_key         : $input.lens_key
          timeline_id      : $input.timeline_id
          step_count       : $step_count
          expected_minutes : $expected
          scheduled_minutes: $duration
        }
      }
    }
  }

  response = {
    planner_task     : $slot
    work_item_id     : $input.work_item_id
    lens_key         : $input.lens_key
    work_task_ids    : $ordered_ids
    step_count       : $step_count
    expected_minutes : $expected
    scheduled_minutes: $duration
    is_tweaked       : ($duration != $expected)
  }
}
