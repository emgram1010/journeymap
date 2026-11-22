// AIM-1 stories 01 and 05 — make a login an AI member, or change its job. An admin (a person) names the login, a human manager, a one-line purpose, what it may do (from the fixed list in aim/policy: read, draft_map, draft_plan, own_work; a ceiling action is never offered and is refused if sent) and which plans it may work on. Nothing is saved unless all of it is valid. The login must be an ordinary member of the same account: never an admin, the owner, the caller, or the copilot. The manager must be a switched-on person in the same account. Caps: writes per hour (default 60, at most 200) and per day (default 400, at most 2000). Every save is logged with before and after (ids and action names only).
function "aim/save_profile" {
  input {
    int actor_user_id
    int target_user_id
    int manager_user_id
    text purpose? filters=trim
    json allowed_actions?
    json plan_ids?
    int writes_per_hour?
    int writes_per_day?
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "ai_member_save"}
    } as $admin

    var $acct {
      value = $admin.account_id
    }

    function.run "usr/account_rank" {
      input = {user_id: $input.target_user_id}
    } as $t_rank

    precondition ($t_rank.found == true && $t_rank.account_id == $acct) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    db.query ai_identity {
      where = $db.ai_identity.user_id == $input.target_user_id
      return = {type: "count"}
    } as $t_copilot

    precondition ($t_rank.rank == "member" && $input.target_user_id != $input.actor_user_id && $t_copilot == 0) {
      error_type = "inputerror"
      error = "Only an ordinary member's login can be an AI member: not an admin, the owner, yourself or the copilot. (E-AIM-001)"
    }

    precondition ($input.manager_user_id != 0) {
      error_type = "inputerror"
      error = "An AI member needs a manager: a person who answers for it. (E-AIM-030)"
    }

    function.run "usr/account_rank" {
      input = {user_id: $input.manager_user_id}
    } as $m_rank

    db.query user_status {
      where = $db.user_status.user_id == $input.manager_user_id
      return = {type: "single"}
      output = ["id", "is_active"]
    } as $m_status

    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.manager_user_id
      return = {type: "count"}
    } as $m_is_member

    var $manager_ok {
      value = ($m_rank.found == true) && ($m_rank.account_id == $acct) && ($m_rank.is_ai == false) && ($m_is_member == 0) && (($m_status|get:"is_active":true) == true) && ($input.manager_user_id != $input.target_user_id)
    }

    precondition ($manager_ok) {
      error_type = "inputerror"
      error = "The manager must be a switched-on person in your account, not an AI. (E-AIM-031)"
    }

    var $purpose {
      value = ($input.purpose ?? "")|trim
    }

    var $purpose_len {
      value = $purpose|strlen
    }

    var $purpose_html {
      value = (($purpose|contains:"<") || ($purpose|contains:">"))
    }

    precondition ($purpose != "" && $purpose_len <= 200 && $purpose_html == false) {
      error_type = "inputerror"
      error = "Say in one line what this AI member is for (up to 200 characters, no < or >). (E-AIM-033)"
    }

    // What it may do: a non-empty list, every entry one of the grantable four.
    var $act_val {
      value = $input.allowed_actions ?? []
    }

    var $act_text {
      value = $act_val|json_encode
    }

    var $act_first {
      value = $act_text|substr:0:1
    }

    var $actions {
      value = []
    }

    conditional {
      if ($act_first == "[") {
        var.update $actions {
          value = $act_val
        }
      }
    }

    var $good_actions {
      value = 0
    }

    var $is_good {
      value = false
    }

    foreach ($actions) {
      each as $a {
        var.update $is_good {
          value = ($a == "read") || ($a == "draft_map") || ($a == "draft_plan") || ($a == "own_work")
        }

        var.update $good_actions {
          value = $good_actions + ($is_good|to_int)
        }
      }
    }

    var $action_count {
      value = $actions|count
    }

    precondition ($action_count > 0 && $action_count <= 4 && $good_actions == $action_count) {
      error_type = "inputerror"
      error = "Choose what it may do from: read, draft_map, draft_plan, own_work. Nothing else can be given to an AI member. (E-AIM-034)"
    }

    // Which plans: every id must be a plan of this account.
    var $plan_val {
      value = $input.plan_ids ?? []
    }

    var $plan_text {
      value = $plan_val|json_encode
    }

    var $plan_first {
      value = $plan_text|substr:0:1
    }

    var $plans {
      value = []
    }

    conditional {
      if ($plan_first == "[") {
        var.update $plans {
          value = $plan_val
        }
      }
    }

    var $plan_ids {
      value = [-1]
    }

    var $plan_clean {
      value = []
    }

    var $one_plan {
      value = 0
    }

    foreach ($plans) {
      each as $pl {
        var.update $one_plan {
          value = $pl|to_int
        }

        array.push $plan_ids {
          value = $one_plan
        }

        array.push $plan_clean {
          value = $one_plan
        }
      }
    }

    db.query planner_workspace {
      where = $db.planner_workspace.id in $plan_ids && $db.planner_workspace.account_id == $acct
      return = {type: "count"}
    } as $plans_found

    var $plan_count {
      value = $plan_clean|count
    }

    precondition ($plan_count <= 50 && $plans_found == $plan_count) {
      error_type = "inputerror"
      error = "One of those plans isn't in your account, or a plan is listed twice. (E-AIM-035)"
    }

    var $cap_hour {
      value = $input.writes_per_hour ?? 0
    }

    var $cap_day {
      value = $input.writes_per_day ?? 0
    }

    conditional {
      if ($cap_hour == 0) {
        var.update $cap_hour {
          value = 60
        }
      }
    }

    conditional {
      if ($cap_day == 0) {
        var.update $cap_day {
          value = 400
        }
      }
    }

    precondition ($cap_hour >= 1 && $cap_hour <= 200 && $cap_day >= 1 && $cap_day <= 2000) {
      error_type = "inputerror"
      error = "Limits: up to 200 changes an hour and 2000 a day. (E-AIM-052)"
    }

    db.query ai_member_profile {
      where = $db.ai_member_profile.user_id == $input.target_user_id
      return = {type: "single"}
    } as $existing

    var $pid {
      value = $existing|get:"id":0
    }

    var $before {
      value = {manager_user_id: ($existing|get:"manager_user_id":0), allowed_actions: ($existing|get:"allowed_actions":null), plan_ids: ($existing|get:"plan_ids":null)}
    }

    var $step {
      value = "ai_member_created"
    }

    conditional {
      if ($pid == 0) {
        db.add ai_member_profile {
          data = {created_at: "now", updated_at: "now", account_id: $acct, user_id: $input.target_user_id, manager_user_id: $input.manager_user_id, purpose: $purpose, allowed_actions: $actions, plan_ids: $plan_clean, is_paused: false, paused_reason: "", writes_per_hour: $cap_hour, writes_per_day: $cap_day, updated_by_user_id: $input.actor_user_id}
        } as $made

        var.update $pid {
          value = $made.id
        }
      }

      else {
        var.update $step {
          value = "ai_member_scope_changed"
        }

        // A json column merges on patch: clear the two lists first, then write them.
        db.patch ai_member_profile {
          field_name = "id"
          field_value = $pid
          data = {allowed_actions: null, plan_ids: null}
        } as $cleared

        db.patch ai_member_profile {
          field_name = "id"
          field_value = $pid
          data = {updated_at: "now", manager_user_id: $input.manager_user_id, purpose: $purpose, allowed_actions: $actions, plan_ids: $plan_clean, writes_per_hour: $cap_hour, writes_per_day: $cap_day, updated_by_user_id: $input.actor_user_id}
        } as $saved
      }
    }

    function.run "ops/log_event" {
      input = {feature: "AIM-1", step: $step, outcome: "success", severity: "info", error_code: "", message: "An AI member's manager, purpose or scope was saved.", user_id: $input.actor_user_id, account_id: $acct, entity_type: "ai_member_profile", entity_id: $pid, correlation_id: "", duration_ms: 0, metadata: {ai_user_id: $input.target_user_id, before: $before, manager_user_id: $input.manager_user_id, allowed_actions: $actions, plan_ids: $plan_clean}}
    } as $_ev
  }

  response = {profile_id: $pid, user_id: $input.target_user_id, manager_user_id: $input.manager_user_id, purpose: $purpose, allowed_actions: $actions, plan_ids: $plan_clean, writes_per_hour: $cap_hour, writes_per_day: $cap_day}
}
