// AIM-1 story 01 (threat T-7) — the app's own screens are for people. A login marked as an AI member (it has an ai_member_profile row) is refused on the journey-map and planner API groups, whatever password or sign-in link it holds: an AI member works only through its access token and the tool gate, where aim/check applies. Called by the two group middlewares for every signed-in request; one query for a person. The refusal is logged at most once an hour per login.
function "aim/assert_person_door" {
  input {
    int user_id
    text step? filters=trim
  }

  stack {
    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.user_id && $input.user_id != 0
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $p

    var $pid {
      value = $p|get:"id":0
    }

    conditional {
      if ($pid != 0) {
        var $now_ms {
          value = now|to_int
        }

        var $hour_ago {
          value = $now_ms - 3600000
        }

        db.query event_log {
          where = $db.event_log.feature == "AIM-1" && $db.event_log.step == "person_door_refused" && $db.event_log.user_id == $input.user_id && $db.event_log.created_at >= $hour_ago
          return = {type: "count"}
        } as $recent

        conditional {
          if ($recent == 0) {
            function.run "ops/log_event" {
              input = {feature: "AIM-1", step: "person_door_refused", outcome: "rejected", severity: "warn", error_code: "E-AIM-003", message: "An AI member's login tried to use the app's own screens. It was refused.", user_id: $input.user_id, account_id: ($p|get:"account_id":0), entity_type: "ai_member_profile", entity_id: $pid, correlation_id: "", duration_ms: 0, metadata: {step: $input.step}}
            } as $_ev
          }
        }
      }
    }

    precondition ($pid == 0) {
      error_type = "accessdenied"
      error = "This login is an AI member. It works through its access token, not the app. (E-AIM-003)"
    }
  }

  response = {ok: true}
}
