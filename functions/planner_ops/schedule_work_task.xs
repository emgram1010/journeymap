// COP-5 story 01 (extraction) — THE ONE PLACE a job step is put onto a
// day: SCHED-1's rule (US-SCHED-1-03), moved out of endpoint 560
// (`POST work_task/{work_task_id}/schedule`) so the copilot's
// `plan_schedule_step` tool schedules a step through exactly the same
// checks, writes and logging as a person's click. A copy would drift.
//
// Everything 560's header says still holds here: it creates a
// `planner_task` slot on the timeline and links it to the work task; the
// slot carries NO title (reference, do not copy); the default duration is
// the step's EXPECTED minutes from the pinned version (EST-1's stage
// estimate on a map with an Items row, for the stage's owner only); a
// SUPPLIED duration is validated 1..1440 and only an ABSENT one falls
// back (to expected, and to 30 only when there is no estimate at all);
// scheduling the same step twice is refused (E-SCHED-001) and the unique
// index is what makes that true under a race; a cancelled job's steps
// are refused (E-SCHED-008). Undoing this is `DELETE work_task/{id}/schedule`.
//
// `actor` is planner/resolve_actor's result: {user_id, account_id, role}.
// A function cannot see what the caller sent, so "was a duration sent?"
// is the explicit flag `has_duration_minutes` (false = use the fallback;
// true = take `duration_minutes` as given and validate it, so an explicit
// 0 is still refused). `assignee_agent_id` 0 = the day's own person, as in 560.
//
// 4-C (2026-11-17): endpoint 560 now calls this function (replay
// c4_560_replay.py, identical before vs after), and two of its bugs are
// fixed here, once for both callers: a missing pinned version is a logged
// failure and a coded refusal (E-SCHED-012), not a raw 500; and the loser
// of two identical requests at the same moment gets E-SCHED-001, logged,
// not a raw "Duplicate record" 500 (any other failed insert: E-SCHED-013).
// NOT changed: with no duration sent, an expected time over 1,440 minutes
// is still refused as E-SCHED-002 - no map anywhere has such a step to
// prove a fix on.
function "planner_ops/schedule_work_task" {
  input {
    json actor
    int work_task_id filters=min:1
    int timeline_id filters=min:1
    int duration_minutes?
    bool has_duration_minutes?
    int assignee_agent_id?
    text correlation_id? filters=trim
  }

  stack {
    var $actor {
      value = $input.actor
    }

    db.get work_task {
      field_name = "id"
      field_value = $input.work_task_id
    } as $wt

    precondition ($wt != null) {
      error_type = "notfound"
      error = "Step not found"
    }

    db.get work_item {
      field_name = "id"
      field_value = $wt.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Step not found"
    }

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $job.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "SCHED-1"
        step       : "schedule_block"
        entity_type: "work_task"
        entity_id  : $input.work_task_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    // The destination day must belong to the same plan as the job.
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

    // Handoff 4-A rule 2 (COP-5 story 06): the slot lands on the assignee override when one is
    // given, else on the day's own person - refused for a switched-off copilot's column (E-COP-059).
    var $target_agent_id {
      value = (($input.assignee_agent_id != 0) ? $input.assignee_agent_id : $tl_guard.timeline.agent_id)
    }

    function.run "planner_ops/assert_agent_assignable" {
      input = {agent_id: $target_agent_id, actor_user_id: $actor.user_id, account_id: $actor.account_id, step: "schedule_step"}
    } as $_assignable

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id == $input.work_task_id
      return = {type: "count"}
    } as $already

    // Expected minutes come from the job's pinned version.
    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    // 4-C (endpoint 560 moved onto this function): a job whose pinned
    // version row is missing used to crash here with a raw 500 ("Unable to
    // locate var: version.snapshot.cells") and no event. It is a data
    // fault, not the planner's mistake: logged as a failure for support
    // and refused with its own code. Nothing is written.
    conditional {
      if ($version == null) {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-1"
            step          : "schedule_block"
            outcome       : "failure"
            severity      : "error"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : "E-SCHED-012"
            message       : "Schedule refused: the job's pinned map version was not found."
            metadata      : {work_item_id: $job.id, journey_map_version_id: $job.journey_map_version_id}
          }
        }
      }
    }

    precondition ($version != null) {
      error_type = "inputerror"
      error = "This job's map version can't be found, so its steps can't be scheduled. Nothing was changed. (E-SCHED-012)"
    }

    var $expected {
      value = 0
    }

    foreach ($version.snapshot.cells) {
      each as $c {
        conditional {
          if ($c.stage_key == $wt.stage_key && $c.lens_key == $wt.lens_key) {
            var.update $expected {
              value = ($c.duration_minutes ?? 0)
            }
          }
        }
      }
    }

    // EST-1 (US-EST-1-05) — on a map WITH an Items row, the step's
    // real expected minutes are its stage's estimate (baseline only
    // when that stage has a missing rate), not the raw cell scan
    // above. A map with no Items row keeps the scan untouched.
    //
    // EST-1 Opus review fixes (2026-10-25), mirrored from 555: the
    // override only applies when $wt's own lens_key is the stage's
    // OWNER — a second actor at the same stage keeps the raw cell
    // scan's number, never the combined stage total (double-counting
    // otherwise). And the stage also counts as incomplete when the
    // WHOLE job is incomplete for a reason that isn't this stage's
    // own (no lines at all), not only when this stage's own `missing`
    // is non-empty. Reads `$step_estimate.complete` directly (not
    // through a map), so `== false` is a plain, safe comparison — no
    // `|has`/null-check needed here (unlike 559's job_complete map).
    function.run "estimate/estimate_job" {
      input = {work_item_id: $job.id}
    } as $step_estimate

    conditional {
      if ($step_estimate.has_items_row == true) {
        foreach ($step_estimate.stages) {
          each as $se {
            conditional {
              if ($se.stage_key == $wt.stage_key && $se.owner_lens_key == $wt.lens_key) {
                var $se_incomplete {
                  value = (($se.missing|count) > 0)
                }

                conditional {
                  if ($se.scales_with != "per_order" && $step_estimate.complete == false) {
                    var.update $se_incomplete {
                      value = true
                    }
                  }
                }

                conditional {
                  if ($se_incomplete == true) {
                    var.update $expected {
                      value = $se.baseline_minutes
                    }
                  }

                  else {
                    var.update $expected {
                      value = $se.total_minutes
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    var $caller_set_duration {
      value = ($input.has_duration_minutes == true)
    }

    // Absent: fall back to expected, and to 30 only when the version
    // has no estimate at all. Supplied: take it as given and let the
    // validation below judge it.
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
      if ($already > 0) {
        var.update $reject_code {
          value = "E-SCHED-001"
        }

        var.update $reject_msg {
          value = "This step is already on the schedule. (E-SCHED-001)"
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
            feature       : "SCHED-1"
            step          : "schedule_block"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Schedule refused."
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

    // 4-C (endpoint 560 moved onto this function): two identical requests
    // at the same moment both pass the E-SCHED-001 count above; the unique
    // index on planner_task_work_task.work_task_id then stops the second
    // link, the transaction rolls its slot back, and the caller used to get
    // a raw 500 ("Duplicate record detected") with no event. Now the failed
    // insert is caught and the links are re-counted: if the step IS on the
    // schedule (someone else won), the answer is the same E-SCHED-001
    // refusal, logged; if it is not, the failure is logged and refused
    // (E-SCHED-013). Either way nothing half-written survives.
    var $slot {
      value = null
    }

    var $tx_failed {
      value = false
    }

    try_catch {
      try {
        group {
          stack {
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
                } as $new_slot

                db.add planner_task_work_task {
                  data = {planner_task_id: $new_slot.id, work_task_id: $input.work_task_id, position: 1}
                } as $link
              }
            }

            var.update $slot {
              value = $new_slot
            }
          }
        }
      }

      catch {
        var.update $tx_failed {
          value = true
        }
      }
    }

    var $lost_race {
      value = false
    }

    conditional {
      if ($tx_failed == true) {
        db.query planner_task_work_task {
          where = $db.planner_task_work_task.work_task_id == $input.work_task_id
          return = {type: "count"}
        } as $already_after

        var.update $lost_race {
          value = ($already_after > 0)
        }
      }
    }

    conditional {
      if ($tx_failed == true && $lost_race == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-1"
            step          : "schedule_block"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : "E-SCHED-001"
            message       : "Schedule refused."
            metadata      : {lost_race: true}
          }
        }
      }
    }

    conditional {
      if ($tx_failed == true && $lost_race == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-1"
            step          : "schedule_block"
            outcome       : "failure"
            severity      : "error"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : "E-SCHED-013"
            message       : "Schedule failed while writing; nothing was saved."
            metadata      : {timeline_id: $input.timeline_id}
          }
        }
      }
    }

    precondition ($lost_race == false) {
      error_type = "inputerror"
      error = "This step is already on the schedule. (E-SCHED-001)"
    }

    precondition ($tx_failed == false) {
      error_type = "inputerror"
      error = "The step couldn't be scheduled, and nothing was saved. Try again. (E-SCHED-013)"
    }

    function.run "planner/resequence" {
      input = {workspace_id: $job.workspace_id, timeline_id: $input.timeline_id}
    } as $reseq

    function.run "ops/log_event" {
      input = {
        feature       : "SCHED-1"
        step          : "schedule_block"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $slot.id
        correlation_id: $input.correlation_id
        message       : "Job step scheduled."
        metadata      : {
          work_task_id     : $input.work_task_id
          work_item_id     : $job.id
          timeline_id      : $input.timeline_id
          expected_minutes : $expected
          scheduled_minutes: $duration
        }
      }
    }
  }

  response = {
    planner_task     : $slot
    work_task_id     : $input.work_task_id
    expected_minutes : $expected
    scheduled_minutes: $duration
    is_tweaked       : ($duration != $expected)
  }
}
