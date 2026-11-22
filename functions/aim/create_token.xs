// AIM-1 story 03 — an admin (a person) makes an access token for one AI member. The token is returned ONCE and only its SHA-256 hash is stored; it is never written to a log. At most 2 live tokens a member (E-AIM-013). scope_actions may narrow what this token may do; every entry must already be in the member's own job (E-AIM-014), and the gate takes the overlap, so a token is never wider than the member. Tokens are for AI members only (E-AIM-012). A token lasts 90 days (decision D-4, taken 2026-11-21).
function "aim/create_token" {
  input {
    int actor_user_id
    int target_user_id
    text label? filters=trim
    json scope_actions?
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "ai_token_create"}
    } as $admin

    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.target_user_id && $db.ai_member_profile.account_id == $admin.account_id
      return = {type: "single"}
    } as $p

    var $pid {
      value = $p|get:"id":0
    }

    precondition ($pid != 0) {
      error_type = "inputerror"
      error = "Access tokens are for AI members only. Make this login an AI member first. (E-AIM-012)"
    }

    var $paused {
      value = ($p|get:"is_paused":false) == true
    }

    precondition ($paused == false) {
      error_type = "inputerror"
      error = "This AI member is switched off. Switch it back on before making a token. (E-AIM-016)"
    }

    var $now_ms {
      value = now|to_int
    }

    db.query agent_access_token {
      where = $db.agent_access_token.user_id == $input.target_user_id
      return = {type: "list"}
    } as $tokens

    var $live {
      value = 0
    }

    var $rv {
      value = 0
    }

    var $ex {
      value = 0
    }

    foreach ($tokens) {
      each as $t {
        var.update $rv {
          value = ($t.revoked_at ?? 0)|to_int
        }

        var.update $ex {
          value = ($t.expires_at ?? 0)|to_int
        }

        var.update $live {
          value = $live + (($rv == 0 && $ex > $now_ms)|to_int)
        }
      }
    }

    precondition ($live < 2) {
      error_type = "inputerror"
      error = "This AI member already has 2 live tokens. Revoke one first. (E-AIM-013)"
    }

    var $label {
      value = (($input.label ?? "")|trim)|substr:0:60
    }

    var $label_html {
      value = (($label|contains:"<") || ($label|contains:">"))
    }

    precondition ($label_html == false) {
      error_type = "inputerror"
      error = "A token's name cannot contain < or >. (E-AIM-015)"
    }

    var $scope_val {
      value = $input.scope_actions ?? []
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

    var $job_val {
      value = ($p|get:"allowed_actions":null) ?? []
    }

    var $job_text {
      value = $job_val|json_encode
    }

    var $job_first {
      value = $job_text|substr:0:1
    }

    var $job {
      value = []
    }

    conditional {
      if ($job_first == "[") {
        var.update $job {
          value = $job_val
        }
      }
    }

    var $inside {
      value = 0
    }

    foreach ($scope) {
      each as $s {
        foreach ($job) {
          each as $j {
            var.update $inside {
              value = $inside + (($s == $j)|to_int)
            }
          }
        }
      }
    }

    var $scope_count {
      value = $scope|count
    }

    precondition ($inside == $scope_count) {
      error_type = "inputerror"
      error = "A token can only be narrower than the AI member's own job, never wider. (E-AIM-014)"
    }

    security.create_uuid as $u1

    security.create_uuid as $u2

    var $part1 {
      value = $u1|replace:"-":""
    }

    var $part2 {
      value = $u2|replace:"-":""
    }

    var $token {
      value = "emg_ai_" ~ $part1 ~ $part2
    }

    var $hash {
      value = $token|sha256
    }

    var $expires {
      value = $now_ms + 7776000000
    }

    var $manager_id {
      value = $p|get:"manager_user_id":0
    }

    db.add agent_access_token {
      data = {created_at: "now", account_id: $admin.account_id, user_id: $input.target_user_id, token_hash: $hash, label: $label, scope_actions: $scope, created_by_user_id: $input.actor_user_id, expires_at: $expires}
    } as $row

    function.run "ops/log_event" {
      input = {feature: "AIM-1", step: "agent_token_created", outcome: "success", severity: "warn", error_code: "", message: "An access token was made for an AI member. Its manager should know.", user_id: $input.actor_user_id, account_id: $admin.account_id, entity_type: "agent_access_token", entity_id: $row.id, correlation_id: "", duration_ms: 0, metadata: {ai_user_id: $input.target_user_id, manager_user_id: $manager_id, scope_actions: $scope}}
    } as $_ev
  }

  response = {token_id: $row.id, token: $token, label: $label, scope_actions: $scope, expires_at: $expires, expires_in_days: 90}
}
