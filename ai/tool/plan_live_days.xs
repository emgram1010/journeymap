// DEMAND-1 follow-up (founder 2026-11-21) — read the LIVE days of one plan: who is working which day, how far each one has got, and what was added after it went live. READ-ONLY: gate kind "read"; nothing is written except the gate's own tool-log row. Same visibility rules as plan_get (one business E-COP-045, the Planner grant, copilot/plan_in_business; every miss answers "Plan not found"). Each day is read from its CURRENT frozen snapshot (live/latest_publications), never from the live plan, so it shows exactly what the person was given. Step counts come from the steps' own statuses (the five fixed ones). No email and no user id leave here. Days default to yesterday through 7 days ahead (UTC); at most 100 days.
tool plan_live_days {
  instructions = "See the LIVE days of one plan of this business: the work people were actually given and how far it has got. For each live day: day_id, the person (member_id, name), the date, the start time, the live version (1 = published once; higher = changed or added to after going live), when it went live, how many steps it holds and how many are not started, in progress, blocked, done and skipped, whether work has begun, when the last step was recorded, and how many jobs were added after it went live (unplanned work). Draft days are not listed: use plan_get for those. Days default to yesterday through 7 days ahead; pass date_from and date_to (YYYY-MM-DD) for another range. Find the plan_id with plan_list. This only reads."

  input {
    int plan_id? {
      description = "The plan to read (from plan_list)."
    }

    text date_from? filters=trim {
      description = "Optional. First day to return, YYYY-MM-DD."
    }

    text date_to? filters=trim {
      description = "Optional. Last day to return, YYYY-MM-DD."
    }

    int journey_architecture_id? {
      description = "Only for an outside assistant (no ticket): the business (architecture id) the plan is in. Leave 0 in a copilot chat: the chat's business is used."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_live_days", kind: "read"}
    } as $cop1_gate

    var $gate_pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $gate_via {
      value = $cop1_gate.via ?? ""
    }

    var $gate_context {
      value = $cop1_gate.context ?? ""
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    function.run "copilot/work_business" {
      input = {pin: $gate_pin, via: $gate_via, context: $gate_context, named: $input.journey_architecture_id, account_id: $caller_account}
    } as $work_biz

    var $pin {
      value = $work_biz.business ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This needs one business: use it in a copilot chat about a business or, from an outside assistant, pass journey_architecture_id. (E-COP-045)"
    }

    function.run "usr/assert_module_access" {
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_live_days"}
    } as $_plan_ok

    var $date_shape_ok {
      value = (($input.date_from == "" || ("/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$input.date_from)) && ($input.date_to == "" || ("/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$input.date_to)))
    }

    precondition ($date_shape_ok) {
      error_type = "inputerror"
      error = "date_from and date_to must be dates like 2026-11-21."
    }

    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $input.plan_id, architecture_id: $pin, user_id: $caller_user}
    } as $plan_check

    var $plan_ok {
      value = (($plan_check|get:"ok":false) ?? false) == true
    }

    precondition ($plan_ok == true) {
      error_type = "notfound"
      error = "Plan not found"
    }

    db.query planner_workspace {
      where = $db.planner_workspace.id == $input.plan_id && $db.planner_workspace.account_id == $caller_account
      return = {type: "single"}
      output = ["id", "name"]
    } as $plan

    // ── the day range ──────────────────────────────────────────────────────
    var $now_ms {
      value = now|to_int
    }

    var $from_ms {
      value = $now_ms - 86400000
    }

    var $to_ms {
      value = $now_ms + 604800000
    }

    var $from {
      value = $from_ms|format_timestamp:"Y-m-d":"UTC"
    }

    var $to {
      value = $to_ms|format_timestamp:"Y-m-d":"UTC"
    }

    conditional {
      if ($input.date_from != "") {
        var.update $from {
          value = $input.date_from
        }
      }
    }

    conditional {
      if ($input.date_to != "") {
        var.update $to {
          value = $input.date_to
        }
      }
    }

    // ── live days and their people ─────────────────────────────────────────
    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.plan_id && $db.planner_timeline.status == "published" && $db.planner_timeline.planned_date >= $from && $db.planner_timeline.planned_date <= $to
      sort = {planner_timeline.planned_date: "asc", planner_timeline.id: "asc"}
      return = {type: "list"}
      output = ["id", "agent_id", "planned_date", "start_time"]
    } as $timelines

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.plan_id
      return = {type: "list"}
      output = ["id", "name"]
    } as $agents

    var $key {
      value = ""
    }

    var $name_by_agent {
      value = {}
    }

    foreach ($agents) {
      each as $a {
        var.update $key {
          value = "a:" ~ ($a.id|to_text)
        }

        var.update $name_by_agent {
          value = $name_by_agent|set:$key:$a.name
        }
      }
    }

    // Every tally is pre-seeded per day, so no lookup below can miss.
    var $tl_ids {
      value = []
    }

    var $m_steps {
      value = {}
    }

    var $m_status {
      value = {}
    }

    var $m_events {
      value = {}
    }

    var $m_last {
      value = {}
    }

    var $m_added {
      value = {}
    }

    var $m_version {
      value = {}
    }

    var $m_live {
      value = {}
    }

    var $s1 {
      value = ""
    }

    var $s2 {
      value = ""
    }

    var $s3 {
      value = ""
    }

    var $s4 {
      value = ""
    }

    var $s5 {
      value = ""
    }

    var $dk {
      value = ""
    }

    foreach ($timelines) {
      each as $t {
        array.push $tl_ids {
          value = $t.id
        }

        var.update $dk {
          value = "d:" ~ ($t.id|to_text)
        }

        var.update $s1 {
          value = $dk ~ ":not_started"
        }

        var.update $s2 {
          value = $dk ~ ":in_progress"
        }

        var.update $s3 {
          value = $dk ~ ":blocked"
        }

        var.update $s4 {
          value = $dk ~ ":done"
        }

        var.update $s5 {
          value = $dk ~ ":skipped"
        }

        var.update $m_status {
          value = $m_status|set:$s1:0|set:$s2:0|set:$s3:0|set:$s4:0|set:$s5:0
        }

        var.update $m_steps {
          value = $m_steps|set:$dk:0
        }

        var.update $m_events {
          value = $m_events|set:$dk:0
        }

        var.update $m_last {
          value = $m_last|set:$dk:0
        }

        var.update $m_added {
          value = $m_added|set:$dk:0
        }

        var.update $m_version {
          value = $m_version|set:$dk:0
        }

        var.update $m_live {
          value = $m_live|set:$dk:0
        }
      }
    }

    function.run "live/latest_publications" {
      input = {timeline_ids: $tl_ids}
    } as $latest

    // Which day each frozen step belongs to.
    var $wt_ids {
      value = [-1]
    }

    var $day_of_wt {
      value = {}
    }

    var $wk {
      value = ""
    }

    var $n {
      value = 0
    }

    foreach ($latest.publications) {
      each as $p {
        var.update $dk {
          value = "d:" ~ ($p.timeline_id|to_text)
        }

        var.update $m_version {
          value = $m_version|set:$dk:$p.version
        }

        var.update $m_live {
          value = $m_live|set:$dk:$p.published_at
        }

        foreach ($p.snapshot.items) {
          each as $it {
            foreach ($it.work_task_ids) {
              each as $wid {
                array.push $wt_ids {
                  value = $wid
                }

                var.update $wk {
                  value = "w:" ~ ($wid|to_text)
                }

                var.update $day_of_wt {
                  value = $day_of_wt|set:$wk:$dk
                }

                var.update $n {
                  value = (($m_steps|get:$dk:null) ?? 0) + 1
                }

                var.update $m_steps {
                  value = $m_steps|set:$dk:$n
                }
              }
            }
          }
        }
      }
    }

    db.query work_task {
      where = $db.work_task.id in $wt_ids
      return = {type: "list"}
      output = ["id", "status"]
    } as $steps

    var $sk {
      value = ""
    }

    foreach ($steps) {
      each as $st {
        var.update $wk {
          value = "w:" ~ ($st.id|to_text)
        }

        var.update $dk {
          value = ($day_of_wt|get:$wk:null) ?? "d:0"
        }

        var.update $sk {
          value = $dk ~ ":" ~ $st.status
        }

        var.update $n {
          value = (($m_status|get:$sk:null) ?? 0) + 1
        }

        var.update $m_status {
          value = $m_status|set:$sk:$n
        }
      }
    }

    db.query activity_log {
      where = $db.activity_log.work_task_id in $wt_ids
      return = {type: "list"}
      output = ["id", "work_task_id", "occurred_at"]
    } as $events

    var $last {
      value = 0
    }

    var $gt {
      value = 0
    }

    foreach ($events) {
      each as $ev {
        var.update $wk {
          value = "w:" ~ ($ev.work_task_id|to_text)
        }

        var.update $dk {
          value = ($day_of_wt|get:$wk:null) ?? "d:0"
        }

        var.update $n {
          value = (($m_events|get:$dk:null) ?? 0) + 1
        }

        var.update $last {
          value = ($m_last|get:$dk:null) ?? 0
        }

        var.update $gt {
          value = (($ev.occurred_at ?? 0) > $last)|to_int
        }

        var.update $last {
          value = $last + ((($ev.occurred_at ?? 0) - $last) * $gt)
        }

        var.update $m_events {
          value = $m_events|set:$dk:$n
        }

        var.update $m_last {
          value = $m_last|set:$dk:$last
        }
      }
    }

    db.query live_day_addition {
      where = $db.live_day_addition.timeline_id in $tl_ids
      return = {type: "list"}
      output = ["id", "timeline_id"]
    } as $adds

    foreach ($adds) {
      each as $ad {
        var.update $dk {
          value = "d:" ~ ($ad.timeline_id|to_text)
        }

        var.update $n {
          value = (($m_added|get:$dk:null) ?? 0) + 1
        }

        var.update $m_added {
          value = $m_added|set:$dk:$n
        }
      }
    }

    // ── one row per live day ───────────────────────────────────────────────
    var $days {
      value = []
    }

    var $pos {
      value = 0
    }

    var $row {
      value = {}
    }

    var $ak {
      value = ""
    }

    foreach ($timelines) {
      each as $t2 {
        var.update $pos {
          value = $pos + 1
        }

        var.update $dk {
          value = "d:" ~ ($t2.id|to_text)
        }

        var.update $ak {
          value = "a:" ~ ($t2.agent_id|to_text)
        }

        var.update $s1 {
          value = $dk ~ ":not_started"
        }

        var.update $s2 {
          value = $dk ~ ":in_progress"
        }

        var.update $s3 {
          value = $dk ~ ":blocked"
        }

        var.update $s4 {
          value = $dk ~ ":done"
        }

        var.update $s5 {
          value = $dk ~ ":skipped"
        }

        var.update $row {
          value = {
            day_id          : $t2.id
            member_id       : $t2.agent_id
            member_name     : (($name_by_agent|get:$ak:null) ?? "")
            date            : $t2.planned_date
            start_time      : $t2.start_time
            live_version    : (($m_version|get:$dk:null) ?? 0)
            live_since      : (($m_live|get:$dk:null) ?? 0)
            steps           : (($m_steps|get:$dk:null) ?? 0)
            not_started     : (($m_status|get:$s1:null) ?? 0)
            in_progress     : (($m_status|get:$s2:null) ?? 0)
            blocked         : (($m_status|get:$s3:null) ?? 0)
            done            : (($m_status|get:$s4:null) ?? 0)
            skipped         : (($m_status|get:$s5:null) ?? 0)
            work_begun      : ((($m_events|get:$dk:null) ?? 0) > 0)
            last_recorded_at: (($m_last|get:$dk:null) ?? 0)
            jobs_added_after_live: (($m_added|get:$dk:null) ?? 0)
          }
        }

        array.push $days {
          value = {pos: $pos, row: $row}
        }
      }
    }

    var $shown {
      value = []
    }

    foreach ($days) {
      each as $d {
        conditional {
          if ($d.pos <= 100) {
            array.push $shown {
              value = $d.row
            }
          }
        }
      }
    }

    var $total {
      value = $days|count
    }
  }

  response = {
    plan          : {plan_id: $plan.id, name: $plan.name}
    live_days     : $shown
    live_days_total: $total
    truncated     : ($total > 100)
    days_from     : $from
    days_to       : $to
  }
}
