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
// APP-2 (US-APP-2-01) — each entry also carries `session`: which job,
// which flow and which plan this step belongs to. Found in review
// 2026-10-17: the performer screen showed bare step names with no way
// to tell two jobs on the same flow apart. `$jobs` and `$versions`
// were already loaded here for the task/done-when hydration above, so
// this adds exactly two more queries TOTAL (journey_map titles,
// workspace/plan names) — never one per task or per job — and reuses
// the same dedup-then-lookup shape the cell/stage/lens maps above
// already use.
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

    // APP-2 (US-APP-2-01): job title and plan (workspace) id, keyed by
    // work_item id — built in this same pass, no second loop over $jobs.
    var $job_title_by_wi {
      value = {}
    }

    var $ws_id_by_wi {
      value = {}
    }

    var $ws_ids {
      value = []
    }

    var $seen_ws {
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

        var.update $job_title_by_wi {
          value = $job_title_by_wi|set:$wi_key:$j.title
        }

        var.update $ws_id_by_wi {
          value = $ws_id_by_wi|set:$wi_key:$j.workspace_id
        }

        var.update $wi_key {
          value = $j.workspace_id|to_text
        }

        var.update $already {
          value = $seen_ws|get:$wi_key:null
        }

        conditional {
          if ($already == null) {
            array.push $ws_ids {
              value = $j.workspace_id
            }

            var.update $seen_ws {
              value = $seen_ws|set:$wi_key:true
            }
          }
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

    // One query, regardless of how many jobs/tasks are being hydrated.
    db.query planner_workspace {
      where = $db.planner_workspace.id in $ws_ids
      return = {type: "list"}
    } as $plans

    var $plan_name_by_wsid {
      value = {}
    }

    var $plan_key {
      value = ""
    }

    foreach ($plans) {
      each as $p {
        var.update $plan_key {
          value = $p.id|to_text
        }

        var.update $plan_name_by_wsid {
          value = $plan_name_by_wsid|set:$plan_key:$p.name
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id in $version_ids
      return = {type: "list"}
    } as $versions

    // APP-2 (US-APP-2-01): the flow's title lives on `journey_map`, not
    // on the version row — one more dedup-then-lookup pass, same shape
    // as the maps just above.
    var $map_ids {
      value = []
    }

    var $seen_map {
      value = {}
    }

    var $map_key {
      value = ""
    }

    foreach ($versions) {
      each as $v {
        var.update $map_key {
          value = $v.journey_map_id|to_text
        }

        var.update $already {
          value = $seen_map|get:$map_key:null
        }

        conditional {
          if ($already == null) {
            array.push $map_ids {
              value = $v.journey_map_id
            }

            var.update $seen_map {
              value = $seen_map|set:$map_key:true
            }
          }
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $map_ids
      return = {type: "list"}
    } as $maps

    var $flow_title_by_mapid {
      value = {}
    }

    foreach ($maps) {
      each as $m {
        var.update $map_key {
          value = $m.id|to_text
        }

        var.update $flow_title_by_mapid {
          value = $flow_title_by_mapid|set:$map_key:$m.title
        }
      }
    }

    var $flow_title_by_version {
      value = {}
    }

    var $version_no_by_version {
      value = {}
    }

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

        var.update $map_key {
          value = $v.journey_map_id|to_text
        }

        var.update $flow_title_by_version {
          value = $flow_title_by_version|set:$v_key:($flow_title_by_mapid|get:$map_key:null)
        }

        var.update $version_no_by_version {
          value = $version_no_by_version|set:$v_key:$v.version_no
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

    // APP-2 (US-APP-2-02) — notes, newest first, grouped by work_task
    // id. One query regardless of task count, same shape as every
    // other lookup in this function. `event_type == "note"` only:
    // a blocked reason is a different concept, shown with the status,
    // not mixed into this list.
    db.query activity_log {
      where = $db.activity_log.work_task_id in $input.work_task_ids && $db.activity_log.event_type == "note"
      sort = {activity_log.occurred_at: "desc"}
      return = {type: "list"}
    } as $note_rows

    var $note_author_ids {
      value = []
    }

    var $seen_author {
      value = {}
    }

    var $author_key {
      value = ""
    }

    foreach ($note_rows) {
      each as $n {
        var.update $author_key {
          value = $n.performer_user_id|to_text
        }

        var.update $already {
          value = $seen_author|get:$author_key:null
        }

        conditional {
          if ($already == null) {
            array.push $note_author_ids {
              value = $n.performer_user_id
            }

            var.update $seen_author {
              value = $seen_author|set:$author_key:true
            }
          }
        }
      }
    }

    db.query user {
      where = $db.user.id in $note_author_ids
      return = {type: "list"}
    } as $note_authors

    var $author_name_by_id {
      value = {}
    }

    foreach ($note_authors) {
      each as $a {
        var.update $author_key {
          value = $a.id|to_text
        }

        var.update $author_name_by_id {
          value = $author_name_by_id|set:$author_key:$a.name
        }
      }
    }

    // Grouped here, once, rather than filtered per task below — the
    // `|get` with a variable key silently drops its default on a
    // miss (CLAUDE.md), so every work_task_id this function was asked
    // about is pre-seeded to an empty list before any note is added.
    var $notes_by_task {
      value = {}
    }

    var $note_task_key {
      value = ""
    }

    foreach ($input.work_task_ids) {
      each as $wtid {
        var.update $note_task_key {
          value = $wtid|to_text
        }

        var.update $notes_by_task {
          value = $notes_by_task|set:$note_task_key:[]
        }
      }
    }

    var $note_bucket {
      value = []
    }

    foreach ($note_rows) {
      each as $n {
        var.update $note_task_key {
          value = $n.work_task_id|to_text
        }

        var.update $author_key {
          value = $n.performer_user_id|to_text
        }

        var.update $note_bucket {
          value = $notes_by_task|get:$note_task_key:[]
        }

        array.push $note_bucket {
          value = {
            note      : $n.note
            occurred_at: $n.occurred_at
            author    : ($author_name_by_id|get:$author_key:null)
          }
        }

        var.update $notes_by_task {
          value = $notes_by_task|set:$note_task_key:$note_bucket
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

    // APP-2 (US-APP-2-01): hoisted one var per lookup, never a pipe
    // nested inside another filter's argument (CLAUDE.md) — e.g.
    // `$plan_name_by_wsid|get:($id|to_text):null` parses but fails at
    // runtime with "Invalid expression".
    var $session_job_title {
      value = null
    }

    var $session_plan_id {
      value = 0
    }

    var $session_plan_id_text {
      value = ""
    }

    var $session_plan_name {
      value = null
    }

    var $session_flow_title {
      value = null
    }

    var $session_version_no {
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

        var.update $session_job_title {
          value = $job_title_by_wi|get:$wi_key:null
        }

        var.update $session_plan_id {
          value = $ws_id_by_wi|get:$wi_key:0
        }

        var.update $session_plan_id_text {
          value = $session_plan_id|to_text
        }

        var.update $session_plan_name {
          value = $plan_name_by_wsid|get:$session_plan_id_text:null
        }

        var.update $session_flow_title {
          value = $flow_title_by_version|get:$version_text:null
        }

        var.update $session_version_no {
          value = $version_no_by_version|get:$version_text:null
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
            session         : {
              work_item_id: $t.work_item_id
              title       : $session_job_title
              flow_title  : $session_flow_title
              version_no  : $session_version_no
              plan_id     : $session_plan_id
              plan_name   : $session_plan_name
            }
            notes           : ($notes_by_task|get:$task_key:[])
          })
        }
      }
    }
  }

  response = {statuses: $statuses}
}
