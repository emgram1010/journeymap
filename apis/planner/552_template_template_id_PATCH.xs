// PLAN-1 (US-PLAN-1-02) — Edit a template, or archive it.
// PLAN-3 (US-PLAN-3-02) — now also accepts `add_agent_profile_ids`,
// same append-only shape as `add_map_ids`.
//
// NONE OF THIS REACHES AN EXISTING PLAN. Instances copied their
// window, start time, accepted maps and agent roster at creation;
// this endpoint changes only what the NEXT instance will be made
// from. That is the guarantee the template/instance split exists to
// provide, and FT-PLAN-1-05 is the test of it — confirmed live.
//
// ARCHIVING IS `is_active = false`, never a delete: instances point
// at this row, and how a plan was originally set up should stay
// readable long after the template stops being offered. An archived
// template is hidden from the default list and refuses new instances.
//
// ⚠️ MAPS AND AGENTS CAN ONLY BE ADDED HERE, NOT REMOVED. Removing one
// means deleting a `plan_template_map`/`plan_template_agent` row, and
// every delete in this backend is awaiting the founder's approval (see
// product/learning-fixes.md). Both `add_*_ids` inputs are append-only
// and ignore an id already attached, so they're safe to call
// repeatedly. `remove_*_ids` inputs belong here once deletes are
// allowed.
query "template/{template_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int template_id filters=min:1
    text name? filters=trim
    int window_days?
    text default_start_time? filters=trim
    bool is_active?
    json add_map_ids?
    json add_agent_profile_ids?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_template" {
      input = {account_id: $actor.account_id, template_id: $input.template_id}
    } as $guard

    var $existing {
      value = $guard.template
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_name {
      value = $existing.name
    }

    conditional {
      if ($raw_input|has:"name") {
        var.update $next_name {
          value = $input.name
        }
      }
    }

    var $next_window {
      value = $existing.window_days
    }

    conditional {
      if ($raw_input|has:"window_days") {
        var.update $next_window {
          value = $input.window_days
        }
      }
    }

    var $next_time {
      value = $existing.default_start_time
    }

    conditional {
      if ($raw_input|has:"default_start_time") {
        var.update $next_time {
          value = $input.default_start_time
        }
      }
    }

    var $next_active {
      value = $existing.is_active
    }

    conditional {
      if ($raw_input|has:"is_active") {
        var.update $next_active {
          value = $input.is_active
        }
      }
    }

    var $add_maps {
      value = []
    }

    conditional {
      if ($raw_input|has:"add_map_ids") {
        var.update $add_maps {
          value = $input.add_map_ids
        }
      }
    }

    var $add_agents {
      value = []
    }

    conditional {
      if ($raw_input|has:"add_agent_profile_ids") {
        var.update $add_agents {
          value = $input.add_agent_profile_ids
        }
      }
    }

    db.query plan_template {
      where = $db.plan_template.account_id == $actor.account_id && $db.plan_template.name == $next_name && $db.plan_template.id != $input.template_id
      return = {type: "count"}
    } as $name_clash

    function.run "planner/assert_maps_publishable" {
      input = {account_id: $actor.account_id, map_ids: $add_maps}
    } as $maps_check

    function.run "planner/assert_agent_profiles_eligible" {
      input = {account_id: $actor.account_id, profile_ids: $add_agents}
    } as $agents_check

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($next_name == null || $next_name == "" || ($next_name|strlen) > 80 || $name_clash > 0) {
        var.update $reject_code {
          value = "E-PLAN-001"
        }

        var.update $reject_msg {
          value = "Give the template a unique name (up to 80 characters). (E-PLAN-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_window < 1 || $next_window > 366)) {
        var.update $reject_code {
          value = "E-PLAN-002"
        }

        var.update $reject_msg {
          value = "Choose a window between 1 and 366 days. (E-PLAN-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ("/^([01][0-9]|2[0-3]):[0-5][0-9]$/"|regex_matches:$next_time) == false) {
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
      if ($reject_code == "" && $agents_check.ok == false && $agents_check.reason == "not_eligible") {
        var.update $reject_code {
          value = "E-PLAN-010"
        }

        var.update $reject_msg {
          value = "This person isn't tagged as an agent right now. (E-PLAN-010)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $agents_check.ok == false) {
        var.update $reject_code {
          value = "E-PLAN-010"
        }

        var.update $reject_msg {
          value = "One of those agents isn't available to this account. (E-PLAN-010)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLAN-1"
            step          : "update_template"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "plan_template"
            entity_id     : $input.template_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Template update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Already-attached maps are skipped rather than rejected, so this
    // is safe to call twice with the same list.
    db.query plan_template_map {
      where = $db.plan_template_map.plan_template_id == $input.template_id
      return = {type: "list"}
    } as $current_links

    var $have {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($current_links) {
      each as $l {
        var.update $key {
          value = $l.journey_map_id|to_text
        }

        var.update $have {
          value = $have|set:$key:1
        }
      }
    }

    var $to_add {
      value = []
    }

    foreach ($add_maps) {
      each as $mid {
        var.update $key {
          value = $mid|to_text
        }

        array.push $to_add {
          value = {map_id: $mid, already: ($have|get:$key:null)}
        }
      }
    }

    // Same dedupe shape, one level down: already-attached agent
    // profiles are skipped rather than rejected.
    db.query plan_template_agent {
      where = $db.plan_template_agent.plan_template_id == $input.template_id
      return = {type: "list"}
    } as $current_agent_links

    var $have_agent {
      value = {}
    }

    var $akey {
      value = ""
    }

    foreach ($current_agent_links) {
      each as $l {
        var.update $akey {
          value = $l.agent_profile_id|to_text
        }

        var.update $have_agent {
          value = $have_agent|set:$akey:1
        }
      }
    }

    var $to_add_agents {
      value = []
    }

    foreach ($add_agents) {
      each as $pid {
        var.update $akey {
          value = $pid|to_text
        }

        array.push $to_add_agents {
          value = {profile_id: $pid, already: ($have_agent|get:$akey:null)}
        }
      }
    }

    db.transaction {
      stack {
        db.patch plan_template {
          field_name = "id"
          field_value = $input.template_id
          data = {
            name              : $next_name
            window_days       : $next_window
            default_start_time: $next_time
            is_active         : $next_active
            updated_at        : "now"
          }
        } as $updated

        foreach ($to_add) {
          each as $a {
            conditional {
              if ($a.already == null) {
                db.add plan_template_map {
                  data = {plan_template_id: $input.template_id, journey_map_id: $a.map_id}
                } as $link
              }
            }
          }
        }

        foreach ($to_add_agents) {
          each as $a {
            conditional {
              if ($a.already == null) {
                db.add plan_template_agent {
                  data = {plan_template_id: $input.template_id, agent_profile_id: $a.profile_id}
                } as $agent_link
              }
            }
          }
        }
      }
    }

    db.query plan_template_map {
      where = $db.plan_template_map.plan_template_id == $input.template_id
      return = {type: "list"}
    } as $final_links

    var $map_ids {
      value = []
    }

    foreach ($final_links) {
      each as $l {
        array.push $map_ids {
          value = $l.journey_map_id
        }
      }
    }

    db.query plan_template_agent {
      where = $db.plan_template_agent.plan_template_id == $input.template_id
      return = {type: "list"}
    } as $final_agent_links

    var $agent_profile_ids {
      value = []
    }

    foreach ($final_agent_links) {
      each as $l {
        array.push $agent_profile_ids {
          value = $l.agent_profile_id
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "PLAN-1"
        step          : "update_template"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "plan_template"
        entity_id     : $input.template_id
        correlation_id: $input.correlation_id
        message       : "Plan template updated."
      }
    }
  }

  response = {
    template         : $updated
    map_ids          : $map_ids
    agent_profile_ids: $agent_profile_ids
  }
}
