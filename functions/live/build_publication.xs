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

    var $items {
      value = []
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

        foreach ($all_links) {
          each as $l {
            conditional {
              if ($l.planner_task_id == $s.id) {
                array.push $wt_ids {
                  value = $l.work_task_id
                }
              }
            }
          }
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
    var $canonical {
      value = "publication|v1\n"
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

        var.update $line {
          value = "item|" ~ $esc_ref ~ "|" ~ ($i.seq|to_text) ~ "|" ~ ($i.scheduled_minutes|to_text) ~ "|" ~ ($i.assignee_agent_id|to_text) ~ "|" ~ $esc_title ~ "|" ~ $wt_joined ~ "\n"
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
    canonical    : $canonical
    snapshot_hash: $hash
  }
}
