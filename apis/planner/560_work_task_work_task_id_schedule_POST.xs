// SCHED-1 (US-SCHED-1-03) — Put a job step onto a day.
//
// Creates a `planner_task` slot on the timeline and links it to the
// work task. The default duration is the step's EXPECTED minutes from
// the pinned version, so scheduling something changes nothing about
// what was agreed — it just makes room for it.
//
// THE SLOT CARRIES NO TITLE. `planner_task.title` is left empty for a
// linked slot on purpose: the real title lives in the job's pinned
// version and is read through the link. Copying it here would create
// a second copy that drifts the moment anything is republished, and
// "reference, do not copy" is an architecture rule, not a preference.
// ⚠️ Known gap: PLN-7's task list does not yet hydrate linked slots,
// so a scheduled job step currently reads with a blank title there.
// That hydration belongs with the planner UI work (PLN-9).
//
// ⚠️ A SUPPLIED DURATION IS VALIDATED; ONLY AN ABSENT ONE FALLS BACK.
// The first version of this endpoint clamped anything under a minute
// up to 30 before validating, which meant an explicit
// `duration_minutes: 0` was silently accepted as 30 instead of being
// refused — exactly the "junk quietly becomes a plausible value"
// failure VAL-1 exists to prevent. The 30-minute fallback now applies
// ONLY when the caller sent nothing and the version has no estimate
// for the step; anything sent by the caller is held to 1..1440.
//
// SCHEDULING THE SAME STEP TWICE IS IMPOSSIBLE, not merely checked:
// `planner_task_work_task.work_task_id` is unique. The check below
// exists to turn that into a sentence instead of a database error,
// and the index is what makes it true under a race.
query "work_task/{work_task_id}/schedule" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_task_id filters=min:1
    int timeline_id filters=min:1
    int duration_minutes?
    int assignee_agent_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

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

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id == $input.work_task_id
      return = {type: "count"}
    } as $already

    // Expected minutes come from the job's pinned version.
    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

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

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $caller_set_duration {
      value = $raw_input|has:"duration_minutes"
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
          value = "E-SCHED-001"
        }

        var.update $reject_msg {
          value = "That job is cancelled, so its steps can't be scheduled. (E-SCHED-001)"
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

        db.add planner_task_work_task {
          data = {planner_task_id: $slot.id, work_task_id: $input.work_task_id, position: 1}
        } as $link
      }
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
