// REPEAT-1 stories 01 + 07 — THE one assembly of "what would repeating this plan do": the same answer the screen's preview shows and the AI's plan_repeat tool returns, so neither can drift from the other. Read-only: it writes nothing. It runs repeat/build_plan (jobs, people, days, dates, name) and, when the date is accepted, repeat/plan_work (lines, windows, slots, the backlog and what is not created), then lays the counts out. A refused date (E-REPEAT-002 or E-REPEAT-003) comes back as reject_code / reject_msg with empty counts, not thrown, so each caller can log the refusal its own way. Tenancy is planner/assert_workspace inside build_plan (another account's plan is "not found"). Every input is passed to function.run explicitly. A bare number inside a multi-line object literal turns into null (CLAUDE.md), so every number below is taken from a variable.
function "repeat/preview" {
  input {
    int account_id
    int workspace_id
    text start_date? filters=trim
    int[] skip_job_ids?

    // REPEAT-2: what the planner chose NOT to carry. Omitted = false = copy.
    bool skip_people?
    bool skip_jobs?
    bool skip_assignments?
  }

  stack {
    function.run "repeat/build_plan" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id, start_date: $input.start_date, skip_job_ids: $input.skip_job_ids, skip_people: $input.skip_people, skip_jobs: $input.skip_jobs, skip_assignments: $input.skip_assignments}
    } as $plan

    var $counts {
      value = {}
    }

    var $people {
      value = []
    }

    var $step_changes {
      value = []
    }

    var $left_out {
      value = []
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

    conditional {
      if ($plan.reject_code == "") {
        function.run "repeat/plan_work" {
          input = {account_id: $input.account_id, workspace_id: $input.workspace_id, plan: $plan, shift_days: $plan.offer.shift_days, source_name: $plan.source.name}
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

        var.update $counts {
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

        var.update $step_changes {
          value = $work.step_changes
        }

        var.update $left_out {
          value = $work.left_out
        }
      }
    }
  }

  response = {
    reject_code : $plan.reject_code
    reject_msg  : $plan.reject_msg
    source      : $plan.source
    offer       : $plan.offer
    counts      : $counts
    people      : $people
    jobs        : $plan.jobs
    step_changes: $step_changes
    left_out    : $left_out
    choices     : $plan.choices
  }
}
