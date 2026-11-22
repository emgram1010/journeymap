// AIM-1 — THE one check an AI member's tool call must pass, called by journey/tool_gate for every caller. A login is an AI member when it has an ai_member_profile row; anyone else gets is_ai false and ok true at the cost of one query. Never throws: returns ok, code and a friendly message, and the gate refuses in any mode. Order: account-wide pause (E-AIM-041), member switched off or paused (E-AIM-040), no active manager (E-AIM-032), a ceiling tool (E-AIM-060, counted as suspicious), a tool with no class (E-AIM-061, default deny), a class outside the member's job (E-AIM-061) or outside the token's narrower scope (E-AIM-010), then the write caps per hour and per day (E-AIM-050, E-AIM-051; reads still work). Automatic pause: the 3rd ceiling attempt in a day, or the 10th refusal in 10 minutes, switches the member off until a person switches it back on. The server decides; nothing here depends on what the AI was told.
function "aim/check" {
  input {
    int user_id
    int account_id
    text tool? filters=trim
    text kind? filters=trim
    int token_id?
  }

  stack {
    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.user_id && $input.user_id != 0
      return = {type: "single"}
    } as $p

    var $pid {
      value = $p|get:"id":0
    }

    var $is_ai {
      value = $pid != 0
    }

    var $ok {
      value = true
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    var $klass {
      value = ""
    }

    var $auto_paused {
      value = false
    }

    conditional {
      if ($is_ai) {
        function.run "aim/policy" {
          input = {tool: $input.tool}
        } as $pol

        var.update $klass {
          value = $pol.klass
        }

        var $acct {
          value = $p|get:"account_id":0
        }

        db.query account_ai_pause {
          where = $db.account_ai_pause.account_id == $acct
          return = {type: "single"}
        } as $pause_row

        var $all_paused {
          value = ($pause_row|get:"is_paused":false) == true
        }

        var $member_paused {
          value = ($p|get:"is_paused":false) == true
        }

        // The manager must be a person in the same account who is switched on.
        var $manager_id {
          value = $p|get:"manager_user_id":0
        }

        db.query user {
          where = $db.user.id == $manager_id && $db.user.account_id == $acct && $manager_id != 0
          return = {type: "single"}
          output = ["id"]
        } as $mgr

        db.query user_status {
          where = $db.user_status.user_id == $manager_id
          return = {type: "single"}
          output = ["id", "is_active"]
        } as $mgr_status

        db.query ai_member_profile {
          where = $db.ai_member_profile.user_id == $manager_id && $manager_id != 0
          return = {type: "count"}
        } as $mgr_is_ai

        var $manager_ok {
          value = (($mgr|get:"id":0) != 0) && (($mgr_status|get:"is_active":true) == true) && ($mgr_is_ai == 0)
        }

        // Is the tool's class in the member's job, and in the token's narrower scope?
        var $allowed_val {
          value = ($p|get:"allowed_actions":null) ?? []
        }

        var $allowed_text {
          value = $allowed_val|json_encode
        }

        var $allowed_first {
          value = $allowed_text|substr:0:1
        }

        var $allowed {
          value = []
        }

        conditional {
          if ($allowed_first == "[") {
            var.update $allowed {
              value = $allowed_val
            }
          }
        }

        var $in_job {
          value = 0
        }

        foreach ($allowed) {
          each as $a {
            var.update $in_job {
              value = $in_job + (($a == $klass)|to_int)
            }
          }
        }

        db.query agent_access_token {
          where = $db.agent_access_token.id == $input.token_id && $db.agent_access_token.user_id == $input.user_id && $input.token_id != 0
          return = {type: "single"}
        } as $tok

        var $scope_val {
          value = ($tok|get:"scope_actions":null) ?? []
        }

        var $scope_text {
          value = $scope_val|json_encode
        }

        var $scope_first {
          value = $scope_text|substr:0:1
        }

        var $scope {
          value = []
        }

        conditional {
          if ($scope_first == "[") {
            var.update $scope {
              value = $scope_val
            }
          }
        }

        var $scope_size {
          value = $scope|count
        }

        var $in_scope {
          value = 0
        }

        foreach ($scope) {
          each as $s {
            var.update $in_scope {
              value = $in_scope + (($s == $klass)|to_int)
            }
          }
        }

        // Counts from the audit trail (rows are written by the gate after this check).
        var $now_ms {
          value = now|to_int
        }

        var $hour_ago {
          value = $now_ms - 3600000
        }

        var $day_ago {
          value = $now_ms - 86400000
        }

        var $ten_min_ago {
          value = $now_ms - 600000
        }

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $input.user_id && $db.tool_call_log.kind == "write" && $db.tool_call_log.verdict == "allowed" && $db.tool_call_log.created_at >= $hour_ago
          return = {type: "count"}
        } as $writes_hour

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $input.user_id && $db.tool_call_log.kind == "write" && $db.tool_call_log.verdict == "allowed" && $db.tool_call_log.created_at >= $day_ago
          return = {type: "count"}
        } as $writes_day

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $input.user_id && $db.tool_call_log.verdict == "refused" && $db.tool_call_log.created_at >= $ten_min_ago
          return = {type: "count"}
        } as $refused_recent

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $input.user_id && $db.tool_call_log.code == "E-AIM-060" && $db.tool_call_log.created_at >= $day_ago
          return = {type: "count"}
        } as $suspicious_today

        var $cap_hour {
          value = $p|get:"writes_per_hour":0
        }

        conditional {
          if ($cap_hour == 0) {
            var.update $cap_hour {
              value = 60
            }
          }
        }

        var $cap_day {
          value = $p|get:"writes_per_day":0
        }

        conditional {
          if ($cap_day == 0) {
            var.update $cap_day {
              value = 400
            }
          }
        }

        conditional {
          if ($all_paused) {
            var.update $code {
              value = "E-AIM-041"
            }

            var.update $message {
              value = "AI is paused for this account. A person has to turn it back on. (E-AIM-041)"
            }
          }

          elseif ($member_paused) {
            var.update $code {
              value = "E-AIM-040"
            }

            var.update $message {
              value = "This AI member is switched off. A person has to switch it back on. (E-AIM-040)"
            }
          }

          elseif ($manager_ok == false) {
            var.update $code {
              value = "E-AIM-032"
            }

            var.update $message {
              value = "This AI member has no active manager, so it cannot work. An admin has to name one. (E-AIM-032)"
            }
          }

          elseif ($klass == "ceiling") {
            var.update $code {
              value = "E-AIM-060"
            }

            var.update $message {
              value = "An AI member can never do this. A person has to. (E-AIM-060)"
            }
          }

          elseif ($klass == "") {
            var.update $code {
              value = "E-AIM-061"
            }

            var.update $message {
              value = "This tool isn't open to AI members. (E-AIM-061)"
            }
          }

          elseif ($in_job == 0) {
            var.update $code {
              value = "E-AIM-063"
            }

            var.update $message {
              value = "That is outside this AI member's job. An admin can change what it may do. (E-AIM-063)"
            }
          }

          elseif ($scope_size > 0 && $in_scope == 0) {
            var.update $code {
              value = "E-AIM-010"
            }

            var.update $message {
              value = "That is outside what this access token may do. (E-AIM-010)"
            }
          }

          elseif ($input.kind == "write" && $writes_hour >= $cap_hour) {
            var.update $code {
              value = "E-AIM-050"
            }

            var.update $message {
              value = "This AI member has reached its hourly limit for changes. Reading still works. (E-AIM-050)"
            }
          }

          elseif ($input.kind == "write" && $writes_day >= $cap_day) {
            var.update $code {
              value = "E-AIM-051"
            }

            var.update $message {
              value = "This AI member has reached its daily limit for changes. Reading still works. (E-AIM-051)"
            }
          }
        }

        var.update $ok {
          value = $code == ""
        }

        var $scope_refusal {
          value = ($code == "E-AIM-060" || $code == "E-AIM-061" || $code == "E-AIM-063" || $code == "E-AIM-010")
        }

        var $pause_reason {
          value = ""
        }

        conditional {
          if ($code == "E-AIM-060" && $suspicious_today >= 2) {
            var.update $pause_reason {
              value = "Paused automatically: 3 attempts in a day at something no AI may do."
            }
          }

          elseif ($scope_refusal && $refused_recent >= 9) {
            var.update $pause_reason {
              value = "Paused automatically: 10 refused calls in 10 minutes."
            }
          }
        }

        conditional {
          if ($pause_reason != "") {
            db.patch ai_member_profile {
              field_name = "id"
              field_value = $pid
              data = {is_paused: true, paused_reason: $pause_reason, paused_at: "now", updated_at: "now"}
            } as $paused_row

            var.update $auto_paused {
              value = true
            }

            function.run "ops/log_event" {
              input = {feature: "AIM-1", step: "auto_paused", outcome: "rejected", severity: "error", error_code: $code, message: $pause_reason, user_id: $input.user_id, account_id: $acct, entity_type: "ai_member_profile", entity_id: $pid, correlation_id: "", duration_ms: 0, metadata: {tool: $input.tool, manager_user_id: $manager_id}}
            } as $_paused_ev
          }
        }

        // One event per refusal for scope and ceiling (they are rare and each matters). For a
        // pause, a missing manager or a cap, one event an hour is enough: the reason does not change.
        db.query event_log {
          where = $db.event_log.feature == "AIM-1" && $db.event_log.user_id == $input.user_id && $db.event_log.error_code == $code && $db.event_log.created_at >= $hour_ago
          return = {type: "count"}
        } as $same_logged

        var $log_it {
          value = ($ok == false) && ($scope_refusal || $same_logged == 0) && ($refused_recent < 30)
        }

        var $step {
          value = "refused"
        }

        conditional {
          if ($code == "E-AIM-060") {
            var.update $step {
              value = "suspicious_attempt"
            }
          }

          elseif ($code == "E-AIM-050" || $code == "E-AIM-051") {
            var.update $step {
              value = "capped"
            }
          }
        }

        conditional {
          if ($log_it) {
            function.run "ops/log_event" {
              input = {feature: "AIM-1", step: $step, outcome: "rejected", severity: "warn", error_code: $code, message: $message, user_id: $input.user_id, account_id: $acct, entity_type: "ai_member_profile", entity_id: $pid, correlation_id: "", duration_ms: 0, metadata: {tool: $input.tool, klass: $klass, token_id: $input.token_id, manager_user_id: $manager_id}}
            } as $_refused_ev
          }
        }
      }
    }
  }

  response = {is_ai: $is_ai, ok: $ok, code: $code, message: $message, klass: $klass, auto_paused: $auto_paused, profile_id: $pid}
}
