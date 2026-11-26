// REQ-1 story 05 — what a JOB's step needs: the job's step (work_task) names a stage key and a row key, and its job (work_item) is pinned to one published map version. This function resolves those two and asks the one question (req/step_needs), so a job never reads the live map. A job pinned to an older version reads the older needs; a job on a version published before this feature reads none. Read-only. A step or job that does not exist answers no needs (the caller has its own not-found rule).
function "req/job_step_needs" {
  input {
    int work_task_id filters=min:1
  }

  stack {
    db.query work_task {
      where = $db.work_task.id == $input.work_task_id
      return = {type: "single"}
    } as $task

    var $item_id {
      value = $task|get:"work_item_id":0
    }

    db.query work_item {
      where = $db.work_item.id == $item_id
      return = {type: "single"}
    } as $item

    var $version_id {
      value = $item|get:"journey_map_version_id":0
    }

    var $stage_key {
      value = $task|get:"stage_key":""
    }

    var $lens_key {
      value = $task|get:"lens_key":""
    }

    var $out {
      value = {needs: [], hard: 0, soft: 0}
    }

    conditional {
      if ($version_id != 0 && $stage_key != "" && $lens_key != "") {
        function.run "req/step_needs" {
          input = {journey_map_version_id: $version_id, stage_key: $stage_key, lens_key: $lens_key}
        } as $found

        var.update $out {
          value = $found
        }
      }
    }
  }

  response = {journey_map_version_id: $version_id, needs: $out.needs, hard: $out.hard, soft: $out.soft}
}
