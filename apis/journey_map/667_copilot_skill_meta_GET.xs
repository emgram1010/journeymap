// COP-11 stories 04/05 — the side table's own read endpoint (the AUTH-1 rule: a side table needs its
// own GET, or the screen never sees it). For the signed-in person's account: each item's lock, kind of
// work, when it was last used and whether it is "not used in N days", plus the three limits and the
// active-item count for "23 of 50 items". Read-only; "last used" is computed from copilot_skill_use
// (not stored); nothing is ever retired or changed for being stale (story 04).
// COP-9-05: also each item's use count and the trial rule's two numbers, for "Trial: 3 of 5 uses".
query "copilot/skill_meta" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $me

    var $account_id {
      value = $me|get:"account_id":0
    }

    db.query copilot_library_setting {
      where = $db.copilot_library_setting.account_id == $account_id && $account_id != 0
      return = {type: "single"}
    } as $setting

    var $max_items_raw {
      value = ($setting|get:"max_active_items":0) ?? 0
    }

    var $max_words_raw {
      value = ($setting|get:"max_load_words":0) ?? 0
    }

    var $stale_days_raw {
      value = ($setting|get:"stale_after_days":0) ?? 0
    }

    var $max_items {
      value = (($max_items_raw != 0) ? $max_items_raw : 50)
    }

    var $max_words {
      value = (($max_words_raw != 0) ? $max_words_raw : 4000)
    }

    var $stale_days {
      value = (($stale_days_raw != 0) ? $stale_days_raw : 30)
    }

    var $trial_min_raw {
      value = ($setting|get:"trial_min_uses":0) ?? 0
    }

    var $trial_max_raw {
      value = ($setting|get:"trial_max_overrides":0) ?? 0
    }

    var $trial_min {
      value = (($trial_min_raw != 0) ? $trial_min_raw : 5)
    }

    var $trial_max {
      value = (($trial_max_raw != 0) ? $trial_max_raw : 2)
    }

    var $now_ms {
      value = now|to_int
    }

    var $cutoff {
      value = $now_ms - ($stale_days * 86400000)
    }

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $account_id && $account_id != 0
      sort = {copilot_skill.id: "asc"}
      return = {type: "list"}
      output = ["id", "created_at", "status"]
    } as $skills

    db.query copilot_skill_meta {
      where = $db.copilot_skill_meta.account_id == $account_id && $account_id != 0
      return = {type: "list"}
      output = ["skill_id", "is_locked", "locked_by_user_id", "locked_at", "work_kind"]
    } as $metas

    // Oldest first, so the last write for a key is the newest use.
    db.query copilot_skill_use {
      where = $db.copilot_skill_use.account_id == $account_id && $account_id != 0
      sort = {copilot_skill_use.created_at: "asc"}
      return = {type: "list"}
      output = ["skill_id", "exception_skill_id", "created_at"]
    } as $uses

    var $last_used {
      value = {}
    }

    var $key {
      value = ""
    }

    var $key2 {
      value = ""
    }

    var $ts {
      value = 0
    }

    var $use_count {
      value = {}
    }

    var $n1 {
      value = 0
    }

    var $n2 {
      value = 0
    }

    foreach ($uses) {
      each as $u {
        var.update $key {
          value = "k" ~ ($u.skill_id|to_text)
        }

        var.update $key2 {
          value = "k" ~ ($u.exception_skill_id|to_text)
        }

        var.update $ts {
          value = $u.created_at|to_int
        }

        var.update $last_used {
          value = $last_used|set:$key:$ts
        }

        var.update $last_used {
          value = $last_used|set:$key2:$ts
        }

        var.update $n1 {
          value = (($use_count|get:$key:null) ?? 0) + 1
        }

        var.update $use_count {
          value = $use_count|set:$key:$n1
        }

        var.update $n2 {
          value = (($use_count|get:$key2:null) ?? 0) + 1
        }

        var.update $use_count {
          value = $use_count|set:$key2:$n2
        }
      }
    }

    var $out {
      value = []
    }

    var $active_count {
      value = 0
    }

    var $lu {
      value = 0
    }

    var $created_ms {
      value = 0
    }

    var $stale {
      value = false
    }

    var $uc {
      value = 0
    }

    foreach ($skills) {
      each as $s {
        var.update $key {
          value = "k" ~ ($s.id|to_text)
        }

        var.update $lu {
          value = ($last_used|get:$key:null) ?? 0
        }

        var.update $uc {
          value = ($use_count|get:$key:null) ?? 0
        }

        var.update $created_ms {
          value = $s.created_at|to_int
        }

        var.update $stale {
          value = ($s.status != "retired" && ((($lu != 0) && ($lu < $cutoff)) || (($lu == 0) && ($created_ms < $cutoff))))
        }

        var.update $active_count {
          value = $active_count + (($s.status != "retired")|to_int)
        }

        array.push $out {
          value = {skill_id: $s.id, last_used_at: $lu, not_used_in_days: $stale, use_count: $uc}
        }
      }
    }
  }

  response = {
    items               : $out
    metas               : $metas
    active_count        : $active_count
    max_active_items    : $max_items
    max_load_words      : $max_words
    stale_after_days    : $stale_days
    trial_min_uses      : $trial_min
    trial_max_overrides : $trial_max
  }
  tags = ["cop-11"]
}
