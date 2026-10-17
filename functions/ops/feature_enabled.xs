// GOV-1 (US-GOV-1-12) — Read one feature flag for one account.
//
// The rule is deliberately blunt: a flag is ON only when there is a row
// for that account saying so. No row, unknown key, or anything odd =
// OFF. That means a feature under construction can never be live by
// accident, and turning a flag off always restores the old behaviour.
//
// Flags in the MVP: required_fields_ui (AUTH-1), publish_gate (PUB-1).
function "ops/feature_enabled" {
  description = "True only when an account_feature_flag row says this flag is on for this account. Defaults to off."

  input {
    int account_id
    text flag_key filters=trim
  }

  stack {
    var $enabled {
      value = false
    }

    conditional {
      if ($input.account_id != 0 && $input.flag_key != null && $input.flag_key != "") {
        db.query account_feature_flag {
          where = $db.account_feature_flag.account_id == $input.account_id && $db.account_feature_flag.flag_key == $input.flag_key
          return = {type: "list"}
        } as $rows

        foreach ($rows) {
          each as $row {
            conditional {
              if ($row.enabled == true) {
                var.update $enabled {
                  value = true
                }
              }
            }
          }
        }
      }
    }
  }

  response = {enabled: $enabled}
}
