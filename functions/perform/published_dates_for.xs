// GAP-FIX W4/W5 (2026-10-17) — Every date this performer has published
// work on, across the account.
//
// WHY THIS EXISTS. The Today screen could only ever ask for ONE day and
// could only ever say one thing when that day was empty: "Nothing is
// scheduled for you today." That single sentence covered four completely
// different situations — no agent linked to this login, nothing
// published at all, work published for a DIFFERENT day, or work
// published to somebody else. For the only support person in the
// business that is a dead end: the screen knows nothing it can use to
// tell those apart. This function supplies the one missing fact that
// separates them, and the same list drives the day navigation (W4), so
// "next day with work" is a real jump rather than a guess.
//
// MIRRORS perform/collect_published_items EXACTLY in how it decides
// "mine": the frozen publication snapshot's own `assignee_agent_id`,
// through a PRE-SEEDED membership map (`|contains:` is false for every
// array — CLAUDE.md), never the live plan. The two must agree, because
// a date listed here that then shows an empty day would be a worse lie
// than the empty state it replaces.
//
// DUPLICATES AND ORDER ARE THE CALLER'S PROBLEM, deliberately. De-duping
// here would need a conditional reading a set built earlier in the same
// loop — the exact shape that silently discards its writes — and
// sorting ISO date strings is one line in the client. Returning the raw
// list keeps this function free of both traps.
//
// COST: one scan of the account's published publications per call. Fine
// at MVP volumes; revisit with a date-indexed lookup if an account ever
// carries thousands of published days.
function "perform/published_dates_for" {
  input {
    int account_id filters=min:1
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
      where = $db.planner_timeline.workspace_id in $ws_ids && $db.planner_timeline.status == "published"
      return = {type: "list"}
    } as $timelines

    var $date_by_tl {
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

        var.update $date_by_tl {
          value = $date_by_tl|set:$key:$t.planned_date
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

    var $dates {
      value = []
    }

    var $tl_key {
      value = ""
    }

    var $tl_date {
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

        var.update $tl_date {
          value = $date_by_tl|get:$tl_key:""
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
                array.push $dates {
                  value = $tl_date
                }
              }
            }
          }
        }
      }
    }
  }

  response = {dates: $dates}
}
