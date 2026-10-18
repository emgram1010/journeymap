// US-DEL-1-01 (2026-10-18) — Is anything depending on this map?
//
// THE ONE PLACE THIS IS DECIDED. Both the map delete (api 22) and the
// architecture cascade (api 69) call it, so there can never be two
// ideas of what "in use" means — the duplication CLAUDE.md singles out
// as the kind that eventually disagrees with itself.
//
// WHY. Deleting a map used to succeed no matter what, leaving a plan
// or a template silently claiming a map that no longer existed. Found
// live on 2026-10-18: one plan and two templates already in that
// state. The symptom is not an error at delete time — it is a
// confusing refusal days later when someone tries to create a job
// ("This plan doesn't use 'that map'").
//
// THE REASON IS NAMED, NOT JUST FLAGGED. "Something uses it" is not
// something anyone can act on, so this returns the NAME of the first
// plan or template that does, and the caller puts it in the message.
//
// JOBS COUNT AS A DEPENDENCY even though they would survive the
// delete (they read the frozen version, not the map — see
// US-DEL-1-02). A map that real work was created from is history, and
// history is not tidied away. Counted through journey_map_version,
// because `work_item` points at a version, never at a map.
//
// Three counting queries plus two small lookups — no row loading, the
// same shape as planner/workspace_has_history.
function "journey/assert_map_unused" {
  input {
    int journey_map_id filters=min:1
  }

  stack {
    // Plans that have accepted this map.
    db.query planner_workspace_map {
      where = $db.planner_workspace_map.journey_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $plan_links

    // Templates that list this map.
    db.query plan_template_map {
      where = $db.plan_template_map.journey_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $template_links

    // Jobs created from any version of this map.
    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $versions

    var $version_ids {
      value = []
    }

    foreach ($versions) {
      each as $v {
        array.push $version_ids {
          value = $v.id
        }
      }
    }

    var $job_count {
      value = 0
    }

    conditional {
      if (($version_ids|count) > 0) {
        db.query work_item {
          where = $db.work_item.journey_map_version_id in $version_ids
          return = {type: "count"}
        } as $jobs

        var.update $job_count {
          value = $jobs
        }
      }
    }

    var $ok {
      value = true
    }

    var $reason {
      value = ""
    }

    var $blocker_name {
      value = ""
    }

    // Plans first: the most actionable thing to tell someone, because
    // a plan is where they would go to remove it.
    conditional {
      if (($plan_links|count) > 0) {
        db.get planner_workspace {
          field_name = "id"
          field_value = ($plan_links|first).workspace_id
        } as $plan

        var.update $ok {
          value = false
        }

        var.update $reason {
          value = "in_use_by_plan"
        }

        var.update $blocker_name {
          value = ($plan.name ?? "a plan")
        }
      }
    }

    conditional {
      if ($ok == true && ($template_links|count) > 0) {
        db.get plan_template {
          field_name = "id"
          field_value = ($template_links|first).plan_template_id
        } as $tpl

        var.update $ok {
          value = false
        }

        var.update $reason {
          value = "in_use_by_template"
        }

        var.update $blocker_name {
          value = ($tpl.name ?? "a template")
        }
      }
    }

    conditional {
      if ($ok == true && $job_count > 0) {
        var.update $ok {
          value = false
        }

        var.update $reason {
          value = "has_jobs"
        }

        var.update $blocker_name {
          value = ""
        }
      }
    }
  }

  response = {
    ok            : $ok
    reason        : $reason
    blocker_name  : $blocker_name
    plan_count    : ($plan_links|count)
    template_count: ($template_links|count)
    job_count     : $job_count
  }
}
