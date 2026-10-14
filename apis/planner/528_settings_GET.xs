// PLN-4 (US-PLN-4-01) — Read the account's cost settings, creating them
// on first use.
//
// There is no seed step at migration time (US-PLN-1-07): the first read
// is what creates the settings row and the four default models. That
// keeps new accounts free of rows nobody asked for, and means the
// defaults can change without a migration.
//
// WHAT TRIGGERS THE SEED: the absence of the SETTINGS row, not the
// absence of models. An earlier version seeded only when the account
// had zero models, which meant an account holding one stray model row
// never got the defaults at all — exactly what happened on the first
// live test. "Have these settings been set up yet?" is the real
// question, and the settings row is the thing that answers it.
//
// IDEMPOTENCY: two simultaneous first calls must not end with two
// settings rows or eight models. The unique indexes from PLN-1
// (`planner_settings(account_id)` and `planner_model(account_id,
// model_key)`) are the real backstop — they make the duplicate
// physically impossible. Each insert is wrapped so the loser of a race
// swallows the conflict, and both reads happen again at the end, so the
// response reflects what is actually stored rather than what this call
// believes it wrote.
//
// `human_hourly_rate` seeds to 0 on purpose. The UI shows a prompt to
// set it rather than inventing a plausible-looking rate (see
// DEFAULT_SETTINGS in the planner frontend).
query "settings" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    var $defaults {
      value = [
        {model_key: "claude-fable-5-1", label: "Claude Fable 5.1", input_per_1m: 10, output_per_1m: 50}
        {model_key: "claude-opus-5", label: "Claude Opus 5", input_per_1m: 5, output_per_1m: 25}
        {model_key: "claude-sonnet-5", label: "Claude Sonnet 5", input_per_1m: 2, output_per_1m: 10}
        {model_key: "claude-haiku-4-5", label: "Claude Haiku 4.5", input_per_1m: 1, output_per_1m: 5}
      ]
    }

    db.query planner_settings {
      where = $db.planner_settings.account_id == $actor.account_id
      return = {type: "list"}
    } as $existing_settings

    conditional {
      if (($existing_settings|count) == 0) {
        try_catch {
          try {
            db.add planner_settings {
              data = {account_id: $actor.account_id, currency_symbol: "$", human_hourly_rate: 0}
            } as $created_settings
          }

          catch {
            debug.log {
              value = "planner_settings already created concurrently for this account"
            }
          }
        }

        // Attempt every default. A key the account already holds is
        // rejected by the unique index and swallowed, so a stray
        // pre-existing model never blocks the rest from seeding.
        foreach ($defaults) {
          each as $m {
            try_catch {
              try {
                db.add planner_model {
                  data = {
                    account_id   : $actor.account_id
                    model_key    : $m.model_key
                    label        : $m.label
                    input_per_1m : $m.input_per_1m
                    output_per_1m: $m.output_per_1m
                    is_custom    : false
                  }
                } as $added_model
              }

              catch {
                debug.log {
                  value = "default model already present for this account"
                }
              }
            }
          }
        }

        function.run "ops/log_event" {
          input = {
            feature    : "PLN-4"
            step       : "seed_settings"
            outcome    : "success"
            severity   : "info"
            user_id    : $actor.user_id
            account_id : $actor.account_id
            entity_type: "planner_settings"
            message    : "Cost settings and default models created on first read."
          }
        }
      }
    }

    db.get planner_settings {
      field_name = "account_id"
      field_value = $actor.account_id
    } as $settings

    db.query planner_model {
      where = $db.planner_model.account_id == $actor.account_id
      sort = {planner_model.id: "asc"}
      return = {type: "list"}
    } as $models
  }

  response = {
    currency_symbol  : $settings.currency_symbol
    human_hourly_rate: $settings.human_hourly_rate
    models           : $models
  }
}
