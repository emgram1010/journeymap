// PLAN-1 (US-PLAN-1-02) — Create a plan template.
//
// The template is the reusable shape; the plan made from it is a
// separate copy. Nothing here holds tasks, people or capacity.
//
// MAPS ARE VALIDATED BEFORE ANYTHING IS WRITTEN, so a template is
// never left half-built with some maps attached and one rejected.
// Only a map with a published version may be attached — see
// planner/assert_maps_publishable for why.
//
// Admin-only is deliberately NOT applied: PLN-2's access matrix
// reserves admin for rates and the model catalogue only. A template
// is ordinary planning work, like a plan or an agent.
query "template" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    text name filters=trim
    int window_days?
    text default_start_time? filters=trim
    json map_ids?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $window_days {
      value = 14
    }

    conditional {
      if ($raw_input|has:"window_days") {
        var.update $window_days {
          value = $input.window_days
        }
      }
    }

    var $start_time {
      value = "08:00"
    }

    conditional {
      if ($raw_input|has:"default_start_time") {
        var.update $start_time {
          value = $input.default_start_time
        }
      }
    }

    var $map_ids {
      value = []
    }

    conditional {
      if ($raw_input|has:"map_ids") {
        var.update $map_ids {
          value = $input.map_ids
        }
      }
    }

    db.query plan_template {
      where = $db.plan_template.account_id == $actor.account_id && $db.plan_template.name == $input.name
      return = {type: "count"}
    } as $name_clash

    function.run "planner/assert_maps_publishable" {
      input = {account_id: $actor.account_id, map_ids: $map_ids}
    } as $maps_check

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.name == null || $input.name == "" || ($input.name|strlen) > 80 || $name_clash > 0) {
        var.update $reject_code {
          value = "E-PLAN-001"
        }

        var.update $reject_msg {
          value = "Give the template a unique name (up to 80 characters). (E-PLAN-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($window_days < 1 || $window_days > 366)) {
        var.update $reject_code {
          value = "E-PLAN-002"
        }

        var.update $reject_msg {
          value = "Choose a window between 1 and 366 days. (E-PLAN-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ("/^([01][0-9]|2[0-3]):[0-5][0-9]$/"|regex_matches:$start_time) == false) {
        var.update $reject_code {
          value = "E-PLAN-003"
        }

        var.update $reject_msg {
          value = "Enter a start time like 08:00. (E-PLAN-003)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $maps_check.ok == false && $maps_check.reason == "not_published") {
        var.update $reject_code {
          value = "E-PLAN-004"
        }

        var.update $reject_msg {
          value = "Publish '" ~ $maps_check.map_title ~ "' first. Only published maps can be used in a plan. (E-PLAN-004)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $maps_check.ok == false) {
        var.update $reject_code {
          value = "E-PLAN-004"
        }

        var.update $reject_msg {
          value = "One of those maps isn't available to this account. (E-PLAN-004)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLAN-1"
            step          : "create_template"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "plan_template"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Template create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.transaction {
      stack {
        db.add plan_template {
          data = {
            account_id        : $actor.account_id
            name              : $input.name
            window_days       : $window_days
            default_start_time: $start_time
            is_active         : true
          }
        } as $template

        foreach ($map_ids) {
          each as $mid {
            db.add plan_template_map {
              data = {plan_template_id: $template.id, journey_map_id: $mid}
            } as $link
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "PLAN-1"
        step          : "create_template"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "plan_template"
        entity_id     : $template.id
        correlation_id: $input.correlation_id
        message       : "Plan template created."
        metadata      : {map_count: ($map_ids|count)}
      }
    }
  }

  response = {
    template: $template
    map_ids : $map_ids
  }
}
