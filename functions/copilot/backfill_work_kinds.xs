// COP-11 story 03 ("existing items") — one-off backfill: skill-library items saved before COP-11 with
// scope_type "work_kind" and a free-text scope_text get the closest kind from the fixed list
// (map_building, planning, doing_work, research), or "general", in copilot_skill_meta.work_kind.
// Safe by design:
//   - only fills a kind that is NOT set yet (no meta row, or work_kind ""); a set kind is never overwritten;
//   - never deletes, retires or edits an item, and never touches the lock;
//   - dry_run true = report only; writes need a named account (account_id != 0); account_id 0 = report
//     across every account, never written.
// Two passes: the first resolves every item into a row (kind + what to do), the second writes, with its
// condition on the LOOP ITEM only (CLAUDE.md: never branch on a var updated in the same iteration).
// Logged as copilot.skill.kinds_backfilled with the counts.
function "copilot/backfill_work_kinds" {
  input {
    int account_id?
    bool dry_run?
  }

  stack {
    precondition ($input.dry_run == true || $input.account_id != 0) {
      error_type = "inputerror"
      error = "Writing needs one named account. Run with dry_run true to report across all accounts."
    }

    var $all_accounts {
      value = $input.account_id == 0
    }

    db.query copilot_skill {
      where = $db.copilot_skill.scope_type == "work_kind" && ($all_accounts || $db.copilot_skill.account_id == $input.account_id)
      sort = {copilot_skill.id: "asc"}
      return = {type: "list"}
      output = ["id", "account_id", "title", "scope_text"]
    } as $items

    var $item_ids {
      value = [-1]
    }

    foreach ($items) {
      each as $it {
        array.push $item_ids {
          value = $it.id
        }
      }
    }

    db.query copilot_skill_meta {
      where = $db.copilot_skill_meta.skill_id in $item_ids
      return = {type: "list"}
      output = ["id", "skill_id", "work_kind"]
    } as $metas

    var $meta_id {
      value = {}
    }

    var $meta_kind {
      value = {}
    }

    var $mk {
      value = ""
    }

    foreach ($metas) {
      each as $m {
        var.update $mk {
          value = "s::" ~ ($m.skill_id|to_text)
        }

        var.update $meta_id {
          value = $meta_id|set:$mk:$m.id
        }

        var.update $meta_kind {
          value = $meta_kind|set:$mk:$m.work_kind
        }
      }
    }

    // Pass 1: resolve each item.
    var $rows {
      value = []
    }

    var $t {
      value = ""
    }

    var $exact {
      value = ""
    }

    var $kind {
      value = ""
    }

    var $is_research {
      value = false
    }

    var $is_planning {
      value = false
    }

    var $is_map {
      value = false
    }

    var $is_doing {
      value = false
    }

    var $has_meta {
      value = 0
    }

    var $cur_kind {
      value = ""
    }

    var $act {
      value = ""
    }

    var $row {
      value = {}
    }

    foreach ($items) {
      each as $it {
        var.update $t {
          value = (($it.scope_text ?? "")|lower)|trim
        }

        var.update $exact {
          value = $t|replace:" ":"_"
        }

        var.update $is_research {
          value = ($t|contains:"research") || ($t|contains:"source") || ($t|contains:"find out")
        }

        var.update $is_planning {
          value = ($t|contains:"plan") || ($t|contains:"schedul") || ($t|contains:"calendar") || ($t|contains:"week")
        }

        var.update $is_map {
          value = ($t|contains:"map") || ($t|contains:"build") || ($t|contains:"journey") || ($t|contains:"stage")
        }

        var.update $is_doing {
          value = ($t|contains:"task") || ($t|contains:"job") || ($t|contains:"doing") || ($t|contains:"perform") || ($t|contains:"execut")
        }

        var.update $kind {
          value = (($exact == "map_building" || $exact == "planning" || $exact == "doing_work" || $exact == "research" || $exact == "general") ? $exact : "")
        }

        var.update $kind {
          value = (($kind == "" && $is_research) ? "research" : $kind)
        }

        var.update $kind {
          value = (($kind == "" && $is_planning) ? "planning" : $kind)
        }

        var.update $kind {
          value = (($kind == "" && $is_map) ? "map_building" : $kind)
        }

        var.update $kind {
          value = (($kind == "" && $is_doing) ? "doing_work" : $kind)
        }

        var.update $kind {
          value = (($kind == "") ? "general" : $kind)
        }

        var.update $mk {
          value = "s::" ~ ($it.id|to_text)
        }

        var.update $has_meta {
          value = ($meta_id|get:$mk:null) ?? 0
        }

        var.update $cur_kind {
          value = ($meta_kind|get:$mk:null) ?? ""
        }

        var.update $act {
          value = (($has_meta == 0) ? "add" : (($cur_kind == "") ? "patch" : "keep"))
        }

        var.update $row {
          value = {skill_id: $it.id, account_id: $it.account_id, title: $it.title, scope_text: $it.scope_text, kind: $kind, meta_id: $has_meta, current_kind: $cur_kind, action: $act}
        }

        array.push $rows {
          value = $row
        }
      }
    }

    // Pass 2: write. Conditions read the loop item and the input only.
    foreach ($rows) {
      each as $r {
        conditional {
          if ($r.action == "add" && $input.dry_run == false) {
            db.add copilot_skill_meta {
              data = {created_at: "now", updated_at: "now", skill_id: $r.skill_id, account_id: $r.account_id, is_locked: false, locked_by_user_id: 0, work_kind: $r.kind}
            } as $_added
          }

          elseif ($r.action == "patch" && $input.dry_run == false) {
            db.patch copilot_skill_meta {
              field_name = "id"
              field_value = $r.meta_id
              data = {updated_at: "now", work_kind: $r.kind}
            } as $_patched
          }
        }
      }
    }

    var $n_add {
      value = 0
    }

    var $n_patch {
      value = 0
    }

    var $n_keep {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $n_add {
          value = $n_add + (($r.action == "add")|to_int)
        }

        var.update $n_patch {
          value = $n_patch + (($r.action == "patch")|to_int)
        }

        var.update $n_keep {
          value = $n_keep + (($r.action == "keep")|to_int)
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-11"
        step       : "copilot.skill.kinds_backfilled"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The kind-of-work backfill ran."
        user_id    : 0
        account_id : $input.account_id
        entity_type: "copilot_skill_meta"
        entity_id  : 0
        metadata   : {dry_run: $input.dry_run, added: $n_add, filled: $n_patch, kept: $n_keep}
      }
    } as $_logged
  }

  response = {dry_run: $input.dry_run, account_id: $input.account_id, added: $n_add, filled: $n_patch, kept: $n_keep, rows: $rows}
}
