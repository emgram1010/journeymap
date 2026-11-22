// AIM-1 story 06 — an admin (a person) switches one AI member off or back on. Off: its next call is refused whatever token it comes with, and every live token it holds is revoked (each by its own id). On: it may work again, but old tokens stay revoked, so a new token has to be made. Nothing it did is deleted. Also the way out of an automatic pause.
function "aim/switch_member" {
  input {
    int actor_user_id
    int target_user_id
    bool turn_on?
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "ai_member_switch"}
    } as $admin

    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.target_user_id && $db.ai_member_profile.account_id == $admin.account_id
      return = {type: "single"}
    } as $p

    var $pid {
      value = $p|get:"id":0
    }

    precondition ($pid != 0) {
      error_type = "notfound"
      error = "AI member not found. (E-AIM-002)"
    }

    var $on {
      value = $input.turn_on == true
    }

    var $manager_id {
      value = $p|get:"manager_user_id":0
    }

    var $revoked {
      value = 0
    }

    var $step {
      value = "ai_member_switched_off"
    }

    conditional {
      if ($on) {
        var.update $step {
          value = "ai_member_switched_on"
        }

        db.patch ai_member_profile {
          field_name = "id"
          field_value = $pid
          data = {is_paused: false, paused_reason: "", updated_at: "now", updated_by_user_id: $input.actor_user_id}
        } as $on_row
      }

      else {
        db.patch ai_member_profile {
          field_name = "id"
          field_value = $pid
          data = {is_paused: true, paused_reason: "Switched off by an admin.", paused_at: "now", updated_at: "now", updated_by_user_id: $input.actor_user_id}
        } as $off_row

        db.query agent_access_token {
          where = $db.agent_access_token.user_id == $input.target_user_id
          return = {type: "list"}
        } as $tokens

        var $staged {
          value = []
        }

        var $rv {
          value = 0
        }

        foreach ($tokens) {
          each as $t {
            var.update $rv {
              value = ($t.revoked_at ?? 0)|to_int
            }

            array.push $staged {
              value = {id: $t.id, live: ($rv == 0)}
            }
          }
        }

        foreach ($staged) {
          each as $s {
            conditional {
              if ($s.live == true) {
                db.patch agent_access_token {
                  field_name = "id"
                  field_value = $s.id
                  data = {revoked_at: "now", revoked_by_user_id: $input.actor_user_id}
                } as $revoked_row

                math.add $revoked {
                  value = 1
                }
              }
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {feature: "AIM-1", step: $step, outcome: "success", severity: "warn", error_code: "", message: "An AI member was switched on or off by an admin.", user_id: $input.actor_user_id, account_id: $admin.account_id, entity_type: "ai_member_profile", entity_id: $pid, correlation_id: "", duration_ms: 0, metadata: {ai_user_id: $input.target_user_id, tokens_revoked: $revoked, manager_user_id: $manager_id}}
    } as $_ev
  }

  response = {user_id: $input.target_user_id, is_on: $on, tokens_revoked: $revoked}
}
