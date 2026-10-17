// JOB-1 (US-JOB-1-02) — Add a job to a plan; its tasks appear
// automatically from the published map version.
//
// THE JOB IS PINNED TO THE LATEST PUBLISHED VERSION AT THIS MOMENT,
// and that pin never moves. Publishing a newer version later, or
// editing the live map, cannot change this job's content — it keeps
// reading the snapshot it started with. Work already in flight is
// immune to later edits, which is the whole reason PUB-1 freezes
// versions at all. Proven live: a job pinned to v2 still read v2's
// text word-for-word after v3 was published with everything changed.
//
// TWO CHECKS BEFORE ANYTHING IS WRITTEN:
//   - the map must be one this plan accepts (`planner_workspace_map`,
//     copied from the template by PLAN-1) — E-JOB-002;
//   - it must have a published version — E-JOB-003.
// The messages name the map, because "that map isn't allowed" with no
// name is not something anyone can act on.
//
// The job row and all its tasks are one `db.transaction`: a job with
// half its tasks would look complete-able while silently missing
// steps.
query "work_item" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int journey_map_id filters=min:1
    text title filters=trim
    json attributes?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "JOB-1"
        step       : "add_job"
        entity_type: "planner_workspace"
        entity_id  : $input.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $map

    var $map_title {
      value = "that map"
    }

    conditional {
      if ($map != null) {
        var.update $map_title {
          value = $map.title
        }
      }
    }

    // Is this map one the plan accepts?
    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id && $db.planner_workspace_map.journey_map_id == $input.journey_map_id
      return = {type: "count"}
    } as $accepted

    // The latest published version, if any.
    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.journey_map_id
      sort = {journey_map_version.version_no: "desc"}
      return = {type: "list"}
    } as $versions

    var $version_count {
      value = $versions|count
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.title == null || $input.title == "" || ($input.title|strlen) > 120) {
        var.update $reject_code {
          value = "E-JOB-001"
        }

        var.update $reject_msg {
          value = "Give the job a short title (up to 120 characters). (E-JOB-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ("/<[a-zA-Z][^>]*>/"|regex_matches:$input.title) == true) {
        var.update $reject_code {
          value = "E-JOB-001"
        }

        var.update $reject_msg {
          value = "Give the job a short title (up to 120 characters). (E-JOB-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($map == null || $map.account_id != $actor.account_id || $accepted == 0)) {
        var.update $reject_code {
          value = "E-JOB-002"
        }

        var.update $reject_msg {
          value = "This plan doesn't use '" ~ $map_title ~ "'. Add it to the plan's maps first. (E-JOB-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $version_count == 0) {
        var.update $reject_code {
          value = "E-JOB-003"
        }

        var.update $reject_msg {
          value = "'" ~ $map_title ~ "' hasn't been published yet. (E-JOB-003)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "JOB-1"
            step          : "add_job"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Add job refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $version {
      value = $versions|first
    }

    function.run "jobs/tasks_from_version" {
      input = {snapshot: $version.snapshot}
    } as $plan

    db.transaction {
      stack {
        db.add work_item {
          data = {
            account_id            : $actor.account_id
            workspace_id          : $input.workspace_id
            journey_map_version_id: $version.id
            title                 : $input.title
            status                : "open"
            attributes            : ($input.attributes ?? {})
            parent_work_item_id   : 0
            created_by            : $actor.user_id
          }
        } as $job

        foreach ($plan.tasks) {
          each as $t {
            db.add work_task {
              data = {
                work_item_id: $job.id
                stage_key   : $t.stage_key
                lens_key    : $t.lens_key
                status      : "not_started"
              }
            } as $task
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "JOB-1"
        step          : "add_job"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_item"
        entity_id     : $job.id
        correlation_id: $input.correlation_id
        message       : "Job added to plan."
        metadata      : {
          task_count   : ($plan.tasks|count)
          skipped_count: ($plan.skipped|count)
          version_id   : $version.id
          version_no   : $version.version_no
        }
      }
    }
  }

  response = {
    work_item     : $job
    pinned_version: {id: $version.id, version_no: $version.version_no}
    task_count    : ($plan.tasks|count)
    tasks         : $plan.tasks
    skipped_stages: $plan.skipped
  }
}
