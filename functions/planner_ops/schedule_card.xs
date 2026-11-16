// COP-5 story 01 (handoff 4-B) — THE ONE PLACE a whole card (one job's
// unscheduled steps for one actor row) is put onto a day: BLK-1's rule
// (US-BLK-1-02), copied from live endpoint 583 (`POST card/schedule`) so the
// copilot's `plan_schedule_card` tool schedules a card through exactly the
// same checks, writes and logging as a person's click. Until 583 is switched
// onto this function (handoff 4-C, not approved), the rule exists twice.
//
// Everything 583's header says holds here: one planner_task linked to every
// step of the row, in the PINNED version's stage order, position 1..n; the
// unique index on planner_task_work_task.work_task_id makes double
// scheduling impossible (E-SCHED-001 turns it into a sentence); E-BLK-001 no
// steps; E-SCHED-002 duration 1..1440; E-SCHED-008 cancelled job; the slot's
// column is refused when it is a switched-off copilot's (E-COP-059, via
// planner_ops/assert_agent_assignable).
//
// `actor` is planner/resolve_actor's result: {user_id, account_id, role}.
// A function cannot see what the caller sent, so "was a duration sent?" is
// the explicit flag `has_duration_minutes` (false = expected sum, 30 when
// there is no estimate; true = take `duration_minutes` and validate it).
// `assignee_agent_id` 0 = the day's own person, as in 583.
function "planner_ops/schedule_card" {
  input {
    json actor
    int work_item_id filters=min:1
    text lens_key filters=trim
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

    // Handoff 4-A rule 2 (COP-5 story 06): the slot lands on the assignee override when one is
    // given, else on the day's own person - refused for a switched-off copilot's column (E-COP-059).
    var $target_agent_id {
      value = (($input.assignee_agent_id != 0) ? $input.assignee_agent_id : $tl_guard.timeline.agent_id)
    }

    function.run "planner_ops/assert_agent_assignable" {
      input = {agent_id: $target_agent_id, actor_user_id: $actor.user_id, account_id: $actor.account_id, step: "schedule_card"}
    } as $_assignable

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

    // EST-1 (US-EST-1-05) - on a map WITH an Items row, a stage's minutes are its real estimate
    // (baseline only when that stage is incomplete), and only when THIS card's lens_key owns the
    // stage. Same rule as 583/560.
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

    // Walk the version's stages IN ORDER and collect this row's steps. The condition reads a var
    // declared fresh inside the iteration (functions/ops/group_issues.xs shape).
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

    var $caller_set_duration {
      value = ($input.has_duration_minutes == true)
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

    // One slot, then one link per step, every write inside the transaction.
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
