// REQ-1 story 02 — Record that a person holds a requirement, optionally until a date. Saving it again UPDATES the end date and is not an error. ADMIN PERSON ONLY: a member is refused (usr/assert_team_admin, E-USR-001) and an AI identity is refused and logged (copilot/assert_person_only, E-COP-025): an AI can never record what anyone holds, itself included. Another account's profile or requirement is "not found". An archived requirement cannot be NEWLY recorded (E-REQ-011), but its existing holdings can still change. `held_until` is text "YYYY-MM-DD" or empty for no end; anything else that is not a real day is refused (E-REQ-012). It is compared to the date of the work, never a clock (req/holding_state). Two parallel first saves: the unique index on (profile, requirement) refuses the second, and the loser is turned into an update. Events: holding.recorded, holding.changed, each with profile, requirement, end date and actor. Every input is passed to function.run explicitly.
query "agent-profile/{agent_profile_id}/requirement" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int agent_profile_id filters=min:1
    int requirement_id filters=min:1
    text held_until? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "holding_record", entity_type: "agent_profile", entity_id: $input.agent_profile_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "holding/record", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "planner/assert_agent_profile" {
      input = {account_id: $actor.account_id, profile_id: $input.agent_profile_id}
    } as $profile_guard

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $req_guard

    function.run "req/holding_state" {
      input = {held_until: $input.held_until, on_date: "2000-01-01"}
    } as $date_check

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.agent_profile_id == $input.agent_profile_id && $db.agent_profile_requirement.requirement_id == $input.requirement_id
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($date_check.bad_date == true) {
        var.update $reject_code {
          value = "E-REQ-012"
        }

        var.update $reject_msg {
          value = "That is not a real date. Use the form 2027-03-31, or leave it empty for no end. (E-REQ-012)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $existing_id == 0 && $req_guard.requirement.is_active == false) {
        var.update $reject_code {
          value = "E-REQ-011"
        }

        var.update $reject_msg {
          value = "That requirement is archived, so it cannot be newly recorded. Restore it first. (E-REQ-011)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "holding.record"
            outcome       : "rejected"
            severity      : "info"
            error_code    : $reject_code
            message       : $reject_msg
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "agent_profile"
            entity_id     : $input.agent_profile_id
            correlation_id: $input.correlation_id
          }
        } as $_logged_reject
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $end {
      value = (($date_check.has_end == true) ? $input.held_until : "")
    }

    var $row_id {
      value = $existing_id
    }

    var $was_new {
      value = false
    }

    conditional {
      if ($existing_id == 0) {
        var.update $was_new {
          value = true
        }

        try_catch {
          try {
            group {
              stack {
                db.add agent_profile_requirement {
                  data = {
                    account_id      : $actor.account_id
                    agent_profile_id: $input.agent_profile_id
                    requirement_id  : $input.requirement_id
                    held_until      : $end
                    recorded_by     : $actor.user_id
                    updated_at      : "now"
                  }
                } as $added

                var.update $row_id {
                  value = $added.id
                }
              }
            }
          }

          catch {
            var.update $was_new {
              value = false
            }
          }
        }
      }
    }

    // The loser of a parallel first save, or an existing holding: update the row.
    conditional {
      if ($was_new == false) {
        db.query agent_profile_requirement {
          where = $db.agent_profile_requirement.agent_profile_id == $input.agent_profile_id && $db.agent_profile_requirement.requirement_id == $input.requirement_id
          return = {type: "single"}
        } as $target

        var.update $row_id {
          value = $target|get:"id":0
        }

        db.patch agent_profile_requirement {
          field_name = "id"
          field_value = $row_id
          data = {held_until: $end, recorded_by: $actor.user_id, updated_at: "now"}
        } as $patched
      }
    }

    var $step {
      value = (($was_new == true) ? "holding.recorded" : "holding.changed")
    }

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : $step
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A holding was recorded or its end date changed."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "agent_profile"
        entity_id     : $input.agent_profile_id
        correlation_id: $input.correlation_id
        metadata      : {requirement_id: $input.requirement_id, requirement: $req_guard.requirement.name, held_until: $end, actor: $actor.user_id}
      }
    } as $_logged
  }

  response = {agent_profile_id: $input.agent_profile_id, requirement_id: $input.requirement_id, held_until: $end, created: $was_new}
}
