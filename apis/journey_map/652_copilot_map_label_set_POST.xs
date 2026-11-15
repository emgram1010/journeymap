// COP-4 story 04 — an account admin labels a map: kind (insight / runnable) and whether it is tested
// (real work proved it). Only a person can mark a map tested; the copilot cannot (E-COP-046 in its
// tool). Unmarking tested clears the date. The screen always sends both kind and tested.
query "copilot/map_label_set" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id?
    text kind? filters=trim|lower
    bool tested?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/map_label_set"
        entity_id    : 0
      }
    } as $admin_user

    var $account_id {
      value = $admin_user.account_id
    }

    db.query journey_map {
      where = $db.journey_map.id == $input.journey_map_id
      return = {type: "single"}
      output = ["id", "account_id", "journey_architecture"]
    } as $map

    precondition ($input.journey_map_id != 0 && ($map|get:"account_id":0) == $account_id) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($input.kind == "" || $input.kind == "insight" || $input.kind == "runnable") {
      error_type = "inputerror"
      error = "kind is insight or runnable; made_by is copilot_research, copilot_strategy or copilot_draft. (E-COP-046)"
    }

    db.query copilot_map_profile {
      where = $db.copilot_map_profile.journey_map_id == $input.journey_map_id
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    var $kind {
      value = ($existing|get:"kind":"")
    }

    conditional {
      if ($input.kind != "") {
        var.update $kind {
          value = $input.kind
        }
      }
    }

    var $now_ms {
      value = now|to_int
    }

    var $tested_value {
      value = 0
    }

    conditional {
      if ($input.tested == true) {
        var.update $tested_value {
          value = $now_ms
        }
      }
    }

    conditional {
      if ($existing_id == 0) {
        db.add copilot_map_profile {
          data = {journey_map_id: $input.journey_map_id, account_id: $account_id, journey_architecture_id: ($map|get:"journey_architecture":0), kind: $kind, made_by: "person", sources: [], tested_since: $tested_value, updated_by_user_id: $auth.id, updated_at: "now"}
        } as $_added
      }

      else {
        db.patch copilot_map_profile {
          field_name = "id"
          field_value = $existing_id
          data = {kind: $kind, tested_since: $tested_value, updated_by_user_id: $auth.id, updated_at: "now"}
        } as $_patched
      }
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-4"
        step       : "map_label_changed"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The owner changed a map's label."
        user_id    : $auth.id
        account_id : $account_id
        entity_type: "journey_map"
        entity_id  : $input.journey_map_id
        metadata   : {kind: $kind, tested: $input.tested}
      }
    } as $_logged
  }

  response = {journey_map_id: $input.journey_map_id, kind: $kind, tested: $input.tested}
  tags = ["cop-4"]
}
