// APP-1 (US-APP-1-02, -03) — Live status plus hydrated task text for a
// set of work_task ids, keyed by id.
//
// SAME HYDRATION ENDPOINT 555 ALREADY DOES for one job's tasks, done
// here across potentially many jobs at once (one scheduled block can
// bundle work_task rows from different jobs). Task text, done-when
// and expected minutes come from each task's own PINNED version —
// never the live map — so the performer always sees what the job was
// actually built from, exactly like JOB-1's own read endpoint.
//
// Composite keys use "::", never "|" inside a quoted string literal —
// confirmed live that a literal pipe between two `~` concatenations
// breaks the parser even though it is inside quotes (CLAUDE.md).
function "perform/hydrate_statuses" {
  input {
    int[] work_task_ids
  }

  stack {
    db.query work_task {
      where = $db.work_task.id in $input.work_task_ids
      return = {type: "list"}
    } as $tasks

    var $wi_ids {
      value = []
    }

    var $seen_wi {
      value = {}
    }

    var $wi_key {
      value = ""
    }

    var $already {
      value = null
    }

    foreach ($tasks) {
      each as $t {
        var.update $wi_key {
          value = $t.work_item_id|to_text
        }

        var.update $already {
          value = $seen_wi|get:$wi_key:null
        }

        conditional {
          if ($already == null) {
            array.push $wi_ids {
              value = $t.work_item_id
            }

            var.update $seen_wi {
              value = $seen_wi|set:$wi_key:true
            }
          }
        }
      }
    }

    db.query work_item {
      where = $db.work_item.id in $wi_ids
      return = {type: "list"}
    } as $jobs

    var $version_id_by_wi {
      value = {}
    }

    var $version_ids {
      value = []
    }

    var $seen_version {
      value = {}
    }

    foreach ($jobs) {
      each as $j {
        var.update $wi_key {
          value = $j.id|to_text
        }

        var.update $version_id_by_wi {
          value = $version_id_by_wi|set:$wi_key:$j.journey_map_version_id
        }

        var.update $wi_key {
          value = $j.journey_map_version_id|to_text
        }

        var.update $already {
          value = $seen_version|get:$wi_key:null
        }

        conditional {
          if ($already == null) {
            array.push $version_ids {
              value = $j.journey_map_version_id
            }

            var.update $seen_version {
              value = $seen_version|set:$wi_key:true
            }
          }
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $versions

    // One flat map covers every version: key = "<version_id>::<stage_key>::<lens_key>".
    var $cell_map {
      value = {}
    }

    var $stage_label_map {
      value = {}
    }

    var $lens_label_map {
      value = {}
    }

    var $v_key {
      value = ""
    }

    var $cell_key {
      value = ""
    }

    foreach ($versions) {
      each as $v {
        var.update $v_key {
          value = $v.id|to_text
        }

        foreach ($v.snapshot.cells) {
          each as $c {
            var.update $cell_key {
              value = $v_key ~ "::" ~ $c.stage_key ~ "::" ~ $c.lens_key
            }

            var.update $cell_map {
              value = $cell_map|set:$cell_key:$c
            }
          }
        }

        foreach ($v.snapshot.stages) {
          each as $s {
            var.update $cell_key {
              value = $v_key ~ "::" ~ $s.key
            }

            var.update $stage_label_map {
              value = $stage_label_map|set:$cell_key:$s.label
            }
          }
        }

        foreach ($v.snapshot.lenses) {
          each as $l {
            var.update $cell_key {
              value = $v_key ~ "::" ~ $l.key
            }

            var.update $lens_label_map {
              value = $lens_label_map|set:$cell_key:$l.label
            }
          }
        }
      }
    }

    var $statuses {
      value = {}
    }

    var $task_key {
      value = ""
    }

    var $version_text {
      value = ""
    }

    var $cell {
      value = null
    }

    foreach ($tasks) {
      each as $t {
        var.update $wi_key {
          value = $t.work_item_id|to_text
        }

        var.update $version_text {
          value = ($version_id_by_wi|get:$wi_key:0)|to_text
        }

        var.update $cell_key {
          value = $version_text ~ "::" ~ $t.stage_key ~ "::" ~ $t.lens_key
        }

        var.update $cell {
          value = $cell_map|get:$cell_key:null
        }

        var.update $task_key {
          value = $t.id|to_text
        }

        var.update $statuses {
          value = $statuses|set:$task_key:({
            work_task_id    : $t.id
            stage_key       : $t.stage_key
            lens_key        : $t.lens_key
            status          : $t.status
            started_at      : $t.started_at
            completed_at    : $t.completed_at
            stage_label     : ($stage_label_map|get:($version_text ~ "::" ~ $t.stage_key):null)
            lens_label      : ($lens_label_map|get:($version_text ~ "::" ~ $t.lens_key):null)
            task            : ($cell.task ?? null)
            done_when       : ($cell.done_when ?? null)
            expected_minutes: ($cell.duration_minutes ?? null)
          })
        }
      }
    }
  }

  response = {statuses: $statuses}
}
