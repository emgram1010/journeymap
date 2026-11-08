// TW-1 (US-TW-1-02) — Which of a job's steps sit on a day that is
// already published to live. Shared by the time-window PUT and DELETE so
// "is this change after go-live" has one answer.
//
// Job -> work_task -> planner_task_work_task -> planner_task -> timeline,
// then live/latest_publications (the one rule for "current publication").
// Every id list is seeded with -1 so an `in` clause never sees [] (only
// `not in [-1]` / `in [-1]` are confirmed). Branches read loop items only.
function "jobs/time_window_live_refs" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      return = {type: "list"}
    } as $wts

    var $wt_ids {
      value = [-1]
    }

    foreach ($wts) {
      each as $w {
        array.push $wt_ids {
          value = $w.id
        }
      }
    }

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id in $wt_ids
      return = {type: "list"}
    } as $links

    var $pt_ids {
      value = [-1]
    }

    foreach ($links) {
      each as $l {
        array.push $pt_ids {
          value = $l.planner_task_id
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.id in $pt_ids
      return = {type: "list"}
    } as $pts

    var $tl_ids {
      value = [-1]
    }

    foreach ($pts) {
      each as $pt {
        array.push $tl_ids {
          value = $pt.timeline_id
        }
      }
    }

    function.run "live/latest_publications" {
      input = {timeline_ids: $tl_ids}
    } as $latest

    var $item_refs {
      value = []
    }

    var $published_timeline_ids {
      value = []
    }

    foreach ($latest.publications) {
      each as $p {
        array.push $published_timeline_ids {
          value = $p.timeline_id
        }
      }
    }

    foreach ($pts) {
      each as $pt {
        foreach ($latest.publications) {
          each as $p {
            conditional {
              if ($pt.timeline_id == $p.timeline_id) {
                array.push $item_refs {
                  value = "pt-" ~ ($pt.id|to_text)
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    live                  : (($item_refs|count) > 0)
    item_refs             : $item_refs
    published_timeline_ids: $published_timeline_ids
  }
}
