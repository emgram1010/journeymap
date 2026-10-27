// EXC-1 (US-EXC-1-07) — Health page "Exceptions" panel. Plain facts for
// the product manager, same spirit as ops/estimates_panel:
//
//   open_children   every child job started by an exception that is not
//                   completed or cancelled — parent, step, reason, linked
//                   map, age in days, how many items left, depth — oldest
//                   first, because the oldest is the one being forgotten;
//   by_stage /      exception counts for the last 30 days (PRD §9:
//   by_reason       "exception frequency by stage and reason");
//   needs_attention children whose PARENT was cancelled (D-7: cancelling
//                   a parent never cancels its children — a person
//                   decides); exception links whose target map has never
//                   been published; spawn refusals in the last 7 days by
//                   code.
//
// READ-ONLY, LOGS NOTHING (it is polled by the Health page — the OBS-1
// heartbeat lesson). Whole-table reads are fine at MVP volumes; every
// lookup is one `in` query, never one per row.
//
// No conditional reads a var updated in the same loop iteration
// (CLAUDE.md): per-row facts are computed into FIELDS first, and the
// filtering loops branch only on their loop item. Map keys are prefixed
// ("j:", "m:", "v:") so a lookup key is never "" (`|get:""` returns the
// whole object).
function "ops/exceptions_panel" {
  input {
  }

  stack {
    var $now_ms {
      value = now|to_int
    }

    var $day_ms {
      value = 86400000
    }

    var $cutoff_30d {
      value = $now_ms - (30 * $day_ms)
    }

    var $since_7d {
      value = now|transform_timestamp:"7 days ago":"UTC"
    }

    db.query work_item_exception {
      sort = {work_item_exception.created_at: "asc"}
      return = {type: "list"}
    } as $rows

    // ── One query each for the jobs, maps and versions the rows mention ──
    var $job_ids {
      value = [-1]
    }

    var $map_ids {
      value = [-1]
    }

    foreach ($rows) {
      each as $r {
        array.push $job_ids {
          value = $r.parent_work_item_id
        }

        array.push $job_ids {
          value = $r.child_work_item_id
        }

        array.push $map_ids {
          value = $r.target_map_id
        }
      }
    }

    db.query work_item {
      where = $db.work_item.id in $job_ids
      return = {type: "list"}
    } as $jobs

    var $job_by_id {
      value = {}
    }

    var $version_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j {
        var $j_key {
          value = "j:" ~ ($j.id|to_text)
        }

        var.update $job_by_id {
          value = $job_by_id|set:$j_key:$j
        }

        array.push $version_ids {
          value = $j.journey_map_version_id
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $versions

    var $stage_label_by_key {
      value = {}
    }

    foreach ($versions) {
      each as $v {
        foreach ($v.snapshot.stages ?? []) {
          each as $vs {
            var $vs_key {
              value = "v:" ~ ($v.id|to_text) ~ "::" ~ $vs.key
            }

            var.update $stage_label_by_key {
              value = $stage_label_by_key|set:$vs_key:($vs.label ?? $vs.key)
            }
          }
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $map_ids
      return = {type: "list"}
    } as $maps

    var $map_title_by_id {
      value = {}
    }

    foreach ($maps) {
      each as $m {
        var $m_key {
          value = "m:" ~ ($m.id|to_text)
        }

        var.update $map_title_by_id {
          value = $map_title_by_id|set:$m_key:$m.title
        }
      }
    }

    // ── Pass 1: every fact about every row, as fields ──────────────────
    var $facts {
      value = []
    }

    foreach ($rows) {
      each as $r2 {
        var $child_key {
          value = "j:" ~ ($r2.child_work_item_id|to_text)
        }

        var $parent_key {
          value = "j:" ~ ($r2.parent_work_item_id|to_text)
        }

        var $child_job {
          value = $job_by_id|get:$child_key:null
        }

        var $parent_job {
          value = $job_by_id|get:$parent_key:null
        }

        var $child_status {
          value = $child_job.status ?? "missing"
        }

        var $parent_status {
          value = $parent_job.status ?? "missing"
        }

        var $label_key {
          value = "v:" ~ (($parent_job.journey_map_version_id ?? 0)|to_text) ~ "::" ~ $r2.stage_key
        }

        var $target_key {
          value = "m:" ~ ($r2.target_map_id|to_text)
        }

        var $moved_count {
          value = 0
        }

        foreach ($r2.moved_lines ?? []) {
          each as $ml {
            var.update $moved_count {
              value = $moved_count + ($ml.quantity ?? 0)
            }
          }
        }

        var $grandparent_id {
          value = $parent_job.parent_work_item_id ?? 0
        }

        var $age_days {
          value = (($now_ms - $r2.created_at) / $day_ms)|floor
        }

        var $stage_label {
          value = ($stage_label_by_key|get:$label_key:null) ?? $r2.stage_key
        }

        var $target_title {
          value = ($map_title_by_id|get:$target_key:null) ?? "a linked map"
        }

        var $depth {
          value = 1 + (($grandparent_id != 0)|to_int)
        }

        array.push $facts {
          value = {
            exception_id       : $r2.id
            account_id         : $r2.account_id
            created_at         : $r2.created_at
            age_days           : $age_days
            recent             : ($r2.created_at >= $cutoff_30d)
            is_open            : ($child_status != "completed" && $child_status != "cancelled")
            parent_cancelled   : ($parent_status == "cancelled")
            child_work_item_id : $r2.child_work_item_id
            child_title        : $child_job.title ?? ""
            child_status       : $child_status
            parent_work_item_id: $r2.parent_work_item_id
            parent_title       : $parent_job.title ?? ""
            parent_status      : $parent_status
            stage_key          : $r2.stage_key
            stage_label        : $stage_label
            reason_code        : $r2.reason_code
            note               : $r2.note
            target_map_id      : $r2.target_map_id
            target_map_title   : $target_title
            moved_count        : $moved_count
            depth              : $depth
            source             : $r2.source
          }
        }
      }
    }

    // ── Pass 2: filter and tally, branching only on loop-item fields ───
    var $open_children {
      value = []
    }

    var $parent_cancelled {
      value = []
    }

    var $stage_counts {
      value = {}
    }

    var $reason_counts {
      value = {waiting_on_someone: 0, missing_information: 0, something_went_wrong: 0, other: 0}
    }

    foreach ($facts) {
      each as $f {
        conditional {
          if ($f.is_open == true) {
            array.push $open_children {
              value = $f
            }
          }
        }

        conditional {
          if ($f.is_open == true && $f.parent_cancelled == true) {
            array.push $parent_cancelled {
              value = $f
            }
          }
        }

        conditional {
          if ($f.recent == true) {
            var $sc_key {
              value = "s:" ~ $f.stage_label
            }

            var $sc_prev {
              value = ($stage_counts|get:$sc_key:null) ?? 0
            }

            var.update $stage_counts {
              value = $stage_counts|set:$sc_key:($sc_prev + 1)
            }

            var $rc_prev {
              value = ($reason_counts|get:$f.reason_code:null) ?? 0
            }

            var.update $reason_counts {
              value = $reason_counts|set:$f.reason_code:($rc_prev + 1)
            }
          }
        }
      }
    }

    var $by_stage {
      value = []
    }

    var $stage_keys {
      value = $stage_counts|keys
    }

    foreach ($stage_keys) {
      each as $sk {
        var $sk_count {
          value = ($stage_counts|get:$sk:null) ?? 0
        }

        // Hoisted: a piped filter WITH ARGUMENTS as an object-literal value
        // swallows every key after it (found live here — `count` vanished).
        var $sk_label {
          value = $sk|replace:"s:":""
        }

        array.push $by_stage {
          value = {stage_label: $sk_label, count: $sk_count}
        }
      }
    }

    var $by_reason {
      value = [
        {reason_code: "waiting_on_someone", count: $reason_counts.waiting_on_someone}
        {reason_code: "missing_information", count: $reason_counts.missing_information}
        {reason_code: "something_went_wrong", count: $reason_counts.something_went_wrong}
        {reason_code: "other", count: $reason_counts.other}
      ]
    }

    // ── Exception links whose target has never been published ──────────
    db.query journey_link {
      where = $db.journey_link.link_type == "exception"
      return = {type: "list"}
    } as $exc_links

    var $link_map_ids {
      value = [-1]
    }

    foreach ($exc_links) {
      each as $el {
        array.push $link_map_ids {
          value = $el.target_map
        }

        array.push $link_map_ids {
          value = $el.source_map
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $link_map_ids
      return = {type: "list"}
    } as $link_versions

    var $published {
      value = {}
    }

    foreach ($link_versions) {
      each as $lv {
        var $lv_key {
          value = "m:" ~ ($lv.journey_map_id|to_text)
        }

        var.update $published {
          value = $published|set:$lv_key:true
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $link_map_ids
      return = {type: "list"}
    } as $link_maps

    var $link_title {
      value = {}
    }

    foreach ($link_maps) {
      each as $lm {
        var $lm_key {
          value = "m:" ~ ($lm.id|to_text)
        }

        var.update $link_title {
          value = $link_title|set:$lm_key:$lm.title
        }
      }
    }

    var $link_facts {
      value = []
    }

    var $link_seen {
      value = {}
    }

    foreach ($exc_links) {
      each as $el2 {
        var $tgt_key {
          value = "m:" ~ ($el2.target_map|to_text)
        }

        var $src_key {
          value = "m:" ~ ($el2.source_map|to_text)
        }

        var $pair_key {
          value = $src_key ~ "::" ~ $tgt_key
        }

        var $pair_dup {
          value = (($link_seen|get:$pair_key:null) != null)
        }

        var.update $link_seen {
          value = $link_seen|set:$pair_key:true
        }

        array.push $link_facts {
          value = {
            source_map_id   : $el2.source_map
            source_map_title: ($link_title|get:$src_key:null) ?? ""
            target_map_id   : $el2.target_map
            target_map_title: ($link_title|get:$tgt_key:null) ?? ""
            target_published: ((($published|get:$tgt_key:null) ?? false) == true)
            dup             : $pair_dup
          }
        }
      }
    }

    var $unpublished_targets {
      value = []
    }

    foreach ($link_facts) {
      each as $lf {
        conditional {
          if ($lf.dup == false && $lf.target_published == false) {
            array.push $unpublished_targets {
              value = $lf
            }
          }
        }
      }
    }

    // ── Spawn refusals in the last 7 days, by code ─────────────────────
    db.query event_log {
      where = $db.event_log.feature == "EXC-1" && $db.event_log.outcome == "rejected" && $db.event_log.created_at >= $since_7d
      return = {type: "list"}
    } as $rejections

    var $rejection_counts {
      value = {}
    }

    foreach ($rejections) {
      each as $rj {
        var $rj_key {
          value = "c:" ~ ($rj.error_code ?? "")
        }

        var $rj_prev {
          value = ($rejection_counts|get:$rj_key:null) ?? 0
        }

        var.update $rejection_counts {
          value = $rejection_counts|set:$rj_key:($rj_prev + 1)
        }
      }
    }

    var $rejection_keys {
      value = $rejection_counts|keys
    }

    var $recent_rejections {
      value = []
    }

    foreach ($rejection_keys) {
      each as $rk {
        var $rk_count {
          value = ($rejection_counts|get:$rk:null) ?? 0
        }

        var $rk_code {
          value = $rk|replace:"c:":""
        }

        array.push $recent_rejections {
          value = {error_code: $rk_code, count: $rk_count}
        }
      }
    }
  }

  response = {
    open_children  : $open_children
    by_stage       : $by_stage
    by_reason      : $by_reason
    needs_attention: {parent_cancelled: $parent_cancelled, unpublished_targets: $unpublished_targets, recent_rejections: $recent_rejections}
  }
}
