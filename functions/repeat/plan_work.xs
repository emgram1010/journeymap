// REPEAT-1 stories 03-04 — What the repeat writes for jobs and slots, decided before anything is written. READ-ONLY. `plan` is repeat/build_plan's answer (the rule the preview shows): only jobs whose verdict is `repeat` are made, each pinned to its map's CURRENT published version (D-6), with its steps from jobs/tasks_from_version (never copied). Lines carry over unless the item is switched off or not in the new version's rates (named). A time window moves by shift_days. Attributes keep their values, marked source "repeat", entered now. Slots: each keeps its day and order, linked to the new job's matching step (matched by stage key + row key); a slot whose person was left off goes to the backlog; a slot whose step is gone is not made (named); a step new in this version goes to the backlog when its job had any slot. Lengths of job slots come from the new job's estimate (jobs/step_expected_minutes), so a length the planner changed last period is counted, not carried. Manual start times carry (D-7). Positions are dense 1..n per container by construction. EVERY BRANCH IS ON A LOOP ITEM'S OWN FIELD: lookups are recorded as fields in a first pass and acted on in a second (CLAUDE.md: a conditional reading a var updated in the same pass silently loses its writes). Map keys are prefixed so no key is ever empty.
function "repeat/plan_work" {
  input {
    int account_id
    int workspace_id
    json plan
    int shift_days
    text source_name? filters=trim
  }

  stack {
    var $shift_ms {
      value = $input.shift_days * 86400000
    }

    var $now_ms {
      value = now|to_int
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

    var $kk {
      value = ""
    }

    // Bare numbers inside a multi-line object literal turn into null and swallow the next key
    // (found live 2026-11-25): number values in such literals always come from these vars.
    var $zero {
      value = 0
    }

    var $one {
      value = 1
    }

    var $kv {
      value = null
    }

    var $left_out {
      value = []
    }

    var $rep_ids {
      value = [-1]
    }

    var $to_ver_ids {
      value = [-1]
    }

    var $repeats_of {
      value = {}
    }

    var $to_ver_of {
      value = {}
    }

    var $newer_of {
      value = {}
    }

    var $ver_no_of {
      value = {}
    }

    var $all_titles {
      value = {}
    }

    foreach ($input.plan.jobs) {
      each as $j {
        var.update $t {
          value = $j.id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $n {
          value = ($j.verdict == "repeat")|to_int
        }

        var.update $repeats_of {
          value = $repeats_of|set:$k:$n
        }

        var.update $to_ver_of {
          value = $to_ver_of|set:$k:$j.to_version_id
        }

        var.update $newer_of {
          value = $newer_of|set:$k:$j.uses_newer_version
        }

        var.update $ver_no_of {
          value = $ver_no_of|set:$k:$j.to_version_no
        }

        var.update $all_titles {
          value = $all_titles|set:$k:$j.title
        }
      }
    }

    foreach ($input.plan.jobs) {
      each as $j {
        conditional {
          if ($j.verdict == "repeat") {
            array.push $rep_ids {
              value = $j.id
            }

            array.push $to_ver_ids {
              value = $j.to_version_id
            }
          }
        }
      }
    }

    db.query work_item {
      where = $db.work_item.id in $rep_ids
      return = {type: "list"}
      output = ["id", "title", "attributes"]
      sort = {work_item.id: "asc"}
    } as $src_jobs

    db.query journey_map_version {
      where = $db.journey_map_version.id in $to_ver_ids
      return = {type: "list"}
      output = ["id", "snapshot"]
    } as $versions

    var $snap_of {
      value = {}
    }

    foreach ($versions) {
      each as $v {
        var.update $t {
          value = $v.id|to_text
        }

        var.update $k {
          value = "v:" ~ $t
        }

        var.update $snap_of {
          value = $snap_of|set:$k:$v.snapshot
        }
      }
    }

    // The new version's item set (E-EST-003's rule): an item with a rate in that version.
    db.query stage_rate {
      where = $db.stage_rate.journey_map_version_id in $to_ver_ids
      return = {type: "list"}
      output = ["journey_map_version_id", "quantity_key"]
    } as $rates

    var $rate_set {
      value = {}
    }

    foreach ($rates) {
      each as $r {
        var.update $t {
          value = $r.journey_map_version_id|to_text
        }

        var.update $k {
          value = "r:" ~ $t ~ "::" ~ $r.quantity_key
        }

        var.update $rate_set {
          value = $rate_set|set:$k:1
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "list"}
      sort = {planner_task.timeline_id: "asc", planner_task.seq: "asc", planner_task.id: "asc"}
    } as $slots

    var $slot_ids {
      value = [-1]
    }

    foreach ($slots) {
      each as $p {
        array.push $slot_ids {
          value = $p.id
        }
      }
    }

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.planner_task_id in $slot_ids
      return = {type: "list"}
      output = ["planner_task_id", "work_task_id"]
    } as $links

    var $slot_step {
      value = {}
    }

    var $linked_step_ids {
      value = [-1]
    }

    foreach ($links) {
      each as $l {
        var.update $t {
          value = $l.planner_task_id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $slot_step {
          value = $slot_step|set:$k:$l.work_task_id
        }

        array.push $linked_step_ids {
          value = $l.work_task_id
        }
      }
    }

    db.query work_task {
      where = ($db.work_task.work_item_id in $rep_ids) || ($db.work_task.id in $linked_step_ids)
      return = {type: "list"}
      output = ["id", "work_item_id", "stage_key", "lens_key"]
      sort = {work_task.id: "asc"}
    } as $src_steps

    var $step_job {
      value = {}
    }

    var $step_key_of {
      value = {}
    }

    var $src_step_set {
      value = {}
    }

    var $sk {
      value = ""
    }

    foreach ($src_steps) {
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

        var.update $t {
          value = $s.work_item_id|to_text
        }

        var.update $sk {
          value = "x:" ~ $t ~ "::" ~ $s.stage_key ~ "::" ~ $s.lens_key
        }

        var.update $step_key_of {
          value = $step_key_of|set:$k:$sk
        }

        var.update $src_step_set {
          value = $src_step_set|set:$sk:1
        }
      }
    }

    db.query work_item_line {
      where = $db.work_item_line.work_item_id in $rep_ids
      return = {type: "list"}
      output = ["id", "work_item_id", "item_type_id", "quantity"]
      sort = {work_item_line.id: "asc"}
    } as $src_lines

    var $item_ids {
      value = [-1]
    }

    foreach ($src_lines) {
      each as $sl {
        array.push $item_ids {
          value = $sl.item_type_id
        }
      }
    }

    db.query item_type {
      where = $db.item_type.id in $item_ids && $db.item_type.account_id == $input.account_id
      return = {type: "list"}
      output = ["id", "key", "label", "is_active"]
    } as $items

    var $item_key {
      value = {}
    }

    var $item_label {
      value = {}
    }

    var $item_active {
      value = {}
    }

    foreach ($items) {
      each as $it {
        var.update $t {
          value = $it.id|to_text
        }

        var.update $k {
          value = "i:" ~ $t
        }

        var.update $item_key {
          value = $item_key|set:$k:$it.key
        }

        var.update $item_label {
          value = $item_label|set:$k:$it.label
        }

        var.update $n {
          value = ($it.is_active == true)|to_int
        }

        var.update $item_active {
          value = $item_active|set:$k:$n
        }
      }
    }

    var $line_checks {
      value = []
    }

    var $ik {
      value = ""
    }

    var $qk {
      value = ""
    }

    var $ver {
      value = 0
    }

    var $active_n {
      value = 0
    }

    var $in_rates {
      value = 0
    }

    var $reason {
      value = ""
    }

    var $label {
      value = ""
    }

    var $ok_n {
      value = 0
    }

    foreach ($src_lines) {
      each as $sl {
        var.update $t {
          value = $sl.item_type_id|to_text
        }

        var.update $ik {
          value = "i:" ~ $t
        }

        var.update $qk {
          value = ($item_key|get:$ik:null) ?? ""
        }

        var.update $label {
          value = ($item_label|get:$ik:null) ?? ""
        }

        var.update $active_n {
          value = ($item_active|get:$ik:null) ?? 0
        }

        var.update $t {
          value = $sl.work_item_id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $ver {
          value = ($to_ver_of|get:$k:null) ?? 0
        }

        var.update $t {
          value = $ver|to_text
        }

        var.update $k {
          value = "r:" ~ $t ~ "::" ~ $qk
        }

        var.update $in_rates {
          value = ($rate_set|get:$k:null) ?? 0
        }

        var.update $reason {
          value = (($in_rates == 0) ? "item_not_in_version" : "")
        }

        var.update $reason {
          value = (($active_n == 0) ? "item_inactive" : $reason)
        }

        var.update $ok_n {
          value = $active_n * $in_rates
        }

        array.push $line_checks {
          value = {
            id          : $sl.id
            work_item_id: $sl.work_item_id
            item_type_id: $sl.item_type_id
            quantity    : $sl.quantity
            quantity_key: $qk
            label       : $label
            ok          : $ok_n
            reason      : $reason
          }
        }
      }
    }

    var $lines_ok {
      value = []
    }

    foreach ($line_checks) {
      each as $lc {
        conditional {
          if ($lc.ok == 1) {
            array.push $lines_ok {
              value = $lc
            }
          }
        }

        conditional {
          if ($lc.ok == 0) {
            array.push $left_out {
              value = {kind: "line", id: $lc.id, job_id: $lc.work_item_id, name: $lc.label, reason: $lc.reason}
            }
          }
        }
      }
    }

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id in $rep_ids
      return = {type: "list"}
    } as $windows

    var $win_of {
      value = {}
    }

    var $d_from {
      value = ""
    }

    var $d_to {
      value = ""
    }

    var $ms {
      value = 0
    }

    foreach ($windows) {
      each as $w {
        var.update $ms {
          value = ($w.start_date|to_timestamp) + $shift_ms
        }

        var.update $d_from {
          value = $ms|format_timestamp:"Y-m-d":"UTC"
        }

        var.update $ms {
          value = ($w.end_date|to_timestamp) + $shift_ms
        }

        var.update $d_to {
          value = $ms|format_timestamp:"Y-m-d":"UTC"
        }

        var.update $t {
          value = $w.work_item_id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $kv {
          value = {start_date: $d_from, start_time: $w.start_time, end_date: $d_to, end_time: $w.end_time, note: $w.note}
        }

        var.update $win_of {
          value = $win_of|set:$k:$kv
        }
      }
    }

    var $jobs_make {
      value = []
    }

    var $new_set {
      value = {}
    }

    var $minutes_of {
      value = {}
    }

    var $step_changes {
      value = []
    }

    var $snap {
      value = {}
    }

    var $attrs_in {
      value = {}
    }

    var $attrs {
      value = {}
    }

    var $a_val {
      value = null
    }

    var $jl {
      value = []
    }

    var $jl_est {
      value = []
    }

    var $win {
      value = null
    }

    var $jt {
      value = ""
    }

    var $is_new {
      value = 0
    }

    var $newer {
      value = false
    }

    var $ver_no {
      value = 0
    }

    var $task_rows {
      value = []
    }

    var $has_win {
      value = 0
    }

    var $sig {
      value = ""
    }

    var $job_prep {
      value = []
    }

    var $sig_set {
      value = {}
    }

    // Pass 1, per job: its own facts (version, window, attributes, lines) and a signature of what
    // decides its steps and lengths (version + lines). Jobs that share a signature share the work.
    foreach ($src_jobs) {
      each as $sj {
        var.update $jt {
          value = $sj.id|to_text
        }

        var.update $k {
          value = "j:" ~ $jt
        }

        var.update $ver {
          value = ($to_ver_of|get:$k:null) ?? 0
        }

        var.update $newer {
          value = ($newer_of|get:$k:null) ?? false
        }

        var.update $ver_no {
          value = ($ver_no_of|get:$k:null) ?? 0
        }

        var.update $win {
          value = $win_of|get:$k:null
        }

        // Attributes: same values, marked as coming from a repeat, entered now.
        var.update $attrs_in {
          value = $sj.attributes ?? {}
        }

        var.update $attrs {
          value = {}
        }

        foreach ($attrs_in|keys) {
          each as $ak {
            var.update $a_val {
              value = $attrs_in|get:$ak:null
            }

            var.update $kv {
              value = $a_val|get:"value":null
            }

            var.update $kv {
              value = {value: $kv, source: "repeat", entered_at: $now_ms}
            }

            var.update $attrs {
              value = $attrs|set:$ak:$kv
            }
          }
        }

        // This job's lines that carry over.
        var.update $jl {
          value = []
        }

        var.update $jl_est {
          value = []
        }

        foreach ($lines_ok) {
          each as $lo {
            conditional {
              if ($lo.work_item_id == $sj.id) {
                array.push $jl {
                  value = {item_type_id: $lo.item_type_id, quantity: $lo.quantity}
                }

                array.push $jl_est {
                  value = {quantity_key: $lo.quantity_key, quantity: $lo.quantity, flagged_quantity: 0}
                }
              }
            }
          }
        }

        var.update $t {
          value = $ver|to_text
        }

        var.update $sig {
          value = ("v:" ~ $t ~ "::" ~ ($jl_est|json_encode))|sha256
        }

        var.update $sig {
          value = "g:" ~ $sig
        }

        var.update $kv {
          value = {sig: $sig, ver: $ver, est_lines: $jl_est}
        }

        var.update $sig_set {
          value = $sig_set|set:$sig:$kv
        }

        var.update $has_win {
          value = ($win != null)|to_int
        }

        array.push $job_prep {
          value = {
            src_id    : $sj.id
            jt        : $jt
            title     : $sj.title
            attributes: $attrs
            version_id: $ver
            version_no: $ver_no
            newer     : $newer
            lines     : $jl
            sig       : $sig
            has_window: $has_win
            window    : $win
          }
        }
      }
    }

    // Pass 2, once per signature: the steps (jobs/tasks_from_version) and each step's expected
    // minutes (estimate/compute_estimate + jobs/step_expected_minutes). 50 jobs on one version with
    // no lines is one run, not fifty.
    var $sig_out {
      value = {}
    }

    var $rows {
      value = []
    }

    foreach ($sig_set|values) {
      each as $g {
        var.update $t {
          value = $g.ver|to_text
        }

        var.update $kk {
          value = "v:" ~ $t
        }

        var.update $snap {
          value = ($snap_of|get:$kk:null) ?? {}
        }

        function.run "jobs/tasks_from_version" {
          input = {snapshot: $snap}
        } as $tf

        function.run "estimate/compute_estimate" {
          input = {snapshot: $snap, lines: $g.est_lines}
        } as $est

        var.update $rows {
          value = []
        }

        foreach ($tf.tasks) {
          each as $tk {
            function.run "jobs/step_expected_minutes" {
              input = {snapshot: $snap, stage_key: $tk.stage_key, lens_key: $tk.lens_key, estimate: $est}
            } as $em

            array.push $rows {
              value = {stage_key: $tk.stage_key, lens_key: $tk.lens_key, minutes: $em.minutes}
            }
          }
        }

        var.update $kv {
          value = {tasks: $tf.tasks, rows: $rows}
        }

        var.update $kk {
          value = $g.sig
        }

        var.update $sig_out {
          value = $sig_out|set:$kk:$kv
        }
      }
    }

    // Pass 3, per job: its own step keys, lengths and changes from its signature's answer.
    var $g_out {
      value = {}
    }

    foreach ($job_prep) {
      each as $jp {
        var.update $kk {
          value = $jp.sig
        }

        var.update $g_out {
          value = $sig_out|get:$kk:null
        }

        var.update $task_rows {
          value = []
        }

        foreach ($g_out.rows) {
          each as $tr {
            var.update $sk {
              value = "x:" ~ $jp.jt ~ "::" ~ $tr.stage_key ~ "::" ~ $tr.lens_key
            }

            var.update $new_set {
              value = $new_set|set:$sk:1
            }

            var.update $minutes_of {
              value = $minutes_of|set:$sk:$tr.minutes
            }

            var.update $is_new {
              value = ($jp.newer|to_int) * (1 - (($src_step_set|get:$sk:null) ?? 0))
            }

            array.push $task_rows {
              value = {stage_key: $tr.stage_key, lens_key: $tr.lens_key, key: $sk, minutes: $tr.minutes, is_new: $is_new}
            }

            array.push $step_changes {
              value = {job_id: $jp.src_id, title: $jp.title, stage_key: $tr.stage_key, lens_key: $tr.lens_key, change: "added", keep: $is_new}
            }
          }
        }

        array.push $jobs_make {
          value = {
            src_id    : $jp.src_id
            title     : $jp.title
            attributes: $jp.attributes
            version_id: $jp.version_id
            version_no: $jp.version_no
            newer     : $jp.newer
            tasks     : $g_out.tasks
            task_rows : $task_rows
            lines     : $jp.lines
            has_window: $jp.has_window
            window    : $jp.window
          }
        }
      }
    }

    // Steps of a repeated job that the new version no longer has.
    var $job_title {
      value = {}
    }

    foreach ($src_jobs) {
      each as $sj {
        var.update $t {
          value = $sj.id|to_text
        }

        var.update $kk {
          value = "j:" ~ $t
        }

        var.update $job_title {
          value = $job_title|set:$kk:$sj.title
        }
      }
    }

    foreach ($src_steps) {
      each as $s {
        var.update $t {
          value = $s.work_item_id|to_text
        }

        var.update $k {
          value = "j:" ~ $t
        }

        var.update $n {
          value = ($repeats_of|get:$k:null) ?? 0
        }

        var.update $sk {
          value = "x:" ~ $t ~ "::" ~ $s.stage_key ~ "::" ~ $s.lens_key
        }

        var.update $newer {
          value = ($newer_of|get:$k:null) ?? false
        }

        var.update $is_new {
          value = $n * ($newer|to_int) * (1 - (($new_set|get:$sk:null) ?? 0))
        }

        var.update $label {
          value = ($job_title|get:$k:null) ?? ""
        }

        array.push $step_changes {
          value = {job_id: $s.work_item_id, title: $label, stage_key: $s.stage_key, lens_key: $s.lens_key, change: "gone", keep: $is_new}
        }
      }
    }

    var $changes {
      value = []
    }

    foreach ($step_changes) {
      each as $sc {
        conditional {
          if ($sc.keep == 1) {
            array.push $changes {
              value = {job_id: $sc.job_id, title: $sc.title, stage_key: $sc.stage_key, lens_key: $sc.lens_key, change: $sc.change}
            }
          }
        }
      }
    }

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id", "agent_id"]
    } as $tls

    var $tl_agent {
      value = {}
    }

    foreach ($tls) {
      each as $tl {
        var.update $t {
          value = $tl.id|to_text
        }

        var.update $kk {
          value = "t:" ~ $t
        }

        var.update $kv {
          value = ($tl.agent_id ?? 0)
        }

        var.update $tl_agent {
          value = $tl_agent|set:$kk:$kv
        }
      }
    }

    var $agent_off {
      value = {}
    }

    var $agent_name {
      value = {}
    }

    foreach ($input.plan.people) {
      each as $pp {
        var.update $t {
          value = $pp.agent_id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $n {
          value = $pp.left_off|to_int
        }

        var.update $agent_off {
          value = $agent_off|set:$k:$n
        }

        var.update $agent_name {
          value = $agent_name|set:$k:$pp.name
        }
      }
    }

    db.query planner_task_start_override {
      where = $db.planner_task_start_override.planner_task_id in $slot_ids
      return = {type: "list"}
      output = ["planner_task_id", "start_time", "reason"]
    } as $overrides

    var $ov_of {
      value = {}
    }

    foreach ($overrides) {
      each as $ov {
        var.update $t {
          value = $ov.planner_task_id|to_text
        }

        var.update $kk {
          value = "p:" ~ $t
        }

        var.update $kv {
          value = ($ov.start_time ?? "")
        }

        var.update $ov_of {
          value = $ov_of|set:$kk:$kv
        }
      }
    }

    var $counter {
      value = {}
    }

    var $job_had_slot {
      value = {}
    }

    var $slot_checks {
      value = []
    }

    var $placed {
      value = 0
    }

    var $owner {
      value = 0
    }

    var $owner_off {
      value = 0
    }

    var $asg {
      value = 0
    }

    var $asg_off {
      value = 0
    }

    var $step {
      value = 0
    }

    var $linked {
      value = 0
    }

    var $sjob {
      value = 0
    }

    var $job_rep {
      value = 0
    }

    var $exists_new {
      value = 0
    }

    var $keep {
      value = 0
    }

    var $to_backlog {
      value = 0
    }

    var $dest {
      value = ""
    }

    var $pos {
      value = 0
    }

    var $minutes {
      value = 0
    }

    var $tweaked {
      value = 0
    }

    var $start_time {
      value = ""
    }

    var $who {
      value = ""
    }

    var $why {
      value = ""
    }

    var $why_text {
      value = ""
    }

    var $drop_reason {
      value = ""
    }

    var $tl_t {
      value = ""
    }

    var $on_day {
      value = 0
    }

    var $s_title {
      value = ""
    }

    var $s_notes {
      value = ""
    }

    var $s_status {
      value = ""
    }

    var $s_reason {
      value = ""
    }

    var $s_label {
      value = ""
    }

    var $off_who {
      value = 0
    }

    var $tb_by {
      value = {}
    }

    foreach ($slots) {
      each as $p {
        var.update $tl_t {
          value = ($p.timeline_id ?? 0)|to_text
        }

        var.update $placed {
          value = (($p.timeline_id ?? 0) != 0)|to_int
        }

        var.update $kk {
          value = "t:" ~ $tl_t
        }

        var.update $owner {
          value = ($tl_agent|get:$kk:null) ?? 0
        }

        var.update $t {
          value = $owner|to_text
        }

        var.update $kk {
          value = "a:" ~ $t
        }

        var.update $owner_off {
          value = ($agent_off|get:$kk:null) ?? $placed
        }

        var.update $kk {
          value = "a:" ~ $t
        }

        var.update $who {
          value = ($agent_name|get:$kk:null) ?? ""
        }

        var.update $asg {
          value = $p.assignee_agent_id ?? 0
        }

        var.update $t {
          value = $asg|to_text
        }

        var.update $kk {
          value = "a:" ~ $t
        }

        var.update $asg_off {
          value = ($agent_off|get:$kk:null) ?? 0
        }

        var.update $kk {
          value = "a:" ~ $t
        }

        var.update $who {
          value = (($owner_off == 1) ? $who : (($agent_name|get:$kk:null) ?? ""))
        }

        var.update $t {
          value = $p.id|to_text
        }

        var.update $kk {
          value = "p:" ~ $t
        }

        var.update $step {
          value = ($slot_step|get:$kk:null) ?? 0
        }

        var.update $kk {
          value = "p:" ~ $t
        }

        var.update $start_time {
          value = ($ov_of|get:$kk:null) ?? ""
        }

        var.update $linked {
          value = ($step != 0)|to_int
        }

        var.update $t {
          value = $step|to_text
        }

        var.update $kk {
          value = "s:" ~ $t
        }

        var.update $sjob {
          value = ($step_job|get:$kk:null) ?? 0
        }

        var.update $kk {
          value = "s:" ~ $t
        }

        var.update $sk {
          value = ($step_key_of|get:$kk:null) ?? "x:none"
        }

        var.update $t {
          value = $sjob|to_text
        }

        var.update $kk {
          value = "j:" ~ $t
        }

        var.update $job_had_slot {
          value = $job_had_slot|set:$kk:1
        }

        var.update $kk {
          value = "j:" ~ $t
        }

        var.update $n {
          value = ($repeats_of|get:$kk:null) ?? 0
        }

        var.update $job_rep {
          value = (($linked == 0) ? 1 : $n)
        }

        var.update $n {
          value = ($new_set|get:$sk:null) ?? 0
        }

        var.update $exists_new {
          value = (($linked == 0) ? 1 : $n)
        }

        var.update $keep {
          value = $job_rep * $exists_new
        }

        var.update $to_backlog {
          value = $placed * ((($owner_off + $asg_off) > 0)|to_int)
        }

        var.update $dest {
          value = (($placed == 1 && $to_backlog == 0) ? ("t:" ~ $tl_t) : "t:0")
        }

        var.update $dest {
          value = (($keep == 0) ? "drop" : $dest)
        }

        var.update $pos {
          value = (($counter|get:$dest:null) ?? 0) + 1
        }

        var.update $counter {
          value = $counter|set:$dest:$pos
        }

        var.update $minutes {
          value = (($linked == 1) ? (($minutes_of|get:$sk:null) ?? 30) : $p.duration_minutes)
        }

        var.update $tweaked {
          value = $linked * ((($p.tweak_reason ?? "") != "")|to_int)
        }

        var.update $why {
          value = (($to_backlog == 1) ? "person_left_off" : "copied")
        }

        var.update $why_text {
          value = (($to_backlog == 1) ? ($who ~ " is no longer on the plan") : ("copied from " ~ $input.source_name))
        }

        var.update $drop_reason {
          value = (($job_rep == 0) ? "job_not_repeated" : "step_gone")
        }

        var.update $on_day {
          value = (($dest != "t:0") && ($dest != "drop"))|to_int
        }

        var.update $s_title {
          value = $p.title ?? ""
        }

        var.update $t {
          value = $sjob|to_text
        }

        var.update $kk {
          value = "j:" ~ $t
        }

        var.update $s_label {
          value = (($s_title != "") ? $s_title : (($all_titles|get:$kk:null) ?? ""))
        }

        // Whose absence sent this slot to the backlog (the day's person first, else the assignee).
        var.update $off_who {
          value = (($owner_off == 1) ? $owner : $asg)
        }

        var.update $t {
          value = $off_who|to_text
        }

        var.update $kk {
          value = "a:" ~ $t
        }

        var.update $n {
          value = (($tb_by|get:$kk:null) ?? 0) + ($keep * $to_backlog)
        }

        var.update $tb_by {
          value = $tb_by|set:$kk:$n
        }

        var.update $s_notes {
          value = $p.notes ?? ""
        }

        var.update $s_status {
          value = $p.status ?? "planned"
        }

        var.update $s_reason {
          value = $p.needs_info_reason ?? ""
        }

        array.push $slot_checks {
          value = {
            src_id           : $p.id
            keep             : $keep
            dest             : $dest
            pos              : $pos
            on_day           : $on_day
            linked           : $linked
            src_job_id       : $sjob
            step_key         : $sk
            title            : $s_title
            label            : $s_label
            notes            : $s_notes
            status           : $s_status
            needs_info_reason: $s_reason
            duration_minutes : $minutes
            src_minutes      : $p.duration_minutes
            tweaked          : $tweaked
            assignee_src     : $asg
            start_time       : $start_time
            to_backlog       : $to_backlog
            review_code      : $why
            review_text      : $why_text
            drop_reason      : $drop_reason
          }
        }
      }
    }

    // A step new in this version goes to the backlog when its job was on the schedule at all.
    var $had {
      value = 0
    }

    var $want {
      value = 0
    }

    foreach ($jobs_make) {
      each as $jm {
        var.update $t {
          value = $jm.src_id|to_text
        }

        var.update $kk {
          value = "j:" ~ $t
        }

        var.update $had {
          value = ($job_had_slot|get:$kk:null) ?? 0
        }

        foreach ($jm.task_rows) {
          each as $tr {
            var.update $want {
              value = $tr.is_new * $had
            }

            var.update $pos {
              value = (($counter|get:"t:0":null) ?? 0) + $want
            }

            var.update $counter {
              value = $counter|set:"t:0":$pos
            }

            array.push $slot_checks {
              value = {
                src_id           : $zero
                keep             : $want
                dest             : "t:0"
                pos              : $pos
                on_day           : $zero
                linked           : $one
                src_job_id       : $jm.src_id
                step_key         : $tr.key
                title            : ""
                label            : $jm.title
                notes            : ""
                status           : "planned"
                needs_info_reason: ""
                duration_minutes : $tr.minutes
                src_minutes      : $tr.minutes
                tweaked          : $zero
                assignee_src     : $zero
                start_time       : ""
                to_backlog       : $zero
                review_code      : "new_step"
                review_text      : "new step in this version"
                drop_reason      : "not_needed"
              }
            }
          }
        }
      }
    }

    var $slots_make {
      value = []
    }

    var $placed_n {
      value = 0
    }

    var $backlog_n {
      value = 0
    }

    var $to_backlog_n {
      value = 0
    }

    var $new_step_n {
      value = 0
    }

    var $dropped_n {
      value = 0
    }

    var $tweaked_n {
      value = 0
    }

    var $starts_n {
      value = 0
    }

    foreach ($slot_checks) {
      each as $sc {
        var.update $placed_n {
          value = $placed_n + ($sc.keep * $sc.on_day)
        }

        var.update $backlog_n {
          value = $backlog_n + ($sc.keep * (1 - $sc.on_day))
        }

        var.update $to_backlog_n {
          value = $to_backlog_n + ($sc.keep * $sc.to_backlog)
        }

        var.update $new_step_n {
          value = $new_step_n + ($sc.keep * (($sc.review_code == "new_step")|to_int))
        }

        var.update $dropped_n {
          value = $dropped_n + ((1 - $sc.keep) * (($sc.src_id != 0)|to_int))
        }

        var.update $tweaked_n {
          value = $tweaked_n + ($sc.keep * $sc.tweaked)
        }

        var.update $starts_n {
          value = $starts_n + ($sc.keep * $sc.on_day * (($sc.start_time != "")|to_int))
        }

        conditional {
          if ($sc.keep == 1) {
            array.push $slots_make {
              value = $sc
            }
          }
        }

        conditional {
          if ($sc.keep == 0 && $sc.src_id != 0) {
            array.push $left_out {
              value = {kind: "slot", id: $sc.src_id, job_id: $sc.src_job_id, name: $sc.label, reason: $sc.drop_reason}
            }
          }
        }
      }
    }

    // REPEAT-2: the planner chose not to carry assignments (or people, which forces it): no slot is
    // made, none is counted, and no slot is reported as "left out" (it was a choice, not a loss).
    // Decided by repeat/build_plan and read from the plan, so the preview and the copy agree. These
    // conditions read a value set before any loop, and sit outside every loop.
    var $choices {
      value = $input.plan.choices ?? {}
    }

    var $no_slots {
      value = ($choices|get:"skip_assignments":false) == true
    }

    var $left_no_slots {
      value = []
    }

    foreach ($left_out) {
      each as $lo {
        conditional {
          if ($lo.kind != "slot") {
            array.push $left_no_slots {
              value = $lo
            }
          }
        }
      }
    }

    conditional {
      if ($no_slots == true) {
        var.update $slots_make {
          value = []
        }

        var.update $left_out {
          value = $left_no_slots
        }

        var.update $tb_by {
          value = {}
        }

        var.update $placed_n {
          value = 0
        }

        var.update $backlog_n {
          value = 0
        }

        var.update $to_backlog_n {
          value = 0
        }

        var.update $new_step_n {
          value = 0
        }

        var.update $dropped_n {
          value = 0
        }

        var.update $tweaked_n {
          value = 0
        }

        var.update $starts_n {
          value = 0
        }
      }
    }

    var $job_counts {
      value = {
        repeated   : ($jobs_make|count)
        newer      : ($input.plan.counts.jobs_newer)
        left_out   : ($input.plan.counts.jobs_left_out)
        will_not   : ($input.plan.counts.jobs_will_not)
        cannot     : ($input.plan.counts.jobs_cannot)
        lines      : ($lines_ok|count)
        lines_left : (($line_checks|count) - ($lines_ok|count))
        windows    : ($windows|count)
      }
    }

    var $slot_counts {
      value = {
        placed       : $placed_n
        backlog      : $backlog_n
        to_backlog   : $to_backlog_n
        new_steps    : $new_step_n
        not_created  : $dropped_n
        lengths_reset: $tweaked_n
        start_times  : $starts_n
      }
    }
  }

  response = {
    jobs_make          : $jobs_make
    slots_make         : $slots_make
    step_changes       : $changes
    left_out           : $left_out
    job_counts         : $job_counts
    slot_counts        : $slot_counts
    to_backlog_by_agent: $tb_by
  }
}
