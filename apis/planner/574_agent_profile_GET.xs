// PLAN-2 (US-PLAN-2-02) — The account's agent profiles.
//
// TWO TENANCY PATHS MERGED INTO ONE LIST, same reasoning as
// `assert_agent_profile`: a person profile's account comes from
// `user.account_id`; an AI profile (user_id = 0) carries its own
// `account_id`. This is the read-side mirror of that same rule.
//
// Ineligible profiles are hidden by default — same "what can I use
// right now" default `GET template` already uses for archived
// templates.
query "agent-profile" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    bool include_ineligible?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query user {
      where = $db.user.account_id == $actor.account_id
      return = {type: "list"}
    } as $account_users

    var $account_user_ids {
      value = []
    }

    foreach ($account_users) {
      each as $u {
        array.push $account_user_ids {
          value = $u.id
        }
      }
    }

    db.query agent_profile {
      where = (($db.agent_profile.user_id in $account_user_ids) || ($db.agent_profile.user_id == 0 && $db.agent_profile.account_id == $actor.account_id)) && ($input.include_ineligible == true || $db.agent_profile.is_eligible == true)
      sort = {agent_profile.created_at: "desc"}
      return = {type: "list"}
    } as $profiles

    // Display name for a person profile comes from user.name — the
    // profile itself never stores one, same split as planner_agent's
    // own rule that an AI's name is local and a person's isn't.
    var $names {
      value = {}
    }

    var $nkey {
      value = ""
    }

    foreach ($account_users) {
      each as $u {
        var.update $nkey {
          value = $u.id|to_text
        }

        var.update $names {
          value = $names|set:$nkey:$u.name
        }
      }
    }

    var $result {
      value = []
    }

    var $rkey {
      value = ""
    }

    var $display_name {
      value = ""
    }

    foreach ($profiles) {
      each as $p {
        var.update $display_name {
          value = $p.name
        }

        conditional {
          if ($p.user_id != 0) {
            var.update $rkey {
              value = $p.user_id|to_text
            }

            var.update $display_name {
              value = ($names|get:$rkey:"")
            }
          }
        }

        array.push $result {
          value = {profile: $p, display_name: $display_name}
        }
      }
    }
  }

  response = {profiles: $result}
}
