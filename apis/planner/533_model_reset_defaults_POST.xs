// PLN-4 (US-PLN-4-06) — Put the four built-in models back. Admin only.
//
// WHAT IT DOES NOT DO IS THE POINT: it never deletes anything, and it
// never touches a custom model. It only adds back seeded models that
// have gone missing, and resets the prices of the seeded ones that are
// still there. Someone reaching for "reset to defaults" after deleting
// something by accident must not lose a second thing in the process.
//
// Matching is by `model_key`, which is why PLN-4's update endpoint
// refuses to let the key change.
//
// A seeded model that was edited gets its default prices back — that is
// what "reset" means. A custom model with the same key as a default
// cannot exist, because the key is unique per account.
query "model/reset-defaults" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_admin" {
      input = {role: $actor.role}
    }

    var $defaults {
      value = [
        {model_key: "claude-fable-5-1", label: "Claude Fable 5.1", input_per_1m: 10, output_per_1m: 50}
        {model_key: "claude-opus-5", label: "Claude Opus 5", input_per_1m: 5, output_per_1m: 25}
        {model_key: "claude-sonnet-5", label: "Claude Sonnet 5", input_per_1m: 2, output_per_1m: 10}
        {model_key: "claude-haiku-4-5", label: "Claude Haiku 4.5", input_per_1m: 1, output_per_1m: 5}
      ]
    }

    var $recreated {
      value = []
    }

    var $repriced {
      value = []
    }

    foreach ($defaults) {
      each as $m {
        db.query planner_model {
          where = $db.planner_model.account_id == $actor.account_id && $db.planner_model.model_key == $m.model_key
          return = {type: "list"}
        } as $found

        conditional {
          if (($found|count) == 0) {
            db.add planner_model {
              data = {
                account_id   : $actor.account_id
                model_key    : $m.model_key
                label        : $m.label
                input_per_1m : $m.input_per_1m
                output_per_1m: $m.output_per_1m
                is_custom    : false
              }
            } as $added

            array.push $recreated {
              value = $m.model_key
            }
          }

          else {
            var $row {
              value = $found|first
            }

            // Only a seeded row is repriced. A custom model is left
            // exactly as the account set it.
            conditional {
              if ($row.is_custom == false) {
                db.patch planner_model {
                  field_name = "id"
                  field_value = $row.id
                  data = {
                    label        : $m.label
                    input_per_1m : $m.input_per_1m
                    output_per_1m: $m.output_per_1m
                    updated_at   : "now"
                  }
                } as $patched

                array.push $repriced {
                  value = $m.model_key
                }
              }
            }
          }
        }
      }
    }

    db.query planner_model {
      where = $db.planner_model.account_id == $actor.account_id
      sort = {planner_model.id: "asc"}
      return = {type: "list"}
    } as $models

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-4"
        step          : "reset_default_models"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_model"
        correlation_id: $input.correlation_id
        message       : "Default models restored."
        metadata      : {recreated: $recreated, repriced: $repriced}
      }
    }
  }

  response = {
    recreated: $recreated
    repriced : $repriced
    models   : $models
  }
}
