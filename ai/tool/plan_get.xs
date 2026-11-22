// DISC-1 story 02 (2026-11-21) — read ONE plan: its header, people, open jobs and days, so an AI
// knows what is draft, what is live and who is on the plan before it changes anything.
// READ-ONLY: gate kind "read"; nothing is written except the gate's own tool-log row.
// Visibility is the existing rules, never copied: one business (copilot/work_business, E-COP-045),
// the Planner grant (usr/assert_module_access), and copilot/plan_in_business. A plan in another
// account, in another business, or an empty plan somebody else made all answer "Plan not found" -
// one answer, so a refusal never confirms a plan exists.
// No email and no user id leave here: has_login is yes/no only.
// Days default to 7 days back and 14 days ahead (UTC dates); at most 200 open jobs are returned.
tool plan_get {
  instructions = "Read one plan of this business before you change it. Returns the plan header, its people (id, name, person or AI, whether they have a login, active), its open jobs (id, title, status, the map and version each one is pinned to) and its days (id, person, date, state draft or live, planned minutes, capacity minutes). A day whose planned minutes are above its capacity minutes is over capacity. Days default to 7 days back and 14 days ahead; pass date_from and date_to (YYYY-MM-DD) for another range. At most 200 open jobs come back: jobs_truncated says so and jobs_total gives the full count. Find the plan_id with plan_list. This only reads."

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
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_get", kind: "read"}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_get"}
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

    // One answer for every miss: not there, another account, another business.
    precondition ($plan_ok == true) {
      error_type = "notfound"
      error = "Plan not found"
    }

    db.query planner_workspace {
      where = $db.planner_workspace.id == $input.plan_id && $db.planner_workspace.account_id == $caller_account
      return = {type: "single"}
      output = ["id", "name", "planning_window_start", "planning_window_end", "is_archived"]
    } as $plan

    // ── the day range ──────────────────────────────────────────────────────
    var $default_from_ts {
      value = now|transform_timestamp:"7 days ago":"UTC"
    }

    var $default_to_ts {
      value = now|transform_timestamp:"+14 days":"UTC"
    }

    var $from {
      value = $default_from_ts|format_timestamp:"Y-m-d":"UTC"
    }

    var $to {
      value = $default_to_ts|format_timestamp:"Y-m-d":"UTC"
    }

    var $range_source {
      value = "default: 7 days back to 14 days ahead (UTC)"
    }

    conditional {
      if ($input.date_from != "") {
        var.update $from {
          value = $input.date_from
        }

        var.update $range_source {
          value = "as asked"
        }
      }
    }

    conditional {
      if ($input.date_to != "") {
        var.update $to {
          value = $input.date_to
        }

        var.update $range_source {
          value = "as asked"
        }
      }
    }

    // ── people ─────────────────────────────────────────────────────────────
    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.plan_id
      sort = {planner_agent.id: "asc"}
      return = {type: "list"}
      output = ["id", "name", "kind", "user_id", "is_active", "daily_capacity_hours"]
    } as $agents

    var $members {
      value = []
    }

    var $cap_by_agent {
      value = {}
    }

    var $key {
      value = ""
    }

    var $cap_minutes {
      value = 0
    }

    var $has_login {
      value = false
    }

    foreach ($agents) {
      each as $a {
        var.update $key {
          value = "a:" ~ ($a.id|to_text)
        }

        var.update $cap_minutes {
          value = ($a.daily_capacity_hours ?? 0) * 60
        }

        var.update $cap_by_agent {
          value = $cap_by_agent|set:$key:$cap_minutes
        }

        var.update $has_login {
          value = ($a.user_id ?? 0) > 0
        }

        array.push $members {
          value = {member_id: $a.id, name: $a.name, kind: $a.kind, has_login: $has_login, active: $a.is_active, capacity_minutes: $cap_minutes}
        }
      }
    }

    // ── open jobs ──────────────────────────────────────────────────────────
    db.query work_item {
      where = $db.work_item.workspace_id == $input.plan_id && ($db.work_item.status == "open" || $db.work_item.status == "in_progress" || $db.work_item.status == "blocked")
      sort = {work_item.id: "asc"}
      return = {type: "list"}
      output = ["id", "title", "status", "journey_map_version_id", "parent_work_item_id"]
    } as $job_rows

    var $version_ids {
      value = [-1]
    }

    foreach ($job_rows) {
      each as $j {
        array.push $version_ids {
          value = $j.journey_map_version_id
        }
      }
    }

    // Never the snapshot: only the id, map and number.
    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
      output = ["id", "journey_map_id", "version_no"]
    } as $versions

    var $map_ids {
      value = [-1]
    }

    var $ver_map {
      value = {}
    }

    var $ver_no {
      value = {}
    }

    foreach ($versions) {
      each as $v {
        var.update $key {
          value = "v:" ~ ($v.id|to_text)
        }

        var.update $ver_map {
          value = $ver_map|set:$key:$v.journey_map_id
        }

        var.update $ver_no {
          value = $ver_no|set:$key:$v.version_no
        }

        array.push $map_ids {
          value = $v.journey_map_id
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $map_ids && $db.journey_map.account_id == $caller_account
      return = {type: "list"}
      output = ["id", "title"]
    } as $map_rows

    var $titles {
      value = {}
    }

    foreach ($map_rows) {
      each as $m {
        var.update $key {
          value = "m:" ~ ($m.id|to_text)
        }

        var.update $titles {
          value = $titles|set:$key:$m.title
        }
      }
    }

    // Pass 1 gives every job its position; pass 2 branches on the row itself (cap 200).
    var $job_staged {
      value = []
    }

    var $pos {
      value = 0
    }

    var $j_map {
      value = 0
    }

    var $j_ver {
      value = 0
    }

    var $j_title {
      value = ""
    }

    var $mkey {
      value = ""
    }

    foreach ($job_rows) {
      each as $j2 {
        var.update $pos {
          value = $pos + 1
        }

        var.update $key {
          value = "v:" ~ ($j2.journey_map_version_id|to_text)
        }

        var.update $j_map {
          value = ($ver_map|get:$key:null) ?? 0
        }

        var.update $j_ver {
          value = ($ver_no|get:$key:null) ?? 0
        }

        var.update $mkey {
          value = "m:" ~ ($j_map|to_text)
        }

        var.update $j_title {
          value = ($titles|get:$mkey:null) ?? ""
        }

        array.push $job_staged {
          value = {pos: $pos, job_id: $j2.id, title: $j2.title, status: $j2.status, journey_map_id: $j_map, map_title: $j_title, version_no: $j_ver, parent_job_id: $j2.parent_work_item_id}
        }
      }
    }

    var $jobs {
      value = []
    }

    foreach ($job_staged) {
      each as $s {
        conditional {
          if ($s.pos <= 200) {
            array.push $jobs {
              value = {job_id: $s.job_id, title: $s.title, status: $s.status, journey_map_id: $s.journey_map_id, map_title: $s.map_title, version_no: $s.version_no, parent_job_id: $s.parent_job_id}
            }
          }
        }
      }
    }

    // ── days ───────────────────────────────────────────────────────────────
    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.plan_id && $db.planner_timeline.planned_date >= $from && $db.planner_timeline.planned_date <= $to
      sort = {planner_timeline.planned_date: "asc"}
      return = {type: "list"}
      output = ["id", "agent_id", "planned_date", "start_time", "status"]
    } as $timelines

    var $tl_ids {
      value = [-1]
    }

    var $minutes_tally {
      value = {}
    }

    var $count_tally {
      value = {}
    }

    foreach ($timelines) {
      each as $t {
        var.update $key {
          value = "d:" ~ ($t.id|to_text)
        }

        var.update $minutes_tally {
          value = $minutes_tally|set:$key:0
        }

        var.update $count_tally {
          value = $count_tally|set:$key:0
        }

        array.push $tl_ids {
          value = $t.id
        }
      }
    }

    // Scoped to these days, so no branch is needed while adding up (endpoint 539's shape).
    db.query planner_task {
      where = $db.planner_task.timeline_id in $tl_ids
      return = {type: "list"}
      output = ["id", "timeline_id", "duration_minutes"]
    } as $slots

    var $cur {
      value = 0
    }

    var $next {
      value = 0
    }

    foreach ($slots) {
      each as $k {
        var.update $key {
          value = "d:" ~ ($k.timeline_id|to_text)
        }

        var.update $cur {
          value = ($minutes_tally|get:$key:null) ?? 0
        }

        var.update $next {
          value = $cur + ($k.duration_minutes ?? 0)
        }

        var.update $minutes_tally {
          value = $minutes_tally|set:$key:$next
        }

        var.update $cur {
          value = ($count_tally|get:$key:null) ?? 0
        }

        var.update $next {
          value = $cur + 1
        }

        var.update $count_tally {
          value = $count_tally|set:$key:$next
        }
      }
    }

    var $days {
      value = []
    }

    var $d_minutes {
      value = 0
    }

    var $d_count {
      value = 0
    }

    var $d_cap {
      value = 0
    }

    var $d_state {
      value = ""
    }

    var $akey {
      value = ""
    }

    foreach ($timelines) {
      each as $t2 {
        var.update $key {
          value = "d:" ~ ($t2.id|to_text)
        }

        var.update $akey {
          value = "a:" ~ ($t2.agent_id|to_text)
        }

        var.update $d_minutes {
          value = ($minutes_tally|get:$key:null) ?? 0
        }

        var.update $d_count {
          value = ($count_tally|get:$key:null) ?? 0
        }

        var.update $d_cap {
          value = ($cap_by_agent|get:$akey:null) ?? 0
        }

        var.update $d_state {
          value = (($t2.status == "published") ? "live" : "draft")
        }

        array.push $days {
          value = {day_id: $t2.id, member_id: $t2.agent_id, date: $t2.planned_date, start_time: $t2.start_time, state: $d_state, scheduled_steps: $d_count, planned_minutes: $d_minutes, capacity_minutes: $d_cap}
        }
      }
    }

    var $jobs_total {
      value = $job_rows|count
    }
  }

  response = {
    plan          : {plan_id: $plan.id, name: $plan.name, window_start: $plan.planning_window_start, window_end: $plan.planning_window_end, archived: $plan.is_archived}
    members       : $members
    jobs          : $jobs
    jobs_total    : $jobs_total
    jobs_truncated: ($jobs_total > 200)
    days          : $days
    days_from     : $from
    days_to       : $to
    days_range    : $range_source
  }
}
