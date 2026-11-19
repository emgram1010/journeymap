// COP-11 story 03 — an account admin changes the three library limits. A signed-in person only
// (never an AI identity). Server bounds: items 10-200, words 1000-20000, days 7-365; outside them the
// save is refused with a plain message and nothing changes. One row per account, edited in place
// (unique account_id); no row = defaults 50 / 4000 / 30. Logged as a success event.
// COP-9-05 adds the trial rule's two numbers: trusted after trial_min_uses uses (1-50, default 5),
// switched off after trial_max_overrides owner overrides (1-10, default 2). Optional: 0 = not sent,
// keep what is saved (older callers send only the first three).
// COP-13 part B adds step_up_daily_cap: the most stronger-model requests per 24 hours (1-20, default 5).
// Optional the same way: 0 = keep what is saved.
query "copilot/library_settings" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int max_active_items?
    int max_load_words?
    int stale_after_days?
    int trial_min_uses?
    int trial_max_overrides?
    int step_up_daily_cap?
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

    precondition ($input.trial_min_uses == 0 || ($input.trial_min_uses >= 1 && $input.trial_min_uses <= 50)) {
      error_type = "inputerror"
      error = "Uses before a skill is trusted must be between 1 and 50."
    }

    precondition ($input.trial_max_overrides == 0 || ($input.trial_max_overrides >= 1 && $input.trial_max_overrides <= 10)) {
      error_type = "inputerror"
      error = "Overrides before a trial skill is switched off must be between 1 and 10."
    }

    precondition ($input.step_up_daily_cap == 0 || ($input.step_up_daily_cap >= 1 && $input.step_up_daily_cap <= 20)) {
      error_type = "inputerror"
      error = "Stronger-model uses per day must be between 1 and 20."
    }

    db.query copilot_library_setting {
      where = $db.copilot_library_setting.account_id == $account_id && $account_id != 0
      return = {type: "single"}
      output = ["id", "trial_min_uses", "trial_max_overrides", "step_up_daily_cap"]
    } as $existing

    var $step_cap {
      value = (($input.step_up_daily_cap != 0) ? $input.step_up_daily_cap : (($existing|get:"step_up_daily_cap":0) ?? 0))
    }

    var $min_uses {
      value = (($input.trial_min_uses != 0) ? $input.trial_min_uses : (($existing|get:"trial_min_uses":0) ?? 0))
    }

    var $max_overrides {
      value = (($input.trial_max_overrides != 0) ? $input.trial_max_overrides : (($existing|get:"trial_max_overrides":0) ?? 0))
    }

    var $existing_id {
      value = $existing|get:"id":0
    }

    conditional {
      if ($existing_id != 0) {
        db.patch copilot_library_setting {
          field_name = "id"
          field_value = $existing_id
          data = {updated_at: "now", max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days, trial_min_uses: $min_uses, trial_max_overrides: $max_overrides, step_up_daily_cap: $step_cap, updated_by_user_id: $auth.id}
        } as $_patched
      }

      else {
        db.add copilot_library_setting {
          data = {updated_at: "now", account_id: $account_id, max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days, trial_min_uses: $min_uses, trial_max_overrides: $max_overrides, step_up_daily_cap: $step_cap, updated_by_user_id: $auth.id}
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
        metadata   : {max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days, trial_min_uses: $min_uses, trial_max_overrides: $max_overrides, step_up_daily_cap: $step_cap}
      }
    } as $_logged
  }

  response = {max_active_items: $input.max_active_items, max_load_words: $input.max_load_words, stale_after_days: $input.stale_after_days, trial_min_uses: $min_uses, trial_max_overrides: $max_overrides, step_up_daily_cap: $step_cap}
  tags = ["cop-11"]
}
