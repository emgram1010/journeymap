// COP-2 stories 01/04/05/08 — the ONLY writer of copilot_action_level. A signed-in account admin
// who is a person sets one action type's level (and, for money types, its limit) in one business.
// The copilot can suggest; it can never call this (an AI identity is refused, E-COP-031, and it
// cannot sign in anyway).
//
// Refusals: business not in this account (E-COP-035); unknown type, or a locked / person-only
// type (E-COP-023 — Publish version and Publish to live can never be lowered); a level other
// than own / tell / wait, or a negative limit (E-COP-034); lowering an irreversible type that
// reaches outside the business below "waits for you" without confirm_irreversible = true
// (E-COP-026, so the screen can ask "this can't be undone — sure?").
//
// Actions already waiting stay waiting (story 01): the gate reads the level at the moment of
// action, and nothing here touches copilot_action. One row per (business, type), enforced by a
// unique index; an existing row is patched in place, the change is logged with from/to.
query "copilot/level_set" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int journey_architecture_id?
    text action_type? filters=trim
    text level? filters=trim|lower
    int limit_amount?
    bool confirm_irreversible?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/level_set"
        entity_id    : $input.journey_architecture_id
      }
    } as $admin_user

    function.run "copilot/identity_for_user" {
      input = {user_id: $auth.id}
    } as $me_ai

    precondition ($me_ai.is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can change approval levels. (E-COP-031)"
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    var $arch_ok {
      value = ($input.journey_architecture_id == 0 || ($arch|get:"account_id":0) == $admin_user.account_id)
    }

    precondition ($arch_ok) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    function.run "copilot/action_level" {
      input = {
        journey_architecture_id: $input.journey_architecture_id
        action_type            : $input.action_type
        amount                 : 0
        has_amount             : false
      }
    } as $current

    precondition ($current.known == true && $current.locked == false && $current.person_only == false) {
      error_type = "inputerror"
      error = "This kind of action is locked and its level can't be changed. (E-COP-023)"
    }

    var $level_ok {
      value = ($input.level == "own" || $input.level == "tell" || $input.level == "wait")
    }

    precondition ($level_ok && $input.limit_amount >= 0) {
      error_type = "inputerror"
      error = "Choose runs on its own, runs then tells you, or waits for you, and a limit of 0 or more. (E-COP-034)"
    }

    var $needs_confirm {
      value = ($current.reversible == false && $current.touches != "internal" && $input.level != "wait" && $input.confirm_irreversible != true)
    }

    precondition ($needs_confirm == false) {
      error_type = "inputerror"
      error = "This kind of action can't be undone once done. Confirm that the copilot may do it without asking you first. (E-COP-026)"
    }

    db.query copilot_action_level {
      where = $db.copilot_action_level.journey_architecture_id == $input.journey_architecture_id && $db.copilot_action_level.action_type == $input.action_type
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    conditional {
      if ($existing_id != 0) {
        db.patch copilot_action_level {
          field_name = "id"
          field_value = $existing_id
          data = {level: $input.level, limit_amount: $input.limit_amount, updated_by_user_id: $auth.id, updated_at: "now"}
        } as $_patched
      }

      else {
        db.add copilot_action_level {
          data = {
            account_id             : $admin_user.account_id
            journey_architecture_id: $input.journey_architecture_id
            action_type            : $input.action_type
            level                  : $input.level
            limit_amount           : $input.limit_amount
            updated_by_user_id     : $auth.id
            updated_at             : "now"
          }
        } as $_added
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-2"
        step       : "level_changed"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "An approval level was changed."
        user_id    : $auth.id
        account_id : $admin_user.account_id
        entity_type: "journey_architecture"
        entity_id  : $input.journey_architecture_id
        metadata   : {action_type: $input.action_type, from: $current.level, to: $input.level, limit_amount: $input.limit_amount}
      }
    } as $_level_logged
  }

  response = {
    journey_architecture_id: $input.journey_architecture_id
    action_type            : $input.action_type
    level                  : $input.level
    limit_amount           : $input.limit_amount
  }
  tags = ["cop-2"]
}
