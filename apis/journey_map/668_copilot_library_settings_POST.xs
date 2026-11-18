// COP-11 story 03 — an account admin changes the three library limits. A signed-in person only
// (never an AI identity). Server bounds: items 10-200, words 1000-20000, days 7-365; outside them the
// save is refused with a plain message and nothing changes. One row per account, edited in place
// (unique account_id); no row = defaults 50 / 4000 / 30. Logged as a success event.
query "copilot/library_settings" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int max_active_items?
    int max_load_words?
    int stale_after_days?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id : $auth.id
        step          : "copilot/library_settings"
        entity_id     : 0
        correlation_id: ""
      }
    } as $admin_user

    function.run "copilot/assert_person_only" {
      input = {
        user_id    : $auth.id
        account_id : $admin_user.account_id
        step       : "copilot/library_settings"
        entity_type: "copilot_library_setting"
        entity_id  : 0
      }
    } as $_person

    var $account_id {
      value = $admin_user.account_id
    }

    precondition ($input.max_active_items >= 10 && $input.max_active_items <= 200) {
      error_type = "inputerror"
      error = "The most items must be between 10 and 200."
    }

    precondition ($input.max_load_words >= 1000 && $input.max_load_words <= 20000) {
      error_type = "inputerror"
      error = "The most words loaded per run must be between 1,000 and 20,000."
    }

    precondition ($input.stale_after_days >= 7 && $input.stale_after_days <= 365) {
      error_type = "inputerror"
      error = "Flag unused items after between 7 and 365 days."
    }

    db.query copilot_library_setting {
      where = $db.copilot_library_setting.account_id == $account_id && $account_id != 0
      return = {type: "single"}
      output = ["id"]
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    conditional {
      if ($existing_id != 0) {
        db.patch copilot_library_setting {
          field_name = "id"
          field_value = $existing_id
          data = {updated_at: "now", max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days, updated_by_user_id: $auth.id}
        } as $_patched
      }

      else {
        db.add copilot_library_setting {
          data = {updated_at: "now", account_id: $account_id, max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days, updated_by_user_id: $auth.id}
        } as $_added
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-11"
        step       : "library_settings"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The skill library limits were changed."
        user_id    : $auth.id
        account_id : $account_id
        entity_type: "copilot_library_setting"
        entity_id  : $existing_id
        metadata   : {max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days}
      }
    } as $_logged
  }

  response = {max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days}
  tags = ["cop-11"]
}
