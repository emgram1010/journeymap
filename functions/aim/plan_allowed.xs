// AIM-1 story 08 — may this caller work on this plan? A person: always yes here (their own rules apply elsewhere). An AI member: only a plan listed in its profile's plan_ids; an empty list means no plan. Called by copilot/plan_in_business, the one rule every plan tool already asks, so a plan outside an AI member's scope answers exactly like a plan that does not exist. Never throws.
function "aim/plan_allowed" {
  input {
    int user_id
    int workspace_id
  }

  stack {
    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.user_id && $input.user_id != 0
      return = {type: "single"}
    } as $p

    var $pid {
      value = $p|get:"id":0
    }

    var $plans_val {
      value = ($p|get:"plan_ids":null) ?? []
    }

    var $plans_text {
      value = $plans_val|json_encode
    }

    var $plans_first {
      value = $plans_text|substr:0:1
    }

    var $plans {
      value = []
    }

    conditional {
      if ($plans_first == "[") {
        var.update $plans {
          value = $plans_val
        }
      }
    }

    var $hits {
      value = 0
    }

    foreach ($plans) {
      each as $pl {
        var.update $hits {
          value = $hits + ((($pl|to_int) == $input.workspace_id)|to_int)
        }
      }
    }
  }

  response = {is_ai: ($pid != 0), allowed: ($pid == 0 || $hits > 0)}
}
