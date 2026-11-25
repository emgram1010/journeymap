// REPEAT-1 story 01 — Preview a repeat. Returns what repeating this plan would copy and what it would leave out, and writes nothing to the plan. It is a POST only because it takes a list (the jobs the planner unticked); it is a read. The answer comes from the SAME two functions the real copy executes: repeat/build_plan (jobs, people, days) and repeat/plan_work (lines, windows, slots, the backlog and what is not created), so the preview and the copy cannot disagree (Opus review 2026-11-25: the slot counts used to come from build_plan alone, which missed a slot given to a left-off person and a step the new version dropped). Another account's plan is "not found" (planner/assert_workspace, inside build_plan). A bad start date (E-REPEAT-002) or a window that overlaps the source (E-REPEAT-003) is refused with a plain message, and the refusal is logged as plan.repeat_preview / rejected. A successful preview logs nothing: it is a read. Every input is passed to function.run explicitly, because an omitted one silently inherits this endpoint's input of the same name.
query "workspace/{workspace_id}/repeat-preview" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text start_date? filters=trim
    int[] skip_job_ids?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "repeat/build_plan" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id, start_date: $input.start_date, skip_job_ids: $input.skip_job_ids}
    } as $plan

    conditional {
      if ($plan.reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature    : "REPEAT-1"
            step       : "plan.repeat_preview"
            outcome    : "rejected"
            severity   : "info"
            error_code : $plan.reject_code
            message    : $plan.reject_msg
            user_id    : $actor.user_id
            account_id : $actor.account_id
            entity_type: "planner_workspace"
            entity_id  : $input.workspace_id
            metadata   : {start_date: $input.start_date}
          }
        } as $_logged
      }
    }

    precondition ($plan.reject_code == "") {
      error_type = "inputerror"
      error = $plan.reject_msg
    }

    function.run "repeat/plan_work" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id, plan: $plan, shift_days: $plan.offer.shift_days, source_name: $plan.source.name}
    } as $work

    var $c {
      value = $plan.counts
    }

    var $sc {
      value = $work.slot_counts
    }

    var $jc {
      value = $work.job_counts
    }

    var $backlog_own {
      value = $sc.backlog - $sc.to_backlog
    }

    var $rows {
      value = 1 + $c.people + $c.days + $jc.repeated + $c.steps + $jc.lines + $jc.windows + (($sc.placed + $sc.backlog) * 3)
    }

    var $counts {
      value = {
        people          : $c.people
        people_left_off : $c.people_left_off
        days            : $c.days
        jobs            : $c.jobs
        jobs_left_out   : $c.jobs_left_out
        jobs_will_not   : $c.jobs_will_not
        jobs_cannot     : $c.jobs_cannot
        jobs_newer      : $c.jobs_newer
        steps           : $c.steps
        slots           : $sc.placed
        slots_to_backlog: $sc.to_backlog
        backlog         : $backlog_own
        slots_dropped   : $sc.not_created
        new_steps       : $sc.new_steps
        lengths_reset   : $sc.lengths_reset
        start_times     : $sc.start_times
        lines           : $jc.lines
        lines_left_out  : $jc.lines_left
        windows         : $jc.windows
        row_estimate    : $rows
      }
    }

    var $t {
      value = ""
    }

    var $k {
      value = ""
    }

    var $n {
      value = 0
    }

    var $people {
      value = []
    }

    foreach ($plan.people) {
      each as $p {
        var.update $t {
          value = $p.agent_id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $n {
          value = ($work.to_backlog_by_agent|get:$k:null) ?? 0
        }

        array.push $people {
          value = {agent_id: $p.agent_id, name: $p.name, kind: $p.kind, left_off: $p.left_off, slots_to_backlog: $n}
        }
      }
    }
  }

  response = {
    source      : $plan.source
    offer       : $plan.offer
    counts      : $counts
    people      : $people
    jobs        : $plan.jobs
    step_changes: $work.step_changes
    left_out    : $work.left_out
  }
}
