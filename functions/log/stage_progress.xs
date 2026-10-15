// LOG-1 (US-LOG-1-04) — Is a stage finished?
//
// MVP fixed rule: a stage is done when every work task in it is
// `done` or `skipped`. The configurable rules (`any_done`, `manual`)
// arrive with STAGE-1's deferred fields; `logModel.ts::stageComplete`
// already implements all three so the caller does not change later.
//
// DERIVED, NOT STORED — DELIBERATELY. There is no `stage_status`
// column and no stage-progress table. Two caches already shadow the
// activity log (`work_task.status` and `work_item.status`) and each
// one is a thing that can silently drift and has to be audited. A
// third would buy nothing: the rule is a count over tasks we are
// already reading, and a count cannot be wrong.
//
// An EMPTY stage is never complete (`logModel.ts` agrees). "Every
// task is finished" is vacuously true for no tasks, and a naive
// implementation would advance a stage nobody has worked.
//
// ORDER comes from `work_task.id` ascending. JOB-1 generates a job's
// tasks by walking the pinned version's stages in display order, so
// creation order IS version order. The first task id of each stage is
// returned so a caller can re-sort without guessing.
function "log/stage_progress" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id
      sort = {id: "asc"}
      return = {type: "list"}
    } as $tasks

    var $by_key {
      value = {}
    }

    var $order {
      value = []
    }

    foreach ($tasks) {
      each as $t {
        var $k {
          value = $t.stage_key
        }

        // Fresh `var`s each iteration, never `var.update` read back in
        // a condition in the same pass — that pattern silently drops
        // the branch's writes in this workspace.
        var $fin {
          value = 0
        }

        conditional {
          if ($t.status == "done" || $t.status == "skipped") {
            var.update $fin {
              value = 1
            }
          }
        }

        var $blk {
          value = 0
        }

        conditional {
          if ($t.status == "blocked") {
            var.update $blk {
              value = 1
            }
          }
        }

        var $prog {
          value = 0
        }

        conditional {
          if ($t.status == "in_progress") {
            var.update $prog {
              value = 1
            }
          }
        }

        var $cur {
          value = $by_key|get:$k:null
        }

        conditional {
          if ($cur == null) {
            var.update $by_key {
              value = $by_key|set:$k:({}|set:"stage_key":$k|set:"total":1|set:"finished":$fin|set:"blocked":$blk|set:"in_progress":$prog|set:"first_task_id":$t.id)
            }

            array.push $order {
              value = $k
            }
          }

          else {
            var.update $by_key {
              value = $by_key|set:$k:($cur|set:"total":($cur.total + 1)|set:"finished":($cur.finished + $fin)|set:"blocked":($cur.blocked + $blk)|set:"in_progress":($cur.in_progress + $prog))
            }
          }
        }
      }
    }

    var $stages {
      value = []
    }

    var $current_stage_key {
      value = ""
    }

    var $complete_count {
      value = 0
    }

    foreach ($order) {
      each as $sk {
        var $e {
          value = $by_key|get:$sk:null
        }

        var $done {
          value = ($e.total > 0 && $e.finished == $e.total)
        }

        array.push $stages {
          value = $e|set:"complete":$done
        }

        conditional {
          if ($done) {
            var.update $complete_count {
              value = $complete_count + 1
            }
          }
        }

        // The first stage still carrying open work. Set once; later
        // iterations leave it alone.
        conditional {
          if ($done == false && $current_stage_key == "") {
            var.update $current_stage_key {
              value = $sk
            }
          }
        }
      }
    }

    var $all_complete {
      value = (($order|count) > 0 && $complete_count == ($order|count))
    }
  }

  response = {
    work_item_id     : $input.work_item_id
    stages           : $stages
    stage_count      : $order|count
    complete_count   : $complete_count
    current_stage_key: $current_stage_key
    all_complete     : $all_complete
  }
}
