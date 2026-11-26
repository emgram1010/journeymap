// REPEAT-1 story 02 — Make the new plan from a repeat: the plan itself, its accepted maps, its people and their days, moved forward. Stories 03-04 add the jobs and slots to the SAME write: repeat/plan_work decides every row first (read-only), jobs/create_job writes each job, and every slot lands on its matching day and position. What to copy is decided by repeat/build_plan (the rule the preview shows), never re-decided here. One all-or-nothing db.transaction (story 00: 550 rows in 5.9 s), so the plan_repeat row is written straight as `ready` and a half-built plan is never visible. THE RACE GUARD is plan_repeat's unique index on (source plan, start date), plus planner_workspace's unique (account, name): two confirms at once both reach the insert, the database refuses the second, its whole transaction rolls back, and the loser is answered with the winner's plan (outcome "exists", E-REPEAT-005). A "does it exist?" read is only the fast path for a second click (EXC-1). A person who is switched off (inactive, or their login is off) is not added and is named with the reason. A map the source accepts that is now archived, deleted or another account's is not copied and is named. Days keep their start time, move by shift_days, and are always draft. The source plan is only read. test_fail_at = 1 throws inside the transaction after every row is written, to prove nothing is left behind; the endpoint always passes 0.
function "repeat/create_plan" {
  input {
    int account_id
    int user_id
    int workspace_id
    text start_date? filters=trim
    text name? filters=trim
    int[] skip_job_ids?
    text correlation_id? filters=trim
    int test_fail_at?

    // REPEAT-2: what the planner chose NOT to carry. Omitted = false = copy (see repeat/build_plan).
    bool skip_people?
    bool skip_jobs?
    bool skip_assignments?
  }

  stack {
    function.run "repeat/build_plan" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id, start_date: $input.start_date, skip_job_ids: $input.skip_job_ids, skip_people: $input.skip_people, skip_jobs: $input.skip_jobs, skip_assignments: $input.skip_assignments}
    } as $plan

    // REPEAT-2: the choices as build_plan settled them (people off forces assignments off). Set once, before every loop.
    var $no_people {
      value = ($plan.choices.skip_people == true)
    }

    var $no_jobs {
      value = ($plan.choices.skip_jobs == true)
    }

    var $no_days {
      value = ($plan.choices.skip_assignments == true)
    }

    var $np {
      value = $no_people|to_int
    }

    var $reject_code {
      value = $plan.reject_code
    }

    var $reject_msg {
      value = $plan.reject_msg
    }

    // A real copy never guesses its start date: an empty one is refused, not defaulted.
    conditional {
      if ($reject_code == "" && $input.start_date == "") {
        var.update $reject_code {
          value = "E-REPEAT-002"
        }

        var.update $reject_msg {
          value = "Pick a start date for the new plan. (E-REPEAT-002)"
        }
      }
    }

    var $name_len {
      value = $input.name|strlen
    }

    conditional {
      if ($reject_code == "" && ($name_len == 0 || $name_len > 80)) {
        var.update $reject_code {
          value = "E-REPEAT-004"
        }

        var.update $reject_msg {
          value = "Give the new plan a name (up to 80 characters). (E-REPEAT-004)"
        }
      }
    }

    // Fast path for a second click: this source has already been repeated to this date.
    var $existing_id {
      value = 0
    }

    conditional {
      if ($reject_code == "") {
        db.query plan_repeat {
          where = $db.plan_repeat.source_workspace_id == $input.workspace_id && $db.plan_repeat.new_start_date == $input.start_date
          return = {type: "single"}
        } as $existing

        var.update $existing_id {
          value = $existing|get:"new_workspace_id":0
        }
      }
    }

    conditional {
      if ($reject_code == "" && $existing_id == 0) {
        db.query planner_workspace {
          where = $db.planner_workspace.account_id == $input.account_id && $db.planner_workspace.name == $input.name
          return = {type: "list"}
          output = ["id"]
        } as $name_rows

        var $name_clash {
          value = $name_rows|count
        }

        conditional {
          if ($name_clash > 0) {
            var.update $reject_code {
              value = "E-PLN-001"
            }

            var.update $reject_msg {
              value = "You already have a plan with this name. (E-PLN-001)"
            }
          }
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat"
            outcome       : "rejected"
            severity      : "info"
            error_code    : $reject_code
            message       : $reject_msg
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            metadata      : {start_date: $input.start_date, name: $input.name}
          }
        } as $_logged_reject
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // ── What to write (read-only; the source is never written) ─────
    db.query planner_workspace {
      where = $db.planner_workspace.id == $input.workspace_id
      return = {type: "single"}
    } as $src

    var $shift_ms {
      value = $plan.offer.shift_days * 86400000
    }

    var $t {
      value = ""
    }

    var $k {
      value = ""
    }

    // A bare number inside a multi-line object literal becomes null and swallows the next key (found live 2026-11-25).
    var $zero {
      value = 0
    }

    // People: the left-off verdict comes from build_plan, so the copy matches the preview.
    var $off_map {
      value = {}
    }

    var $off_n {
      value = 0
    }

    foreach ($plan.people) {
      each as $p {
        var.update $t {
          value = $p.agent_id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $off_n {
          value = $p.left_off|to_int
        }

        var.update $off_map {
          value = $off_map|set:$k:$off_n
        }
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
      sort = {planner_agent.id: "asc"}
    } as $agents

    var $agent_checks {
      value = []
    }

    var $reason {
      value = ""
    }

    foreach ($agents) {
      each as $a {
        var.update $t {
          value = $a.id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $off_n {
          value = ($off_map|get:$k:null) ?? 0
        }

        var.update $reason {
          value = (($a.is_active == false) ? "inactive" : "login_off")
        }

        array.push $agent_checks {
          value = {agent: $a, off: $off_n, reason: $reason}
        }
      }
    }

    var $agents_copy {
      value = []
    }

    var $left_out {
      value = []
    }

    foreach ($agent_checks) {
      each as $c {
        conditional {
          if ($c.off == 0) {
            array.push $agents_copy {
              value = $c.agent
            }
          }
        }

        // A person left off by the planner's own choice is not "left out": nothing is named.
        conditional {
          if ($c.off == 1 && $no_people == false) {
            array.push $left_out {
              value = {kind: "person", id: $c.agent.id, name: $c.agent.name, reason: $c.reason}
            }
          }
        }
      }
    }

    // Accepted maps: read from the SOURCE PLAN, never its template.
    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["journey_map_id"]
    } as $src_maps

    var $src_map_ids {
      value = [-1]
    }

    foreach ($src_maps) {
      each as $sm {
        array.push $src_map_ids {
          value = $sm.journey_map_id
        }
      }
    }

    function.run "journey/deleted_map_ids" {
      input = {}
    } as $deleted

    var $deleted_ids {
      value = [-1]
    }

    foreach ($deleted.ids) {
      each as $d {
        array.push $deleted_ids {
          value = $d
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $src_map_ids && $db.journey_map.account_id == $input.account_id && $db.journey_map.status != "archived" && ($db.journey_map.id not in $deleted_ids)
      return = {type: "list"}
      output = ["id"]
    } as $usable_maps

    db.query journey_map {
      where = $db.journey_map.id in $src_map_ids
      return = {type: "list"}
      output = ["id", "title"]
    } as $named_maps

    var $map_ok {
      value = {}
    }

    var $map_name {
      value = {}
    }

    foreach ($usable_maps) {
      each as $m {
        var.update $t {
          value = $m.id|to_text
        }

        var.update $k {
          value = "m:" ~ $t
        }

        var.update $map_ok {
          value = $map_ok|set:$k:1
        }
      }
    }

    foreach ($named_maps) {
      each as $m {
        var.update $t {
          value = $m.id|to_text
        }

        var.update $k {
          value = "m:" ~ $t
        }

        var.update $map_name {
          value = $map_name|set:$k:$m.title
        }
      }
    }

    var $map_checks {
      value = []
    }

    var $ok_n {
      value = 0
    }

    var $m_title {
      value = ""
    }

    foreach ($src_maps) {
      each as $sm {
        var.update $t {
          value = $sm.journey_map_id|to_text
        }

        var.update $k {
          value = "m:" ~ $t
        }

        var.update $ok_n {
          value = ($map_ok|get:$k:null) ?? 0
        }

        var.update $m_title {
          value = ($map_name|get:$k:null) ?? ""
        }

        array.push $map_checks {
          value = {journey_map_id: $sm.journey_map_id, ok: $ok_n, title: $m_title}
        }
      }
    }

    var $maps_copy {
      value = []
    }

    foreach ($map_checks) {
      each as $mc {
        conditional {
          if ($mc.ok == 1) {
            array.push $maps_copy {
              value = $mc.journey_map_id
            }
          }
        }

        conditional {
          if ($mc.ok == 0) {
            array.push $left_out {
              value = {kind: "map", id: $mc.journey_map_id, name: $mc.title, reason: "map_unavailable"}
            }
          }
        }
      }
    }

    // Days: the same person, the date moved by shift_days, the start time kept, always draft.
    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
      sort = {planner_timeline.planned_date: "asc"}
    } as $timelines

    var $tl_checks {
      value = []
    }

    var $d_ms {
      value = 0
    }

    var $new_date {
      value = ""
    }

    foreach ($timelines) {
      each as $tl {
        var.update $t {
          value = ($tl.agent_id ?? 0)|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        // An agent missing from the map (a day whose person is not on this plan) counts as left off.
        var.update $off_n {
          value = ($off_map|get:$k:null) ?? 1
        }

        var.update $d_ms {
          value = ($tl.planned_date|to_timestamp) + $shift_ms
        }

        var.update $new_date {
          value = $d_ms|format_timestamp:"Y-m-d":"UTC"
        }

        array.push $tl_checks {
          value = {src_id: $tl.id, agent_id: $tl.agent_id, off: $off_n, new_date: $new_date, start_time: $tl.start_time}
        }
      }
    }

    var $days_copy {
      value = []
    }

    foreach ($tl_checks) {
      each as $tc {
        conditional {
          if ($tc.off == 0) {
            array.push $days_copy {
              value = $tc
            }
          }
        }
      }
    }

    // REPEAT-2: no assignments means no days.
    conditional {
      if ($no_days == true) {
        var.update $days_copy {
          value = []
        }
      }
    }

    // Stories 03-04: jobs, lines, windows and slots, all decided before the write (read-only).
    function.run "repeat/plan_work" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id, plan: $plan, shift_days: $plan.offer.shift_days, source_name: $src.name}
    } as $work

    foreach ($work.left_out) {
      each as $wl {
        array.push $left_out {
          value = $wl
        }
      }
    }

    var $job_counts {
      value = $work.job_counts
    }

    var $slot_counts {
      value = $work.slot_counts
    }

    var $counts {
      value = {
        people         : ($agents_copy|count)
        people_left_off: ((($agent_checks|count) - ($agents_copy|count)) * (1 - $np))
        days           : ($days_copy|count)
        maps           : ($maps_copy|count)
        maps_left_out  : (($map_checks|count) - ($maps_copy|count))
        jobs           : $job_counts
        slots          : $slot_counts
        choices        : $plan.choices
      }
    }

    // Health rule (story 04): more slots sent to the backlog than placed is a warning.
    var $mostly_backlog {
      value = ($slot_counts.to_backlog > $slot_counts.placed)
    }

    var $sched_severity {
      value = (($mostly_backlog == true) ? "warn" : "info")
    }

    var $sched_message {
      value = (($mostly_backlog == true) ? "Plan repeated, but more of its slots went to the backlog than onto days." : "Slots carried over to the new plan.")
    }

    // ── The write: all of it, or none of it ─────────────────────────
    var $new_ws_id {
      value = 0
    }

    var $write_ok {
      value = false
    }

    var $fail_msg {
      value = ""
    }

    var $started {
      value = now|to_int
    }

    conditional {
      if ($existing_id == 0) {
        try_catch {
          try {
            group {
              stack {
                db.transaction {
                  stack {
                    db.add planner_workspace {
                      data = {
                        account_id              : $input.account_id
                        created_by              : $input.user_id
                        name                    : $input.name
                        planning_window_start   : $plan.offer.start_date
                        planning_window_end     : $plan.offer.end_date
                        input_tokens_per_minute : $src.input_tokens_per_minute
                        output_tokens_per_minute: $src.output_tokens_per_minute
                        is_archived             : false
                        plan_template_id        : $src.plan_template_id
                      }
                    } as $new_ws

                    var.update $new_ws_id {
                      value = $new_ws.id
                    }

                    foreach ($maps_copy) {
                      each as $mid {
                        db.add planner_workspace_map {
                          data = {workspace_id: $new_ws.id, journey_map_id: $mid}
                        } as $_map_row
                      }
                    }

                    var $new_agent {
                      value = {}
                    }

                    foreach ($agents_copy) {
                      each as $ag {
                        db.add planner_agent {
                          data = {
                            workspace_id        : $new_ws.id
                            name                : $ag.name
                            kind                : $ag.kind
                            color               : $ag.color
                            daily_capacity_hours: $ag.daily_capacity_hours
                            is_visible          : $ag.is_visible
                            model_id            : $ag.model_id
                            user_id             : $ag.user_id
                            is_active           : true
                          }
                        } as $na

                        // REQ-1 story 03: the copy carries the link its source person had.
                        function.run "req/copy_person_link" {
                          input = {account_id: $input.account_id, from_agent_id: $ag.id, to_agent_id: $na.id, user_id: $input.user_id}
                        } as $_link_copied

                        var.update $t {
                          value = $ag.id|to_text
                        }

                        var.update $k {
                          value = "a:" ~ $t
                        }

                        var.update $new_agent {
                          value = $new_agent|set:$k:$na.id
                        }
                      }
                    }

                    var $new_aid {
                      value = 0
                    }

                    var $new_tl {
                      value = {}
                    }

                    foreach ($days_copy) {
                      each as $dc {
                        var.update $t {
                          value = $dc.agent_id|to_text
                        }

                        var.update $k {
                          value = "a:" ~ $t
                        }

                        var.update $new_aid {
                          value = ($new_agent|get:$k:null) ?? 0
                        }

                        db.add planner_timeline {
                          data = {
                            workspace_id: $new_ws.id
                            agent_id    : $new_aid
                            planned_date: $dc.new_date
                            start_time  : $dc.start_time
                            status      : "draft"
                          }
                        } as $day_row

                        var.update $t {
                          value = $dc.src_id|to_text
                        }

                        var.update $k {
                          value = "t:" ~ $t
                        }

                        var.update $new_tl {
                          value = $new_tl|set:$k:$day_row.id
                        }
                      }
                    }

                    // Story 03: each job made through the one job writer, pinned to its current version.
                    var $step_new {
                      value = {}
                    }

                    var $jt {
                      value = ""
                    }

                    var $sk {
                      value = ""
                    }

                    foreach ($work.jobs_make) {
                      each as $jm {
                        function.run "jobs/create_job" {
                          input = {
                            account_id            : $input.account_id
                            workspace_id          : $new_ws.id
                            journey_map_version_id: $jm.version_id
                            title                 : $jm.title
                            attributes            : $jm.attributes
                            parent_work_item_id   : $zero
                            created_by            : $input.user_id
                            tasks                 : $jm.tasks
                            order_lines           : $jm.lines
                            unmatched_lines       : []
                          }
                        } as $nj

                        var.update $jt {
                          value = $jm.src_id|to_text
                        }

                        db.query work_task {
                          where = $db.work_task.work_item_id == $nj.id
                          return = {type: "list"}
                          output = ["id", "stage_key", "lens_key"]
                        } as $nj_steps

                        foreach ($nj_steps) {
                          each as $ns {
                            var.update $sk {
                              value = "x:" ~ $jt ~ "::" ~ $ns.stage_key ~ "::" ~ $ns.lens_key
                            }

                            var.update $step_new {
                              value = $step_new|set:$sk:$ns.id
                            }
                          }
                        }

                        conditional {
                          if ($jm.has_window == 1) {
                            db.add work_item_time_window {
                              data = {
                                work_item_id   : $nj.id
                                start_date     : $jm.window.start_date
                                start_time     : $jm.window.start_time
                                end_date       : $jm.window.end_date
                                end_time       : $jm.window.end_time
                                note           : $jm.window.note
                                constraint_type: "soft"
                                updated_by     : $input.user_id
                              }
                            } as $_win_row
                          }
                        }
                      }
                    }

                    // Story 04: every slot on its matching day and position (dense by construction), linked to the new step.
                    var $dest_tl {
                      value = 0
                    }

                    var $new_asg {
                      value = 0
                    }

                    var $new_step_id {
                      value = 0
                    }

                    foreach ($work.slots_make) {
                      each as $sm {
                        var.update $k {
                          value = $sm.dest
                        }

                        var.update $dest_tl {
                          value = ($new_tl|get:$k:null) ?? 0
                        }

                        var.update $t {
                          value = $sm.assignee_src|to_text
                        }

                        var.update $k {
                          value = "a:" ~ $t
                        }

                        var.update $new_asg {
                          value = ($new_agent|get:$k:null) ?? 0
                        }

                        db.add planner_task {
                          data = {
                            workspace_id     : $new_ws.id
                            timeline_id      : $dest_tl
                            assignee_agent_id: $new_asg
                            title            : $sm.title
                            seq              : $sm.pos
                            duration_minutes : $sm.duration_minutes
                            notes            : $sm.notes
                            status           : $sm.status
                            needs_info_reason: $sm.needs_info_reason
                            tweak_reason     : ""
                          }
                        } as $slot_row

                        // D-2: every slot the repeat puts on a day, and every slot it sends to the backlog for a reason, needs a person to look.
                        conditional {
                          if ($sm.on_day == 1 || $sm.review_code != "copied") {
                            db.add planner_task_review {
                              data = {
                                account_id         : $input.account_id
                                workspace_id       : $new_ws.id
                                planner_task_id    : $slot_row.id
                                reason_code        : $sm.review_code
                                reason_text        : $sm.review_text
                                source_workspace_id: $input.workspace_id
                              }
                            } as $_review_row
                          }
                        }

                        conditional {
                          if ($sm.linked == 1) {
                            var.update $sk {
                              value = $sm.step_key
                            }

                            var.update $new_step_id {
                              value = ($step_new|get:$sk:null) ?? 0
                            }

                            db.add planner_task_work_task {
                              data = {planner_task_id: $slot_row.id, work_task_id: $new_step_id, position: 1}
                            } as $_link_row
                          }
                        }

                        conditional {
                          if ($sm.on_day == 1 && $sm.start_time != "") {
                            db.add planner_task_start_override {
                              data = {planner_task_id: $slot_row.id, start_time: $sm.start_time, reason: "Carried over by a repeat", updated_by: $input.user_id}
                            } as $_ov_row
                          }
                        }
                      }
                    }

                    conditional {
                      if ($input.test_fail_at == 1) {
                        throw {
                          name = "repeat_test_fail"
                          value = "Forced failure after every row was written (test only)."
                        }
                      }
                    }

                    // Written last, so the race guard is checked with everything else already in the same write.
                    db.add plan_repeat {
                      data = {
                        account_id         : $input.account_id
                        source_workspace_id: $input.workspace_id
                        new_workspace_id   : $new_ws.id
                        new_start_date     : $plan.offer.start_date
                        shift_days         : $plan.offer.shift_days
                        state              : "ready"
                        counts             : $counts
                        left_out           : $left_out
                        created_by         : $input.user_id
                      }
                    } as $_repeat_row

                    var.update $write_ok {
                      value = true
                    }
                  }
                }
              }
            }
          }

          catch {
            var.update $write_ok {
              value = false
            }

            var.update $new_ws_id {
              value = 0
            }

            var.update $fail_msg {
              value = $error.message
            }
          }
        }
      }
    }

    var $ended {
      value = now|to_int
    }

    var $duration_ms {
      value = $ended - $started
    }

    // A write that failed: did another confirm win the race? Then answer with its plan.
    var $lost_race {
      value = false
    }

    conditional {
      if ($existing_id == 0 && $write_ok == false) {
        db.query plan_repeat {
          where = $db.plan_repeat.source_workspace_id == $input.workspace_id && $db.plan_repeat.new_start_date == $input.start_date
          return = {type: "single"}
        } as $winner

        var.update $existing_id {
          value = $winner|get:"new_workspace_id":0
        }

        var.update $lost_race {
          value = ($existing_id != 0)
        }
      }
    }

    // Opus review: a failed write with no winner on (source, date) may have lost a race on the NAME
    // (same name, another start date; planner_workspace is unique on account + name). Answer it as
    // the name refusal it is (E-PLN-001), not as a failed write.
    var $name_taken {
      value = false
    }

    conditional {
      if ($write_ok == false && $existing_id == 0) {
        db.query planner_workspace {
          where = $db.planner_workspace.account_id == $input.account_id && $db.planner_workspace.name == $input.name
          return = {type: "list"}
          output = ["id"]
        } as $name_after

        var.update $name_taken {
          value = (($name_after|count) > 0)
        }
      }
    }

    conditional {
      if ($name_taken == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat"
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-PLN-001"
            message       : "You already have a plan with this name. (E-PLN-001)"
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            metadata      : {start_date: $input.start_date, name: $input.name, lost_race: true}
          }
        } as $_logged_name
      }
    }

    precondition ($name_taken == false) {
      error_type = "inputerror"
      error = "You already have a plan with this name. (E-PLN-001)"
    }

    var $outcome {
      value = (($write_ok == true) ? "created" : "exists")
    }

    conditional {
      if ($write_ok == false && $existing_id != 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat"
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-REPEAT-005"
            message       : "This plan has already been repeated to that start date. (E-REPEAT-005)"
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            metadata      : {start_date: $input.start_date, existing_workspace_id: $existing_id, lost_race: $lost_race}
          }
        } as $_logged_exists
      }
    }

    conditional {
      if ($write_ok == false && $existing_id == 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat_failed"
            outcome       : "failure"
            severity      : "error"
            error_code    : "E-REPEAT-006"
            message       : $fail_msg
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            duration_ms   : $duration_ms
            metadata      : {start_date: $input.start_date, name: $input.name, counts: $counts}
          }
        } as $_logged_fail
      }
    }

    precondition ($write_ok == true || $existing_id != 0) {
      error_type = "standard"
      error = "The new plan couldn't be created. Nothing was saved. Try again. (E-REPEAT-006)"
    }

    conditional {
      if ($write_ok == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeated"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "Plan repeated."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $new_ws_id
            correlation_id: $input.correlation_id
            duration_ms   : $duration_ms
            metadata      : {source_workspace_id: $input.workspace_id, new_workspace_id: $new_ws_id, shift_days: $plan.offer.shift_days, counts: $counts}
          }
        } as $_logged_ok
      }
    }

    // The counts in the answer are re-read from the new plan, never the loops' own tallies (T-REPEAT-04-11).
    var $written {
      value = {}
    }

    conditional {
      if ($write_ok == true) {
        db.query work_item {
          where = $db.work_item.workspace_id == $new_ws_id
          return = {type: "list"}
          output = ["id"]
        } as $w_jobs

        var $w_job_ids {
          value = [-1]
        }

        foreach ($w_jobs) {
          each as $wj {
            array.push $w_job_ids {
              value = $wj.id
            }
          }
        }

        db.query work_task {
          where = $db.work_task.work_item_id in $w_job_ids
          return = {type: "list"}
          output = ["id"]
        } as $w_steps

        db.query work_item_line {
          where = $db.work_item_line.work_item_id in $w_job_ids
          return = {type: "list"}
          output = ["id"]
        } as $w_lines

        db.query work_item_time_window {
          where = $db.work_item_time_window.work_item_id in $w_job_ids
          return = {type: "list"}
          output = ["id"]
        } as $w_windows

        db.query planner_task {
          where = $db.planner_task.workspace_id == $new_ws_id && $db.planner_task.timeline_id != 0
          return = {type: "list"}
          output = ["id"]
        } as $w_placed

        db.query planner_task {
          where = $db.planner_task.workspace_id == $new_ws_id && $db.planner_task.timeline_id == 0
          return = {type: "list"}
          output = ["id"]
        } as $w_backlog

        db.query planner_task_review {
          where = $db.planner_task_review.workspace_id == $new_ws_id
          return = {type: "list"}
          output = ["id"]
        } as $w_reviews

        var.update $written {
          value = {
            reviews: ($w_reviews|count)
            jobs   : ($w_jobs|count)
            steps  : ($w_steps|count)
            lines  : ($w_lines|count)
            windows: ($w_windows|count)
            placed : ($w_placed|count)
            backlog: ($w_backlog|count)
          }
        }

        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat_jobs"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "Jobs repeated on their maps' current versions."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $new_ws_id
            correlation_id: $input.correlation_id
            metadata      : {source_workspace_id: $input.workspace_id, counts: $job_counts, step_changes: $work.step_changes}
          }
        } as $_logged_jobs

        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat_schedule"
            outcome       : "success"
            severity      : $sched_severity
            error_code    : ""
            message       : $sched_message
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $new_ws_id
            correlation_id: $input.correlation_id
            metadata      : {source_workspace_id: $input.workspace_id, counts: $slot_counts}
          }
        } as $_logged_sched
      }
    }

    // E-REPEAT-007: the plan exists, but no job could be repeated. A warning in the answer, not a refusal.
    var $jobs_seen {
      value = $plan.jobs|count
    }

    var $warnings {
      value = []
    }

    conditional {
      if ($write_ok == true && $jobs_seen > 0 && $job_counts.repeated == 0 && $no_jobs == false) {
        array.push $warnings {
          value = {code: "E-REPEAT-007", message: "The new plan was made, but none of its jobs could be repeated. (E-REPEAT-007)"}
        }

        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat_jobs"
            outcome       : "success"
            severity      : "warn"
            error_code    : "E-REPEAT-007"
            message       : "Plan repeated with no jobs: every job was left out."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $new_ws_id
            correlation_id: $input.correlation_id
            metadata      : {source_workspace_id: $input.workspace_id, counts: $job_counts}
          }
        } as $_logged_nojobs
      }
    }

    var $people_skipped {
      value = $counts.people_left_off + $counts.maps_left_out
    }

    conditional {
      if ($write_ok == true && $people_skipped > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "REPEAT-1"
            step          : "plan.repeat_skipped_person"
            outcome       : "success"
            severity      : "warn"
            error_code    : ""
            message       : "Plan repeated, but some people or maps were left off."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "planner_workspace"
            entity_id     : $new_ws_id
            correlation_id: $input.correlation_id
            metadata      : {source_workspace_id: $input.workspace_id, left_out: $left_out}
          }
        } as $_logged_skip
      }
    }
  }

  response = {
    outcome              : $outcome
    workspace_id         : $new_ws_id
    existing_workspace_id: $existing_id
    name                 : $input.name
    start_date           : $plan.offer.start_date
    end_date             : $plan.offer.end_date
    shift_days           : $plan.offer.shift_days
    counts               : $counts
    left_out             : $left_out
    step_changes         : $work.step_changes
    written              : $written
    warnings             : $warnings
  }
}
