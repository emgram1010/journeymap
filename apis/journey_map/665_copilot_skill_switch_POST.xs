// COP-9 stories 01/08 — an account admin switches one skill-library item off (or back on) for ONE
// business, without retiring it: it stops loading there and keeps loading everywhere else in its
// scope. A signed-in person only, never an AI identity. The item and the business must both be in
// the admin's own account (E-COP-081). One row per (item, business), edited in place - the unique
// index refuses a duplicate. Logged as a success event.
query "copilot/skill_switch" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int skill_id?
    int journey_architecture_id?
    bool is_off?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id : $auth.id
        step          : "copilot/skill_switch"
        entity_id     : 0
        correlation_id: ""
      }
    } as $admin_user

    function.run "copilot/assert_person_only" {
      input = {
        user_id    : $auth.id
        account_id : $admin_user.account_id
        step       : "copilot/skill_switch"
        entity_type: "copilot_skill"
        entity_id  : $input.skill_id
      }
    } as $_person

    var $account_id {
      value = $admin_user.account_id
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $db.copilot_skill.account_id == $account_id && $account_id != 0
      return = {type: "single"}
      output = ["id"]
    } as $skill

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id && $db.journey_architecture.account_id == $account_id && $account_id != 0
      return = {type: "single"}
      output = ["id"]
    } as $arch

    var $ok {
      value = (($skill|get:"id":0) != 0 && ($arch|get:"id":0) != 0)
    }

    precondition ($ok) {
      error_type = "inputerror"
      error = "The copilot can only write skills in its own business, 'how I work'. (E-COP-081)"
    }

    db.query copilot_skill_off {
      where = $db.copilot_skill_off.skill_id == $input.skill_id && $db.copilot_skill_off.journey_architecture_id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id"]
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    conditional {
      if ($existing_id != 0) {
        db.patch copilot_skill_off {
          field_name = "id"
          field_value = $existing_id
          data = {is_off: $input.is_off, updated_at: "now", updated_by_user_id: $auth.id}
        } as $_patched
      }

      else {
        db.add copilot_skill_off {
          data = {account_id: $account_id, skill_id: $input.skill_id, journey_architecture_id: $input.journey_architecture_id, is_off: $input.is_off, updated_at: "now", updated_by_user_id: $auth.id}
        } as $_added
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-9"
        step       : "skill_switch"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "A skill was switched on or off for one business."
        user_id    : $auth.id
        account_id : $account_id
        entity_type: "copilot_skill"
        entity_id  : $input.skill_id
        metadata   : {journey_architecture_id: $input.journey_architecture_id, is_off: $input.is_off}
      }
    } as $_logged
  }

  response = {skill_id: $input.skill_id, journey_architecture_id: $input.journey_architecture_id, is_off: $input.is_off}
  tags = ["cop-9"]
}
