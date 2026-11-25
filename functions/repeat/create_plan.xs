// REPEAT-1 story 02 — Make the new plan from a repeat: the plan itself, its accepted maps, its people and their days, moved forward. Stories 03 and 04 add the jobs and slots to the SAME write. What to copy is decided by repeat/build_plan (the rule the preview shows), never re-decided here. One all-or-nothing db.transaction (story 00: 550 rows in 5.9 s), so the plan_repeat row is written straight as `ready` and a half-built plan is never visible. THE RACE GUARD is plan_repeat's unique index on (source plan, start date), plus planner_workspace's unique (account, name): two confirms at once both reach the insert, the database refuses the second, its whole transaction rolls back, and the loser is answered with the winner's plan (outcome "exists", E-REPEAT-005). A "does it exist?" read is only the fast path for a second click (EXC-1). A person who is switched off (inactive, or their login is off) is not added and is named with the reason. A map the source accepts that is now archived, deleted or another account's is not copied and is named. Days keep their start time, move by shift_days, and are always draft. The source plan is only read. test_fail_at = 1 throws inside the transaction after every row is written, to prove nothing is left behind; the endpoint always passes 0.
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
  }

  stack {
    function.run "repeat/build_plan" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id, start_date: $input.start_date, skip_job_ids: $input.skip_job_ids}
    } as $plan

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

        conditional {
          if ($c.off == 1) {
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
          value = {agent_id: $tl.agent_id, off: $off_n, new_date: $new_date, start_time: $tl.start_time}
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

    var $counts {
      value = {
        people         : ($agents_copy|count)
        people_left_off: (($agent_checks|count) - ($agents_copy|count))
        days           : ($days_copy|count)
        maps           : ($maps_copy|count)
        maps_left_out  : (($map_checks|count) - ($maps_copy|count))
      }
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
                        } as $_day_row
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
  }
}
