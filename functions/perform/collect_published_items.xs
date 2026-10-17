// APP-1 (US-APP-1-02) — Every published item, on a given day, whose
// EFFECTIVE assignee is one of these agents.
//
// READS ONLY THE FROZEN PUBLICATION, never the live plan (D-23) — the
// same rule LOG-1's record-event endpoint already follows for the
// publication id it stamps onto each log row. A planner rearranging
// the day after publish changes nothing this returns.
//
// `assignee_agent_id` is read straight off each snapshot item, which
// `live/build_publication` already resolved to the slot's own
// override or the timeline's agent — so a step reassigned to a
// different person than who owns the timeline is still found here,
// and a step on someone else's timeline reassigned to ME is too.
//
// MEMBERSHIP TEST: `$my_agents|get:$key:null` with a PRE-SEEDED set,
// never `|contains:` (confirmed always false on arrays) and never a
// nested foreach per item (O(items × agents), needless at MVP size
// but still the wrong habit to build). A miss correctly returns null
// here because null IS the "not mine" answer we want — the one case
// where `|get`'s variable-key default bug is harmless by accident.
function "perform/collect_published_items" {
  input {
    int account_id filters=min:1
    text date filters=trim
    int[] agent_ids
  }

  stack {
    var $my_agents {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($input.agent_ids) {
      each as $id {
        var.update $key {
          value = $id|to_text
        }

        var.update $my_agents {
          value = $my_agents|set:$key:true
        }
      }
    }

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $input.account_id
      return = {type: "list"}
    } as $workspaces

    var $ws_ids {
      value = []
    }

    foreach ($workspaces) {
      each as $w {
        array.push $ws_ids {
          value = $w.id
        }
      }
    }

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id in $ws_ids && $db.planner_timeline.planned_date == $input.date && $db.planner_timeline.status == "published"
      return = {type: "list"}
    } as $timelines

    var $start_by_tl {
      value = {}
    }

    var $tl_ids {
      value = []
    }

    foreach ($timelines) {
      each as $t {
        var.update $key {
          value = $t.id|to_text
        }

        var.update $start_by_tl {
          value = $start_by_tl|set:$key:$t.start_time
        }

        array.push $tl_ids {
          value = $t.id
        }
      }
    }

    db.query plan_publication {
      where = $db.plan_publication.timeline_id in $tl_ids
      return = {type: "list"}
    } as $pubs

    var $items {
      value = []
    }

    var $tl_key {
      value = ""
    }

    var $tl_start {
      value = ""
    }

    var $item_key {
      value = ""
    }

    var $is_mine {
      value = null
    }

    foreach ($pubs) {
      each as $pub {
        var.update $tl_key {
          value = $pub.timeline_id|to_text
        }

        var.update $tl_start {
          value = $start_by_tl|get:$tl_key:""
        }

        foreach ($pub.snapshot.items) {
          each as $raw {
            var.update $item_key {
              value = $raw.assignee_agent_id|to_text
            }

            var.update $is_mine {
              value = $my_agents|get:$item_key:null
            }

            conditional {
              if ($is_mine != null) {
                array.push $items {
                  value = {
                    item_ref         : $raw.item_ref
                    planner_task_id  : $raw.planner_task_id
                    timeline_id      : $pub.timeline_id
                    timeline_start_time: $tl_start
                    seq              : $raw.seq
                    scheduled_minutes: $raw.scheduled_minutes
                    assignee_agent_id: $raw.assignee_agent_id
                    assignee_name    : $raw.assignee_name
                    title            : $raw.title
                    work_task_ids    : $raw.work_task_ids
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  response = {items: $items}
}
