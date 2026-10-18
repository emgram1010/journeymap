// PLAN-1 (US-PLAN-1-04) — Create a real plan from a template.
// PLAN-3 (US-PLAN-3-03) — now also copies the template's agent
// roster into fresh `planner_agent` rows.
//
// THE RESULT IS A COPY, NOT A LINK. The window length, the default
// start time, the accepted maps and the agent roster are read from
// the template ONCE, here, and written onto the new plan. From this
// moment the three are independent: editing the template cannot
// change a plan someone is already working to, and that is the
// entire reason the template and the instance are separate things.
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
// A ROSTER AGENT MAY HAVE GONE INELIGIBLE since it was added to the
// template (PLAN-2 `is_eligible`). NEVER FAIL THE WHOLE INSTANCE for
// that — skip it and say so plainly in the response (`skipped_agents`),
// same "never fail silently" rule OBS-1 already holds this project to
// (D-1, EPIC-PLAN-3).
//
// Everything is one `db.transaction`: a failure partway through must
// not leave a plan with half its accepted maps or agents, which would
// be a plan that silently refuses work it should accept.
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

    // Read the template's agent roster ONCE, now, and resolve each
    // profile's CURRENT eligibility and display data — same rule as
    // the maps above (consulted once, never again after this request).
    db.query plan_template_agent {
      where = $db.plan_template_agent.plan_template_id == $input.template_id
      return = {type: "list"}
    } as $template_agents

    var $roster_profile_ids {
      value = []
    }

    foreach ($template_agents) {
      each as $ta {
        array.push $roster_profile_ids {
          value = $ta.agent_profile_id
        }
      }
    }

    var $profiles_by_id {
      value = {}
    }

    var $rkey {
      value = ""
    }

    conditional {
      if (($roster_profile_ids|count) > 0) {
        db.query agent_profile {
          where = $db.agent_profile.id in $roster_profile_ids
          return = {type: "list"}
        } as $roster_profiles

        var $roster_user_ids {
          value = []
        }

        foreach ($roster_profiles) {
          each as $p {
            conditional {
              if ($p.user_id != 0) {
                array.push $roster_user_ids {
                  value = $p.user_id
                }
              }
            }
          }
        }

        var $roster_user_names {
          value = {}
        }

        conditional {
          if (($roster_user_ids|count) > 0) {
            db.query user {
              where = $db.user.id in $roster_user_ids
              return = {type: "list"}
            } as $roster_owners

            foreach ($roster_owners) {
              each as $u {
                var.update $rkey {
                  value = $u.id|to_text
                }

                var.update $roster_user_names {
                  value = $roster_user_names|set:$rkey:$u.name
                }
              }
            }
          }
        }

        var $resolved_name {
          value = ""
        }

        foreach ($roster_profiles) {
          each as $p {
            var.update $rkey {
              value = $p.id|to_text
            }

            var.update $resolved_name {
              value = $p.name
            }

            conditional {
              if ($p.user_id != 0) {
                var.update $resolved_name {
                  value = ($roster_user_names|get:$rkey:"")
                }
              }
            }

            var.update $profiles_by_id {
              value = $profiles_by_id|set:$rkey:{
                profile_id : $p.id
                user_id    : $p.user_id
                kind       : $p.kind
                name       : $resolved_name
                color      : $p.color
                capacity   : $p.default_daily_capacity_hours
                is_eligible: $p.is_eligible
              }
            }
          }
        }
      }
    }

    // Split the roster into what actually gets copied vs. what's
    // reported as skipped. TWO PASSES (CLAUDE.md): pass 1 just records
    // each lookup as a field via array.push — no branching yet — pass
    // 2 branches on the LOOP ITEM's own field. Branching directly on a
    // var set earlier in the same iteration (the first draft of this
    // did exactly that) silently discards the branch's writes; this
    // shape is the confirmed-safe one `assert_maps_publishable` and
    // `assert_agent_profiles_eligible` already use.
    var $roster_checks {
      value = []
    }

    foreach ($template_agents) {
      each as $ta {
        var.update $rkey {
          value = $ta.agent_profile_id|to_text
        }

        array.push $roster_checks {
          value = {profile_id: $ta.agent_profile_id, info: ($profiles_by_id|get:$rkey:null)}
        }
      }
    }

    var $agents_to_copy {
      value = []
    }

    var $skipped_agents {
      value = []
    }

    foreach ($roster_checks) {
      each as $c {
        conditional {
          if ($c.info != null && $c.info.is_eligible == true) {
            array.push $agents_to_copy {
              value = $c.info
            }
          }
        }

        conditional {
          if ($c.info == null) {
            array.push $skipped_agents {
              value = {profile_id: $c.profile_id, name: null, reason: "not_found"}
            }
          }
        }

        conditional {
          if ($c.info != null && $c.info.is_eligible == false) {
            array.push $skipped_agents {
              value = {profile_id: $c.profile_id, name: $c.info.name, reason: "not_eligible"}
            }
          }
        }
      }
    }

    // Gap-fix #1, last line of defence: names are checked when an
    // agent is added to the template, but a person or AI agent can be
    // renamed afterwards. Two agents with the same name in one plan
    // would hit planner_agent's (workspace, name) unique index and
    // fail the whole plan with a raw database error. Skip every agent
    // whose name is shared, and say why, instead.
    // Same seed → increment → read-back → branch-on-loop-item shape as
    // planner/assert_roster_names_unique.
    var $name_counts {
      value = {}
    }

    var $nk {
      value = ""
    }

    foreach ($agents_to_copy) {
      each as $ag {
        var.update $nk {
          value = "n:" ~ ($ag.name|trim|lower)
        }

        var.update $name_counts {
          value = $name_counts|set:$nk:0
        }
      }
    }

    var $nprev {
      value = 0
    }

    var $nnext {
      value = 0
    }

    foreach ($agents_to_copy) {
      each as $ag {
        var.update $nk {
          value = "n:" ~ ($ag.name|trim|lower)
        }

        var.update $nprev {
          value = $name_counts|get:$nk:0
        }

        var.update $nnext {
          value = $nprev + 1
        }

        var.update $name_counts {
          value = $name_counts|set:$nk:$nnext
        }
      }
    }

    var $copy_checks {
      value = []
    }

    foreach ($agents_to_copy) {
      each as $ag {
        var.update $nk {
          value = "n:" ~ ($ag.name|trim|lower)
        }

        array.push $copy_checks {
          value = {info: $ag, count: ($name_counts|get:$nk:0)}
        }
      }
    }

    var $final_copy {
      value = []
    }

    foreach ($copy_checks) {
      each as $cc {
        conditional {
          if ($cc.count <= 1) {
            array.push $final_copy {
              value = $cc.info
            }
          }
        }

        conditional {
          if ($cc.count > 1) {
            array.push $skipped_agents {
              value = {profile_id: $cc.info.profile_id, name: $cc.info.name, reason: "duplicate_name"}
            }
          }
        }
      }
    }

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

        foreach ($final_copy) {
          each as $ag {
            db.add planner_agent {
              data = {
                workspace_id         : $workspace.id
                name                 : $ag.name
                kind                 : $ag.kind
                color                : $ag.color
                daily_capacity_hours : $ag.capacity
                user_id              : $ag.user_id
                is_visible           : true
                is_active            : true
              }
            } as $copied_agent
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
          template_id        : $input.template_id
          window_start       : $input.start_date
          window_end         : $window_end
          map_count          : ($template_maps|count)
          agent_count        : ($final_copy|count)
          skipped_agent_count: ($skipped_agents|count)
        }
      }
    }

    // Gap-fix #6: a skipped agent means a plan started short-staffed.
    // That's something support should be able to see on the Health
    // page, not only the person who clicked "Create plan".
    conditional {
      if (($skipped_agents|count) > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "PLAN-3"
            step          : "skip_roster_agent"
            outcome       : "success"
            severity      : "warn"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $workspace.id
            correlation_id: $input.correlation_id
            message       : "Plan created from a template, but some roster agents were left off."
            metadata      : {template_id: $input.template_id, skipped: $skipped_agents}
          }
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
    agent_count       : ($final_copy|count)
    skipped_agents    : $skipped_agents
  }
}
