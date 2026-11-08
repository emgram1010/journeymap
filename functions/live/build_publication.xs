// LIVE-1 (US-LIVE-1-02) — Build one timeline's publishable items,
// its blockers, and the canonical string its hash comes from.
//
// The backend twin of `webapp/protype-2/src/liveModel.ts`. Read-only:
// it decides nothing and writes nothing, so the publish endpoint can
// call it to PREVIEW blockers as well as to publish.
//
// EFFECTIVE ASSIGNEE is the slot's own override if set, otherwise the
// timeline's agent — the same rule PLN-7's derive_tasks uses. A step
// with neither is a blocker, not a silent gap.
//
// NAMES IN THE NO_LOGIN MESSAGE ARE DE-DUPLICATED. Four steps assigned
// to one person without a login is one problem, and reading
// "Rhea, Rhea, Rhea, Rhea doesn't have a login" makes the tool look
// broken. The count still reflects the steps; the names do not.
//
// ⚠️ THE LINKS ARE GATHERED BY NESTED LOOP, NOT BY MAP LOOKUP. The
// first version built a slot→work_task map and read it with
// `|get:$key:[]`, which returns **null** on a miss because `|get`
// with a variable key ignores its default (CLAUDE.md) — and
// `array.push` onto null fails with "Variable is not an array". The
// inner loop below branches only on loop-item fields, which is the
// shape that works.
//
// The agent maps are pre-seeded with key "0" so an unassigned slot
// resolves to a real value instead of null, for the same reason.
//
// The canonical string follows `canonicalizePublication` exactly,
// including the escape order (backslash first, then pipe, then strip
// CR, then newline) — same as PUB-1's canonical_hash. Get that order
// wrong and the two sides disagree only on values containing a
// backslash, which is the kind of bug that surfaces months later.
function "live/build_publication" {
  input {
    int timeline_id filters=min:1
  }

  stack {
    db.get planner_timeline {
      field_name = "id"
      field_value = $input.timeline_id
    } as $timeline

    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id
      sort = {planner_task.seq: "asc", planner_task.id: "asc"}
      return = {type: "list"}
    } as $slots

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $timeline.workspace_id
      return = {type: "list"}
    } as $agents

    var $key {
      value = ""
    }

    // Seeded with "0" = nobody, so an unassigned slot never hits a
    // missing key and gets null back.
    var $agent_name {
      value = {}|set:"0":""
    }

    var $agent_login {
      value = {}|set:"0":0
    }

    foreach ($agents) {
      each as $a {
        var.update $key {
          value = $a.id|to_text
        }

        var.update $agent_name {
          value = $agent_name|set:$key:$a.name
        }

        var.update $agent_login {
          value = $agent_login|set:$key:$a.user_id
        }
      }
    }

    db.query planner_task_work_task {
      return = {type: "list"}
    } as $all_links

    // --- TW-1: each slot's job and that job's time window -----------
    // One query for the day's work tasks and one for their windows, then
    // pre-seeded maps (a `|get` with a variable key drops its default, so
    // every key read below is seeded first; "k:0" covers an unlinked slot).
    var $day_wt_ids {
      value = [-1]
    }

    foreach ($slots) {
      each as $s {
        foreach ($all_links) {
          each as $l {
            conditional {
              if ($l.planner_task_id == $s.id) {
                array.push $day_wt_ids {
                  value = $l.work_task_id
                }
              }
            }
          }
        }
      }
    }

    db.query work_task {
      where = $db.work_task.id in $day_wt_ids
      return = {type: "list"}
    } as $day_tasks

    var $no_window {
      value = {start_date: "", start_time: "", end_date: "", end_time: "", note: ""}
    }

    var $job_of_wt {
      value = {}
    }

    var $win_by_job {
      value = {}|set:"k:0":$no_window
    }

    var $day_job_ids {
      value = [-1]
    }

    var $wkey {
      value = ""
    }

    var $jkey {
      value = ""
    }

    foreach ($day_tasks) {
      each as $dt {
        var.update $wkey {
          value = "k:" ~ ($dt.id|to_text)
        }

        var.update $jkey {
          value = "k:" ~ ($dt.work_item_id|to_text)
        }

        var.update $job_of_wt {
          value = $job_of_wt|set:$wkey:$dt.work_item_id
        }

        var.update $win_by_job {
          value = $win_by_job|set:$jkey:$no_window
        }

        array.push $day_job_ids {
          value = $dt.work_item_id
        }
      }
    }

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id in $day_job_ids
      return = {type: "list"}
    } as $day_windows

    foreach ($day_windows) {
      each as $dw {
        var.update $jkey {
          value = "k:" ~ ($dw.work_item_id|to_text)
        }

        var $wobj {
          value = {start_date: $dw.start_date, start_time: $dw.start_time, end_date: $dw.end_date, end_time: $dw.end_time, note: ($dw.note ?? "")}
        }

        var.update $win_by_job {
          value = $win_by_job|set:$jkey:$wobj
        }
      }
    }

    // --- SCHED-2: each slot's manual start, frozen into the item --------
    // Pre-seeded with "" per slot so the read below never misses.
    var $slot_ids {
      value = [-1]
    }

    var $ov_by_slot {
      value = {}
    }

    var $skey {
      value = ""
    }

    foreach ($slots) {
      each as $s0 {
        array.push $slot_ids {
          value = $s0.id
        }

        var.update $skey {
          value = "k:" ~ ($s0.id|to_text)
        }

        var.update $ov_by_slot {
          value = $ov_by_slot|set:$skey:""
        }
      }
    }

    db.query planner_task_start_override {
      where = $db.planner_task_start_override.planner_task_id in $slot_ids
      return = {type: "list"}
    } as $day_overrides

    foreach ($day_overrides) {
      each as $ovr {
        var.update $skey {
          value = "k:" ~ ($ovr.planner_task_id|to_text)
        }

        var.update $ov_by_slot {
          value = $ov_by_slot|set:$skey:$ovr.start_time
        }
      }
    }

    var $sov {
      value = ""
    }

    var $items {
      value = []
    }

    var $job_id {
      value = 0
    }

    var $win {
      value = null
    }

    var $tw_item {
      value = null
    }

    var $eff {
      value = 0
    }

    var $login {
      value = 0
    }

    var $name {
      value = ""
    }

    var $wt_ids {
      value = []
    }

    foreach ($slots) {
      each as $s {
        var.update $eff {
          value = $timeline.agent_id
        }

        conditional {
          if ($s.assignee_agent_id != 0) {
            var.update $eff {
              value = $s.assignee_agent_id
            }
          }
        }

        var.update $key {
          value = $eff|to_text
        }

        var.update $login {
          value = $agent_login|get:$key:0
        }

        var.update $name {
          value = $agent_name|get:$key:""
        }

        // Fresh list per slot, filled by comparing two loop items.
        var.update $wt_ids {
          value = []
        }

        var.update $job_id {
          value = 0
        }

        foreach ($all_links) {
          each as $l {
            conditional {
              if ($l.planner_task_id == $s.id) {
                array.push $wt_ids {
                  value = $l.work_task_id
                }

                var.update $wkey {
                  value = "k:" ~ ($l.work_task_id|to_text)
                }

                var.update $job_id {
                  value = ($job_of_wt|get:$wkey:0) ?? 0
                }
              }
            }
          }
        }

        var.update $jkey {
          value = "k:" ~ ($job_id|to_text)
        }

        var.update $win {
          value = $win_by_job|get:$jkey:$no_window
        }

        // A ternary in a var, not a `conditional`: a conditional whose
        // condition reads a var updated in this same iteration loses its writes.
        var.update $tw_item {
          value = (($win.start_date != "") ? $win : null)
        }

        var.update $skey {
          value = "k:" ~ ($s.id|to_text)
        }

        var.update $sov {
          value = $ov_by_slot|get:$skey:""
        }

        array.push $items {
          value = {
            item_ref          : ("pt-" ~ ($s.id|to_text))
            planner_task_id   : $s.id
            seq               : $s.seq
            scheduled_minutes : $s.duration_minutes
            assignee_agent_id : $eff
            assignee_name     : $name
            assignee_has_login: ($login != 0)
            status            : $s.status
            work_task_ids     : $wt_ids
            title             : $s.title
            work_item_id      : $job_id
            time_window       : $tw_item
            start_override    : $sov
          }
        }
      }
    }

    // --- blockers ---------------------------------------------------
    var $blockers {
      value = []
    }

    var $no_assignee {
      value = 0
    }

    var $needs_info {
      value = 0
    }

    var $no_login_count {
      value = 0
    }

    // Two passes to de-duplicate the names: pass 1 records whether
    // each name was already seen as a FIELD, pass 2 branches on that
    // field of the loop item.
    var $seen_names {
      value = {}
    }

    var $name_checks {
      value = []
    }

    foreach ($items) {
      each as $i {
        conditional {
          if ($i.assignee_agent_id == 0) {
            var.update $no_assignee {
              value = $no_assignee + 1
            }
          }
        }

        conditional {
          if ($i.status == "needs_info") {
            var.update $needs_info {
              value = $needs_info + 1
            }
          }
        }

        conditional {
          if ($i.assignee_agent_id != 0 && $i.assignee_has_login == false) {
            var.update $no_login_count {
              value = $no_login_count + 1
            }

            array.push $name_checks {
              value = {name: $i.assignee_name, seen_before: ($seen_names|get:$i.assignee_name:null)}
            }

            var.update $seen_names {
              value = $seen_names|set:$i.assignee_name:1
            }
          }
        }
      }
    }

    var $no_login_names {
      value = []
    }

    foreach ($name_checks) {
      each as $n {
        conditional {
          if ($n.seen_before == null) {
            array.push $no_login_names {
              value = $n.name
            }
          }
        }
      }
    }

    conditional {
      if (($items|count) == 0) {
        array.push $blockers {
          value = {code: "EMPTY", count: 0, message: "There's nothing on this timeline to publish."}
        }
      }
    }

    conditional {
      if ($no_assignee > 0) {
        array.push $blockers {
          value = {code: "NO_ASSIGNEE", count: $no_assignee, message: ($no_assignee ~ " step(s) don't have a person assigned.")}
        }
      }
    }

    conditional {
      if ($needs_info > 0) {
        array.push $blockers {
          value = {code: "NEEDS_INFO", count: $needs_info, message: ($needs_info ~ " step(s) are marked 'needs info'. Complete them first.")}
        }
      }
    }

    var $joined_names {
      value = $no_login_names|join:", "
    }

    conditional {
      if ($no_login_count > 0) {
        array.push $blockers {
          value = {code: "NO_LOGIN", count: $no_login_count, message: ($joined_names ~ " doesn't have a login yet, so they can't see their work.")}
        }
      }
    }

    // --- canonical string and hash ----------------------------------
    // TW-1: v2 = the v1 line plus the job's window (start date, start
    // time, end date, end time, note); no window = five empty fields.
    // Twin: liveModel.ts::canonicalizePublicationV2. Pinned on both sides:
    // the liveModel.test.ts fixture hashes to
    // c0d594020ab9716cd40b30043268d79a9fa0f3f7e1816f16625a98bd5aa7093e.
    // Stored v1 rows are never re-hashed.
    //
    // SCHED-2: v3 = the v2 line plus the slot's start override ("HH:MM",
    // regex-validated on write, so it needs no escaping; "" = computed).
    // Twin: liveModel.ts::canonicalizePublicationV3, fixture hash
    // e80d17c578404311a100144b574bb9bb8bbe60f0c2ec4092da36be403f3f67ec.
    // Stored v1/v2 rows are never re-hashed.
    var $canonical {
      value = "publication|v3\n"
    }

    var $cw {
      value = null
    }

    var $esc_note {
      value = ""
    }

    var $esc_ref {
      value = ""
    }

    var $esc_title {
      value = ""
    }

    var $wt_joined {
      value = ""
    }

    var $line {
      value = ""
    }

    foreach ($items) {
      each as $i {
        var.update $esc_ref {
          value = ($i.item_ref ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $esc_title {
          value = ($i.title ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $wt_joined {
          value = $i.work_task_ids|join:","
        }

        var.update $jkey {
          value = "k:" ~ ($i.work_item_id|to_text)
        }

        var.update $cw {
          value = $win_by_job|get:$jkey:$no_window
        }

        var.update $esc_note {
          value = ($cw.note ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $line {
          value = "item|" ~ $esc_ref ~ "|" ~ ($i.seq|to_text) ~ "|" ~ ($i.scheduled_minutes|to_text) ~ "|" ~ ($i.assignee_agent_id|to_text) ~ "|" ~ $esc_title ~ "|" ~ $wt_joined ~ "|" ~ $cw.start_date ~ "|" ~ $cw.start_time ~ "|" ~ $cw.end_date ~ "|" ~ $cw.end_time ~ "|" ~ $esc_note ~ "|" ~ ($i.start_override ?? "") ~ "\n"
        }

        var.update $canonical {
          value = $canonical ~ $line
        }
      }
    }

    var $hash {
      value = $canonical|sha256
    }
  }

  response = {
    timeline_id  : $input.timeline_id
    items        : $items
    item_count   : ($items|count)
    blockers     : $blockers
    can_publish  : (($blockers|count) == 0)
    canonical        : $canonical
    canonical_version: "publication|v3"
    snapshot_hash    : $hash
  }
}
