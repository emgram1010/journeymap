// AIM-1 stories 05 to 07 — what an admin (a person) sees about the account's AI members: each one's name, manager, purpose, what it may do, its plans, whether it is switched off (and why), its limits, its tokens (never the token itself: label, made, last used, expires, revoked) and its activity (calls and changes today, refusals in the last 7 days). needs_manager is true when the manager is missing, switched off or no longer in the account. Names and ids only: no email is returned. Also returns the account-wide pause state and the list of things an AI member may be given.
function "aim/overview" {
  input {
    int actor_user_id
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "ai_members_list"}
    } as $admin

    var $acct {
      value = $admin.account_id
    }

    db.query ai_member_profile {
      where = $db.ai_member_profile.account_id == $acct
      return = {type: "list"}
    } as $profiles

    db.query user {
      where = $db.user.account_id == $acct
      return = {type: "list"}
      output = ["id", "name"]
    } as $users

    db.query user_status {
      where = $db.user_status.is_active == false
      return = {type: "list"}
      output = ["id", "user_id"]
    } as $off_rows

    var $names {
      value = {}
    }

    var $k {
      value = ""
    }

    foreach ($users) {
      each as $u {
        var.update $k {
          value = "u:" ~ ($u.id|to_text)
        }

        var.update $names {
          value = $names|set:$k:$u.name
        }
      }
    }

    var $off {
      value = {}
    }

    foreach ($off_rows) {
      each as $o {
        var.update $k {
          value = "u:" ~ ($o.user_id|to_text)
        }

        var.update $off {
          value = $off|set:$k:1
        }
      }
    }

    db.query agent_access_token {
      where = $db.agent_access_token.account_id == $acct
      sort = {agent_access_token.id: "desc"}
      return = {type: "list"}
    } as $tokens

    var $now_ms {
      value = now|to_int
    }

    var $day_start {
      value = $now_ms - ($now_ms % 86400000)
    }

    var $week_ago {
      value = $now_ms - 604800000
    }

    var $members {
      value = []
    }

    var $mk {
      value = ""
    }

    var $name {
      value = ""
    }

    var $manager_name {
      value = ""
    }

    var $manager_off {
      value = 0
    }

    var $my_tokens {
      value = []
    }

    var $rv {
      value = 0
    }

    var $ex {
      value = 0
    }

    foreach ($profiles) {
      each as $p {
        var.update $k {
          value = "u:" ~ ($p.user_id|to_text)
        }

        var.update $mk {
          value = "u:" ~ ($p.manager_user_id|to_text)
        }

        var.update $name {
          value = ($names|get:$k:null) ?? ""
        }

        var.update $manager_name {
          value = ($names|get:$mk:null) ?? ""
        }

        var.update $manager_off {
          value = ($off|get:$mk:null) ?? 0
        }

        var.update $my_tokens {
          value = []
        }

        foreach ($tokens) {
          each as $t {
            conditional {
              if ($t.user_id == $p.user_id) {
                var.update $rv {
                  value = ($t.revoked_at ?? 0)|to_int
                }

                var.update $ex {
                  value = ($t.expires_at ?? 0)|to_int
                }

                array.push $my_tokens {
                  value = {token_id: $t.id, label: $t.label, scope_actions: $t.scope_actions, created_at: $t.created_at, created_by_user_id: $t.created_by_user_id, last_used_at: $t.last_used_at, expires_at: $t.expires_at, revoked: ($rv != 0), live: ($rv == 0 && $ex > $now_ms)}
                }
              }
            }
          }
        }

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $p.user_id && $db.tool_call_log.created_at >= $day_start
          return = {type: "count"}
        } as $calls_today

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $p.user_id && $db.tool_call_log.created_at >= $day_start && $db.tool_call_log.kind == "write" && $db.tool_call_log.verdict == "allowed"
          return = {type: "count"}
        } as $writes_today

        db.query tool_call_log {
          where = $db.tool_call_log.user_id == $p.user_id && $db.tool_call_log.created_at >= $week_ago && $db.tool_call_log.verdict == "refused"
          return = {type: "count"}
        } as $refused_week

        array.push $members {
          value = {user_id: $p.user_id, name: $name, manager_user_id: $p.manager_user_id, manager_name: $manager_name, needs_manager: ($manager_name == "" || $manager_off == 1), purpose: $p.purpose, allowed_actions: $p.allowed_actions, plan_ids: $p.plan_ids, is_paused: $p.is_paused, paused_reason: $p.paused_reason, writes_per_hour: $p.writes_per_hour, writes_per_day: $p.writes_per_day, tokens: $my_tokens, calls_today: $calls_today, writes_today: $writes_today, refused_last_7_days: $refused_week}
        }
      }
    }

    db.query account_ai_pause {
      where = $db.account_ai_pause.account_id == $acct
      return = {type: "single"}
    } as $pause_row

    var $all_paused {
      value = ($pause_row|get:"is_paused":false) == true
    }

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $acct && $db.planner_workspace.is_archived == false
      sort = {planner_workspace.name: "asc"}
      return = {type: "list"}
      output = ["id", "name"]
    } as $plans
  }

  response = {all_paused: $all_paused, grantable: ["read", "draft_map", "draft_plan", "own_work"], members: $members, plans: $plans}
}
