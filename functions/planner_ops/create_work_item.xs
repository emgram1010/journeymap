// COP-5 story 01 (rule moved from endpoint 554, JOB-1 US-JOB-1-02) - add a job to a plan; its tasks come from the map's latest published version, and the job stays pinned to that version for good. This is endpoint 554's rule moved, not rewritten: same checks in the same order, same error codes and messages, same events, same writes, same response keys - so the endpoint and the copilot tool (plan_add_job) create jobs through one piece of code. Takes `actor` (what planner/resolve_actor returns: user_id, account_id, role) because a function has no $auth. Two checks before anything is written: the plan must accept the map (E-JOB-002) and the map must have a published version (E-JOB-003). The job row and all its tasks are one db.transaction. parent_work_item_id 0 = an ordinary job; a real id puts the job under that parent (EXC-1 US-EXC-1-04: must be in this account and this plan, E-EXC-009, and not cancelled, E-EXC-001). Every function.run passes every input this function shares a name with, because an omitted one would inherit this function's own input. Since 4-C (2026-11-17) endpoint 554 itself calls this function, so this is the only copy of the rule. "Latest published version" = the highest version_no: every journey_map_version row is written only by Publish version (endpoint 201, which always stamps published_at), so there is no unpublished version to skip (checked live: 0 of 26 rows without published_at).
function "planner_ops/create_work_item" {
  input {
    // What planner/resolve_actor returns: {user_id, account_id, role}.
    json actor

    int workspace_id filters=min:1
    int journey_map_id filters=min:1

    // Optional on purpose (4-C, 2026-11-17): a title of only spaces trims to "", and a REQUIRED
    // input would refuse that with a bare "Missing param" and no event. Optional lets it reach the
    // E-JOB-001 check below, which is what endpoint 554 always answered.
    text title? filters=trim

    json attributes?

    // EXC-1 - 0 (omitted) = no parent. An optional int arrives as 0, never null.
    int parent_work_item_id?

    text correlation_id? filters=trim
    json order_lines?
    json unmatched_lines?
  }

  stack {
    function.run "planner/assert_workspace" {
      input = {
        account_id  : $input.actor.account_id
        workspace_id: $input.workspace_id
      }
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "JOB-1"
        step          : "add_job"
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        correlation_id: $input.correlation_id
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
      if ($reject_code == "" && ("/<[a-zA-Z][^>]*>/"|regex_matches:$input.title)) {
        var.update $reject_code {
          value = "E-JOB-001"
        }

        var.update $reject_msg {
          value = "Give the job a short title (up to 120 characters). (E-JOB-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($map == null || $map.account_id != $input.actor.account_id || $accepted == 0)) {
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
            user_id       : $input.actor.user_id
            account_id    : $input.actor.account_id
            entity_type   : "work_item"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Add job refused."
          }
        }
      }
    }

    // EXC-1 (US-EXC-1-04) - the optional parent. Read only when given.
    var $parent_id {
      value = $input.parent_work_item_id
    }

    conditional {
      if ($reject_code == "" && $parent_id != 0) {
        db.get work_item {
          field_name = "id"
          field_value = $parent_id
        } as $parent_job

        conditional {
          if ($parent_job == null || $parent_job.account_id != $input.actor.account_id || $parent_job.workspace_id != $input.workspace_id) {
            var.update $reject_code {
              value = "E-EXC-009"
            }

            var.update $reject_msg {
              value = "That parent job is in a different plan. (E-EXC-009)"
            }
          }

          elseif ($parent_job.status == "cancelled") {
            var.update $reject_code {
              value = "E-EXC-001"
            }

            var.update $reject_msg {
              value = "That job is finished or cancelled, so nothing can be sent from it or added under it. (E-EXC-001)"
            }
          }
        }

        conditional {
          if ($reject_code != "") {
            function.run "ops/log_event" {
              input = {
                feature       : "EXC-1"
                step          : "child_job_created"
                outcome       : "rejected"
                severity      : "info"
                user_id       : $input.actor.user_id
                account_id    : $input.actor.account_id
                entity_type   : "work_item"
                entity_id     : $parent_id
                correlation_id: $input.correlation_id
                error_code    : $reject_code
                message       : "Add job under a parent refused."
              }
            }
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

    // The job + task writes live in ONE place, jobs/create_job, shared with the exception
    // spawn's child job. It writes only; this transaction is what makes "a job with half its
    // tasks" impossible (a function.run inside db.transaction rolls back with it - verified live).
    db.transaction {
      stack {
        function.run "jobs/create_job" {
          input = {
            account_id            : $input.actor.account_id
            workspace_id          : $input.workspace_id
            journey_map_version_id: $version.id
            title                 : $input.title
            attributes            : ($input.attributes ?? {})
            parent_work_item_id   : $parent_id
            created_by            : $input.actor.user_id
            tasks                 : $plan.tasks
            order_lines           : ($input.order_lines ?? [])
            unmatched_lines       : ($input.unmatched_lines ?? [])
          }
        } as $job
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "JOB-1"
        step          : "add_job"
        outcome       : "success"
        severity      : "info"
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        entity_type   : "work_item"
        entity_id     : $job.id
        correlation_id: $input.correlation_id
        message       : "Job added to plan."
        metadata      : {
        task_count   : $plan.tasks|count
        skipped_count: $plan.skipped|count
        version_id   : $version.id
        version_no   : $version.version_no
      }
      }
    }

    conditional {
      if ($parent_id != 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "child_job_created"
            outcome       : "success"
            severity      : "info"
            user_id       : $input.actor.user_id
            account_id    : $input.actor.account_id
            entity_type   : "work_item"
            entity_id     : $job.id
            correlation_id: $input.correlation_id
            message       : "Job added under a parent job."
            metadata      : {
            parent_work_item_id   : $parent_id
            journey_map_version_id: $version.id
            task_count            : $plan.tasks|count
          }
          }
        }
      }
    }
  }

  response = {
    work_item     : $job
    pinned_version: {id: $version.id, version_no: $version.version_no}
    task_count    : $plan.tasks|count
    tasks         : $plan.tasks
    skipped_stages: $plan.skipped
  }
}
