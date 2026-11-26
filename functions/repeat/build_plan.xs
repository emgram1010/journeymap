// REPEAT-1 story 01 — THE one rule for "what does repeating this plan copy, and what does it leave out". Read-only: it writes nothing. The preview endpoint returns its answer; the real copy (stories 02-04) executes the same answer, so the preview cannot promise something the copy does not do. Tenancy is planner/assert_workspace (another account's plan is "not found"). A bad start date or an overlapping window is returned as reject_code / reject_msg, not thrown, so the caller can log the refusal before raising it. Verdict per job: repeat | left_out (the planner unticked it) | will_not_repeat (cancelled, an outside order, an exception child: one-off facts) | cannot_repeat (its map is gone, archived, no longer accepted by the plan, or has no published version). A repeated job reads its map's CURRENT published version (D-6). A person who is switched off is left off and their slots go to the backlog. No conditional inside a loop: every branch is arithmetic on the loop item or a map lookup, because a conditional that reads a variable updated in the same pass silently loses its writes (CLAUDE.md).
function "repeat/build_plan" {
  input {
    int account_id
    int workspace_id
    text start_date? filters=trim
    int[] skip_job_ids?
  }

  stack {
    function.run "planner/assert_workspace" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id}
    } as $guard

    var $ws {
      value = $guard.workspace
    }

    // ── Dates: the one rule, shared with repeat/list_periods ────────
    function.run "repeat/period_dates" {
      input = {src_start: $ws.planning_window_start, src_end: $ws.planning_window_end, start_date: $input.start_date}
    } as $dates

    var $reject_code {
      value = $dates.reject_code
    }

    var $reject_msg {
      value = $dates.reject_msg
    }

    var $new_start {
      value = $dates.new_start
    }

    var $new_end {
      value = $dates.new_end
    }

    var $shift_days {
      value = $dates.shift_days
    }

    var $weekdays_align {
      value = $dates.weekdays_align
    }

    var $length_days {
      value = $dates.length_days
    }

    // ── A free name that shows the start date: the one rule, shared with repeat/list_periods ──
    function.run "repeat/free_name" {
      input = {account_id: $input.account_id, source_name: $ws.name, start_date: $new_start}
    } as $fname

    var $candidate {
      value = $fname.name
    }

    var $name_free {
      value = $fname.free
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id", "name", "kind", "user_id", "is_active"]
    } as $agents

    var $user_ids {
      value = [-1]
    }

    foreach ($agents) {
      each as $a {
        array.push $user_ids {
          value = $a.user_id ?? 0
        }
      }
    }

    db.query user_status {
      where = $db.user_status.user_id in $user_ids && $db.user_status.user_id != 0 && $db.user_status.is_active == false
      return = {type: "list"}
      output = ["user_id"]
    } as $off_users

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    var $off_user_set {
      value = {}
    }

    foreach ($off_users) {
      each as $u {
        var.update $t {
          value = $u.user_id|to_text
        }

        var.update $k {
          value = "u:" ~ $t
        }

        var.update $off_user_set {
          value = $off_user_set|set:$k:1
        }
      }
    }

    var $agent_off {
      value = {}
    }

    var $agent_slots {
      value = {}
    }

    var $n {
      value = 0
    }

    var $flag {
      value = 0
    }

    var $people_copy {
      value = 0
    }

    foreach ($agents) {
      each as $a {
        var.update $t {
          value = ($a.user_id ?? 0)|to_text
        }

        var.update $k {
          value = "u:" ~ $t
        }

        var.update $n {
          value = ($off_user_set|get:$k:null) ?? 0
        }

        var.update $flag {
          value = ((($a.is_active == false)|to_int) + $n) > 0
        }

        var.update $flag {
          value = $flag|to_int
        }

        var.update $t {
          value = $a.id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $agent_off {
          value = $agent_off|set:$k:$flag
        }

        var.update $agent_slots {
          value = $agent_slots|set:$k:0
        }

        var.update $people_copy {
          value = $people_copy + (1 - $flag)
        }
      }
    }

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id", "agent_id"]
    } as $timelines

    var $tl_agent {
      value = {}
    }

    var $days_copy {
      value = 0
    }

    var $aid {
      value = 0
    }

    foreach ($timelines) {
      each as $tl {
        var.update $t {
          value = $tl.id|to_text
        }

        var.update $k {
          value = "t:" ~ $t
        }

        var.update $aid {
          value = $tl.agent_id ?? 0
        }

        var.update $tl_agent {
          value = $tl_agent|set:$k:$aid
        }

        var.update $t {
          value = $aid|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $flag {
          value = ($agent_off|get:$k:null) ?? 0
        }

        var.update $days_copy {
          value = $days_copy + (1 - $flag)
        }
      }
    }

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id && $db.work_item.account_id == $input.account_id
      return = {type: "list"}
      output = ["id", "title", "status", "journey_map_version_id", "parent_work_item_id"]
      sort = {work_item.id: "asc"}
    } as $jobs_raw

    var $job_ids {
      value = [-1]
    }

    var $ver_ids {
      value = [-1]
    }

    foreach ($jobs_raw) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }

        array.push $ver_ids {
          value = $j.journey_map_version_id ?? 0
        }
      }
    }

    db.query work_item_origin {
      where = $db.work_item_origin.work_item_id in $job_ids
      return = {type: "list"}
      output = ["work_item_id"]
    } as $origins

    var $origin_set {
      value = {}
    }

    foreach ($origins) {
      each as $o {
        var.update $t {
          value = $o.work_item_id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $origin_set {
          value = $origin_set|set:$k:1
        }
      }
    }

    db.query work_item_exception {
      where = $db.work_item_exception.child_work_item_id in $job_ids
      return = {type: "list"}
      output = ["child_work_item_id"]
    } as $children

    var $child_set {
      value = {}
    }

    foreach ($children) {
      each as $c {
        var.update $t {
          value = $c.child_work_item_id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $child_set {
          value = $child_set|set:$k:1
        }
      }
    }

    var $skip_set {
      value = {}
    }

    foreach ($input.skip_job_ids) {
      each as $sid {
        var.update $t {
          value = $sid|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $skip_set {
          value = $skip_set|set:$k:1
        }
      }
    }

    // The version each job is pinned to → its map.
    db.query journey_map_version {
      where = $db.journey_map_version.id in $ver_ids
      return = {type: "list"}
      output = ["id", "journey_map_id"]
    } as $pinned

    var $ver_map {
      value = {}
    }

    var $map_ids {
      value = [-1]
    }

    foreach ($pinned) {
      each as $v {
        var.update $t {
          value = $v.id|to_text
        }

        var.update $k {
          value = "v:" ~ $t
        }

        var.update $ver_map {
          value = $ver_map|set:$k:$v.journey_map_id
        }

        array.push $map_ids {
          value = $v.journey_map_id
        }
      }
    }

    // Each map's CURRENT published version: sorted ascending, so the last one written wins.
    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $map_ids
      return = {type: "list"}
      output = ["id", "journey_map_id", "version_no"]
      sort = {journey_map_version.version_no: "asc"}
    } as $all_versions

    var $latest {
      value = {}
    }

    var $latest_no {
      value = {}
    }

    foreach ($all_versions) {
      each as $v {
        var.update $t {
          value = $v.journey_map_id|to_text
        }

        var.update $k {
          value = "m:" ~ $t
        }

        var.update $latest {
          value = $latest|set:$k:$v.id
        }

        var.update $latest_no {
          value = $latest_no|set:$k:$v.version_no
        }
      }
    }

    // Maps a job may still be made from: this account's, not deleted, not archived.
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
      where = $db.journey_map.id in $map_ids && $db.journey_map.account_id == $input.account_id && $db.journey_map.status != "archived" && ($db.journey_map.id not in $deleted_ids)
      return = {type: "list"}
      output = ["id", "title"]
    } as $usable_maps

    // A map the plan no longer accepts cannot make a job (the same rule "add a job" applies, E-JOB-002).
    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["journey_map_id"]
    } as $accepted_rows

    var $accepted_set {
      value = {}
    }

    foreach ($accepted_rows) {
      each as $ar {
        var.update $t {
          value = $ar.journey_map_id|to_text
        }

        var.update $k {
          value = "m:" ~ $t
        }

        var.update $accepted_set {
          value = $accepted_set|set:$k:1
        }
      }
    }

    var $accepted {
      value = 0
    }

    var $map_ok {
      value = {}
    }

    var $map_title {
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

        var.update $map_title {
          value = $map_title|set:$k:$m.title
        }
      }
    }

    // Steps per job, and which job each step belongs to.
    db.query work_task {
      where = $db.work_task.work_item_id in $job_ids
      return = {type: "list"}
      output = ["id", "work_item_id"]
    } as $steps

    var $step_job {
      value = {}
    }

    var $job_steps {
      value = {}
    }

    var $job_slots {
      value = {}
    }

    var $step_ids {
      value = [-1]
    }

    foreach ($jobs_raw) {
      each as $j {
        var.update $t {
          value = $j.id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $job_steps {
          value = $job_steps|set:$k:0
        }

        var.update $job_slots {
          value = $job_slots|set:$k:0
        }
      }
    }

    foreach ($steps) {
      each as $s {
        var.update $t {
          value = $s.id|to_text
        }

        var.update $k {
          value = "s:" ~ $t
        }

        var.update $step_job {
          value = $step_job|set:$k:$s.work_item_id
        }

        array.push $step_ids {
          value = $s.id
        }

        var.update $t {
          value = $s.work_item_id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $n {
          value = ($job_steps|get:$k:null) ?? 0
        }

        var.update $n {
          value = $n + 1
        }

        var.update $job_steps {
          value = $job_steps|set:$k:$n
        }
      }
    }

    // Which job each scheduled slot belongs to.
    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id in $step_ids
      return = {type: "list"}
      output = ["planner_task_id", "work_task_id"]
    } as $links

    var $slot_job {
      value = {}
    }

    var $jid {
      value = 0
    }

    foreach ($links) {
      each as $l {
        var.update $t {
          value = $l.work_task_id|to_text
        }

        var.update $k {
          value = "s:" ~ $t
        }

        var.update $jid {
          value = ($step_job|get:$k:null) ?? 0
        }

        var.update $t {
          value = $l.planner_task_id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $slot_job {
          value = $slot_job|set:$k:$jid
        }
      }
    }

    var $jobs {
      value = []
    }

    var $job_repeats {
      value = {}
    }

    var $is_origin {
      value = 0
    }

    var $is_child {
      value = 0
    }

    var $is_cancelled {
      value = 0
    }

    var $is_skipped {
      value = 0
    }

    var $map_id {
      value = 0
    }

    var $to_version {
      value = 0
    }

    var $to_version_no {
      value = 0
    }

    var $usable {
      value = 0
    }

    var $one_off {
      value = 0
    }

    var $blocked {
      value = 0
    }

    var $reason {
      value = ""
    }

    var $verdict {
      value = ""
    }

    var $repeats {
      value = 0
    }

    var $newer {
      value = false
    }

    var $steps_n {
      value = 0
    }

    var $m_title {
      value = ""
    }

    var $jk {
      value = ""
    }

    var $jobs_copy {
      value = 0
    }

    var $jobs_left_out {
      value = 0
    }

    var $jobs_will_not {
      value = 0
    }

    var $jobs_cannot {
      value = 0
    }

    var $jobs_newer {
      value = 0
    }

    var $steps_copy {
      value = 0
    }

    foreach ($jobs_raw) {
      each as $j {
        var.update $t {
          value = $j.id|to_text
        }

        var.update $jk {
          value = "j:" ~ $t
        }

        var.update $is_origin {
          value = ($origin_set|get:$jk:null) ?? 0
        }

        var.update $n {
          value = ($child_set|get:$jk:null) ?? 0
        }

        var.update $is_child {
          value = $n + ((($j.parent_work_item_id ?? 0) != 0)|to_int)
        }

        var.update $is_cancelled {
          value = ($j.status == "cancelled")|to_int
        }

        var.update $is_skipped {
          value = ($skip_set|get:$jk:null) ?? 0
        }

        var.update $steps_n {
          value = ($job_steps|get:$jk:null) ?? 0
        }

        var.update $t {
          value = ($j.journey_map_version_id ?? 0)|to_text
        }

        var.update $k {
          value = "v:" ~ $t
        }

        var.update $map_id {
          value = ($ver_map|get:$k:null) ?? 0
        }

        var.update $t {
          value = $map_id|to_text
        }

        var.update $k {
          value = "m:" ~ $t
        }

        var.update $to_version {
          value = ($latest|get:$k:null) ?? 0
        }

        var.update $to_version_no {
          value = ($latest_no|get:$k:null) ?? 0
        }

        var.update $usable {
          value = ($map_ok|get:$k:null) ?? 0
        }

        var.update $m_title {
          value = ($map_title|get:$k:null) ?? ""
        }

        var.update $accepted {
          value = ($accepted_set|get:$k:null) ?? 0
        }

        var.update $one_off {
          value = (($is_origin + $is_child + $is_cancelled) > 0)|to_int
        }

        var.update $blocked {
          value = (($usable == 0) || ($to_version == 0) || ($accepted == 0))|to_int
        }

        // Lowest priority first; each later line overrides the one before.
        var.update $reason {
          value = (($is_skipped > 0) ? "left_out" : "")
        }

        var.update $reason {
          value = (($to_version == 0) ? "no_published_version" : $reason)
        }

        var.update $reason {
          value = (($accepted == 0) ? "map_not_accepted" : $reason)
        }

        var.update $reason {
          value = (($usable == 0) ? "map_unavailable" : $reason)
        }

        var.update $reason {
          value = (($is_child > 0) ? "exception_child" : $reason)
        }

        var.update $reason {
          value = (($is_origin > 0) ? "outside_order" : $reason)
        }

        var.update $reason {
          value = (($is_cancelled > 0) ? "cancelled" : $reason)
        }

        var.update $verdict {
          value = (($is_skipped > 0) ? "left_out" : "repeat")
        }

        var.update $verdict {
          value = (($blocked > 0) ? "cannot_repeat" : $verdict)
        }

        var.update $verdict {
          value = (($one_off > 0) ? "will_not_repeat" : $verdict)
        }

        var.update $repeats {
          value = ($verdict == "repeat")|to_int
        }

        var.update $newer {
          value = ($repeats == 1) && ($to_version != ($j.journey_map_version_id ?? 0))
        }

        var.update $job_repeats {
          value = $job_repeats|set:$jk:$repeats
        }

        var.update $jobs_copy {
          value = $jobs_copy + $repeats
        }

        var.update $steps_copy {
          value = $steps_copy + ($repeats * $steps_n)
        }

        var.update $jobs_left_out {
          value = $jobs_left_out + (($verdict == "left_out")|to_int)
        }

        var.update $jobs_will_not {
          value = $jobs_will_not + (($verdict == "will_not_repeat")|to_int)
        }

        var.update $jobs_cannot {
          value = $jobs_cannot + (($verdict == "cannot_repeat")|to_int)
        }

        var.update $jobs_newer {
          value = $jobs_newer + ($newer|to_int)
        }

        array.push $jobs {
          value = {
            id                : $j.id
            title             : $j.title
            status            : $j.status
            verdict           : $verdict
            reason            : $reason
            uses_newer_version: $newer
            map_id            : $map_id
            map_title         : $m_title
            from_version_id   : $j.journey_map_version_id
            to_version_id     : $to_version
            to_version_no     : $to_version_no
            steps             : $steps_n
          }
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id", "timeline_id"]
    } as $slots

    var $placed {
      value = 0
    }

    var $job_ok {
      value = 0
    }

    var $off {
      value = 0
    }

    var $ak {
      value = ""
    }

    var $slots_copy {
      value = 0
    }

    var $slots_to_backlog {
      value = 0
    }

    var $backlog_copy {
      value = 0
    }

    var $slots_dropped {
      value = 0
    }

    foreach ($slots) {
      each as $p {
        var.update $placed {
          value = (($p.timeline_id ?? 0) != 0)|to_int
        }

        var.update $t {
          value = $p.id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $jid {
          value = ($slot_job|get:$k:null) ?? 0
        }

        var.update $t {
          value = $jid|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $n {
          value = ($job_repeats|get:$k:null) ?? 0
        }

        // A slot with no job behind it is plain planner work and is copied as it is.
        var.update $job_ok {
          value = (($jid == 0) ? 1 : $n)
        }

        var.update $t {
          value = ($p.timeline_id ?? 0)|to_text
        }

        var.update $k {
          value = "t:" ~ $t
        }

        var.update $aid {
          value = ($tl_agent|get:$k:null) ?? 0
        }

        var.update $t {
          value = $aid|to_text
        }

        var.update $ak {
          value = "a:" ~ $t
        }

        var.update $off {
          value = ($agent_off|get:$ak:null) ?? 0
        }

        var.update $n {
          value = ($agent_slots|get:$ak:null) ?? 0
        }

        var.update $n {
          value = $n + ($placed * $job_ok * $off)
        }

        var.update $agent_slots {
          value = $agent_slots|set:$ak:$n
        }

        var.update $slots_copy {
          value = $slots_copy + ($placed * $job_ok * (1 - $off))
        }

        var.update $slots_to_backlog {
          value = $slots_to_backlog + ($placed * $job_ok * $off)
        }

        var.update $backlog_copy {
          value = $backlog_copy + ((1 - $placed) * $job_ok)
        }

        var.update $slots_dropped {
          value = $slots_dropped + (1 - $job_ok)
        }
      }
    }

    var $people {
      value = []
    }

    foreach ($agents) {
      each as $a {
        var.update $t {
          value = $a.id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $off {
          value = ($agent_off|get:$k:null) ?? 0
        }

        var.update $n {
          value = ($agent_slots|get:$k:null) ?? 0
        }

        array.push $people {
          value = {
            agent_id        : $a.id
            name            : $a.name
            kind            : $a.kind
            left_off        : ($off == 1)
            slots_to_backlog: $n
          }
        }
      }
    }

    var $people_total {
      value = $agents|count
    }

    var $people_left_off {
      value = $people_total - $people_copy
    }

    var $row_estimate {
      value = 1 + $people_copy + $days_copy + $jobs_copy + $steps_copy + (($slots_copy + $slots_to_backlog + $backlog_copy) * 2)
    }

    var $counts {
      value = {
        people          : $people_copy
        people_left_off : $people_left_off
        days            : $days_copy
        jobs            : $jobs_copy
        jobs_left_out   : $jobs_left_out
        jobs_will_not   : $jobs_will_not
        jobs_cannot     : $jobs_cannot
        jobs_newer      : $jobs_newer
        steps           : $steps_copy
        slots           : $slots_copy
        slots_to_backlog: $slots_to_backlog
        backlog         : $backlog_copy
        slots_dropped   : $slots_dropped
        row_estimate    : $row_estimate
      }
    }

    var $source {
      value = {
        id         : $ws.id
        name       : $ws.name
        start_date : $ws.planning_window_start
        end_date   : $ws.planning_window_end
        length_days: $length_days
        is_archived: $ws.is_archived
      }
    }

    var $offer {
      value = {
        start_date    : $new_start
        end_date      : $new_end
        shift_days    : $shift_days
        weekdays_align: $weekdays_align
        name          : $candidate
        name_is_free  : $name_free
      }
    }
  }

  response = {
    reject_code: $reject_code
    reject_msg : $reject_msg
    source     : $source
    offer      : $offer
    counts     : $counts
    people     : $people
    jobs       : $jobs
  }
}
