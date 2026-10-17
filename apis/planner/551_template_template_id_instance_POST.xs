// PLAN-1 (US-PLAN-1-04) — Create a real plan from a template.
//
// THE RESULT IS A COPY, NOT A LINK. The window length, the default
// start time and the accepted maps are read from the template ONCE,
// here, and written onto the new plan. From this moment the two are
// independent: editing the template cannot change a plan someone is
// already working to, and that is the entire reason the template and
// the instance are separate things.
//
// Proven live (FT-PLAN-1-05/06): an instance made from a 14-day
// template ran Oct 19 → Nov 1; the template was then changed to 30
// days and 07:30; the existing instance did not move, and the next
// instance ran Oct 19 → Nov 17 at 07:30.
//
// `plan_template_id` is still recorded, but only as provenance — "this
// plan came from that template". Nothing reads the template again.
//
// THE WINDOW IS INCLUSIVE of both ends, so a 14-day window ends 13
// days after it starts. The same rule is unit-tested on the frontend
// in `webapp/protype-2/src/planTemplate.ts::windowEnd`, including the
// month, year and leap-day boundaries.
//
// Everything is one `db.transaction`: a failure partway through must
// not leave a plan with half its accepted maps, which would be a
// plan that silently refuses work it should accept.
query "template/{template_id}/instance" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int template_id filters=min:1
    text name filters=trim
    date start_date
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_template" {
      input = {account_id: $actor.account_id, template_id: $input.template_id}
    } as $guard

    var $template {
      value = $guard.template
    }

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $actor.account_id && $db.planner_workspace.name == $input.name
      return = {type: "count"}
    } as $name_clash

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.name == null || $input.name == "" || ($input.name|strlen) > 80) {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give the plan a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $name_clash > 0) {
        var.update $reject_code {
          value = "E-PLN-001"
        }

        var.update $reject_msg {
          value = "You already have a plan with this name. (E-PLN-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $template.is_active == false) {
        var.update $reject_code {
          value = "E-PLAN-001"
        }

        var.update $reject_msg {
          value = "That template is archived, so new plans can't be made from it. (E-PLAN-001)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLAN-1"
            step          : "create_instance"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Instance create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Window end is inclusive: start + (window_days - 1) days.
    var $offset_days {
      value = $template.window_days - 1
    }

    var $offset_ms {
      value = $offset_days * 86400000
    }

    var $start_ms {
      value = $input.start_date|to_timestamp
    }

    var $end_ms {
      value = $start_ms + $offset_ms
    }

    var $window_end {
      value = $end_ms|format_timestamp:"Y-m-d":"UTC"
    }

    // Read the template's maps ONCE, now. This list is what gets
    // copied; the template is never consulted again.
    db.query plan_template_map {
      where = $db.plan_template_map.plan_template_id == $input.template_id
      return = {type: "list"}
    } as $template_maps

    db.transaction {
      stack {
        db.add planner_workspace {
          data = {
            account_id              : $actor.account_id
            created_by              : $actor.user_id
            name                    : $input.name
            planning_window_start   : $input.start_date
            planning_window_end     : $window_end
            input_tokens_per_minute : 2000
            output_tokens_per_minute: 500
            is_archived             : false
            plan_template_id        : $input.template_id
          }
        } as $workspace

        foreach ($template_maps) {
          each as $tm {
            db.add planner_workspace_map {
              data = {workspace_id: $workspace.id, journey_map_id: $tm.journey_map_id}
            } as $copied
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "PLAN-1"
        step          : "create_instance"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $workspace.id
        correlation_id: $input.correlation_id
        message       : "Plan created from template."
        metadata      : {
          template_id : $input.template_id
          window_start: $input.start_date
          window_end  : $window_end
          map_count   : ($template_maps|count)
        }
      }
    }
  }

  response = {
    workspace         : $workspace
    from_template_id  : $input.template_id
    default_start_time: $template.default_start_time
    window_days       : $template.window_days
    accepted_map_count: ($template_maps|count)
  }
}
