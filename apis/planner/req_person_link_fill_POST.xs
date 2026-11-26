// REQ-1 story 03 — The one-time fill for people already on plans: tie each person who has a LOGIN to the profile of that login, when the login has EXACTLY ONE. ADMIN PERSON ONLY. It REPORTS FIRST: `apply` is a bool where an omitted value is false, so by default nothing is written and the answer is the counts (the story's "reports counts before it writes"); send apply = true to write. Only the caller's own account, only plans that are not archived, only people with no link yet. Never by name. People with no login are counted as "no login" (an admin ties or makes their profile by hand), a login with TWO profiles is counted and listed (nothing linked), a login with no profile is counted as "no profile yet". SAFE TO RUN TWICE: people already linked are skipped, so the second run changes nothing. TWO PASSES: the first marks every person with a 0/1/2/3 class from values set before the pass; the second acts only on the person's OWN class (a conditional that reads a variable updated earlier in the same iteration silently loses its writes, CLAUDE.md). One summary event with the counts: plan_person.fill. Every input is passed to function.run explicitly.
query "person-link-fill" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    bool apply?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "person_link_fill", entity_type: "account", entity_id: $actor.account_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "person_link/fill", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $actor.account_id && $db.planner_workspace.is_archived == false
      return = {type: "list"}
      output = ["id", "name"]
    } as $plans

    var $plan_ids {
      value = [-1]
    }

    foreach ($plans) {
      each as $w {
        array.push $plan_ids {
          value = $w.id
        }
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id in $plan_ids
      return = {type: "list"}
      output = ["id", "workspace_id", "name", "user_id"]
    } as $agents

    var $agent_ids {
      value = [-1]
    }

    foreach ($agents) {
      each as $a {
        array.push $agent_ids {
          value = $a.id
        }
      }
    }

    db.query planner_agent_profile {
      where = $db.planner_agent_profile.planner_agent_id in $agent_ids
      return = {type: "list"}
      output = ["planner_agent_id"]
    } as $links

    var $linked_set {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($links) {
      each as $l {
        var.update $t {
          value = $l.planner_agent_id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $linked_set {
          value = $linked_set|set:$k:1
        }
      }
    }

    db.query user {
      where = $db.user.account_id == $actor.account_id
      return = {type: "list"}
      output = ["id"]
    } as $account_users

    var $account_user_ids {
      value = [-1]
    }

    foreach ($account_users) {
      each as $u {
        array.push $account_user_ids {
          value = $u.id
        }
      }
    }

    db.query agent_profile {
      where = $db.agent_profile.user_id in $account_user_ids
      return = {type: "list"}
      output = ["id", "user_id"]
    } as $profiles

    var $login_count {
      value = {}
    }

    var $login_profile {
      value = {}
    }

    var $n {
      value = 0
    }

    foreach ($profiles) {
      each as $p {
        var.update $t {
          value = $p.user_id|to_text
        }

        var.update $k {
          value = "l:" ~ $t
        }

        var.update $n {
          value = (($login_count|get:$k:null) ?? 0) + 1
        }

        var.update $login_count {
          value = $login_count|set:$k:$n
        }

        var.update $login_profile {
          value = $login_profile|set:$k:$p.id
        }
      }
    }

    // Pass 1: a class per person, from values set before the pass.
    //   0 already linked · 1 will be linked (exactly one profile for the login) · 2 no login · 3 login has no profile yet · 4 login has several profiles
    var $classed {
      value = []
    }

    var $already {
      value = 0
    }

    var $uid {
      value = 0
    }

    var $cnt {
      value = 0
    }

    var $pid {
      value = 0
    }

    var $cls {
      value = 0
    }

    var $has_login {
      value = 0
    }

    var $no_login_flag {
      value = 0
    }

    var $one_profile {
      value = 0
    }

    var $zero_profiles {
      value = 0
    }

    var $many_profiles {
      value = 0
    }

    var $not_linked {
      value = 0
    }

    foreach ($agents) {
      each as $a {
        var.update $t {
          value = $a.id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $already {
          value = ($linked_set|get:$k:null) ?? 0
        }

        var.update $uid {
          value = $a.user_id ?? 0
        }

        var.update $t {
          value = $uid|to_text
        }

        var.update $k {
          value = "l:" ~ $t
        }

        var.update $cnt {
          value = ($login_count|get:$k:null) ?? 0
        }

        var.update $pid {
          value = ($login_profile|get:$k:null) ?? 0
        }

        var.update $has_login {
          value = ($uid != 0)|to_int
        }

        var.update $no_login_flag {
          value = ($uid == 0)|to_int
        }

        var.update $one_profile {
          value = ($cnt == 1)|to_int
        }

        var.update $zero_profiles {
          value = ($cnt == 0)|to_int
        }

        var.update $many_profiles {
          value = ($cnt > 1)|to_int
        }

        var.update $not_linked {
          value = ($already == 0)|to_int
        }

        var.update $cls {
          value = $not_linked * ($has_login * $one_profile + $no_login_flag * 2 + $has_login * $zero_profiles * 3 + $has_login * $many_profiles * 4)
        }

        array.push $classed {
          value = {id: $a.id, plan: $a.workspace_id, name: $a.name, uid: $uid, cls: $cls, profile_id: $pid}
        }
      }
    }

    var $linked_n {
      value = 0
    }

    var $already_n {
      value = 0
    }

    var $no_login {
      value = []
    }

    var $no_profile {
      value = []
    }

    var $several {
      value = []
    }

    var $will_link {
      value = []
    }

    // Pass 2: act only on the person's OWN class.
    foreach ($classed) {
      each as $c {
        var.update $already_n {
          value = $already_n + (($c.cls == 0)|to_int)
        }

        conditional {
          if ($c.cls == 1) {
            array.push $will_link {
              value = $c
            }
          }
        }

        conditional {
          if ($c.cls == 2) {
            array.push $no_login {
              value = {planner_agent_id: $c.id, plan: $c.plan, name: $c.name}
            }
          }
        }

        conditional {
          if ($c.cls == 3) {
            array.push $no_profile {
              value = {planner_agent_id: $c.id, plan: $c.plan, name: $c.name, user_id: $c.uid}
            }
          }
        }

        conditional {
          if ($c.cls == 4) {
            array.push $several {
              value = {planner_agent_id: $c.id, plan: $c.plan, name: $c.name, user_id: $c.uid}
            }
          }
        }
      }
    }

    var $to_link {
      value = $will_link|count
    }

    conditional {
      if ($input.apply == true) {
        foreach ($will_link) {
          each as $w {
            function.run "req/link_person" {
              input = {account_id: $actor.account_id, planner_agent_id: $w.id, agent_profile_id: $w.profile_id, how: "fill", user_id: $actor.user_id}
            } as $_linked
          }
        }
      }
    }

    var.update $linked_n {
      value = (($input.apply == true) ? $to_link : 0)
    }

    var $applied {
      value = ($input.apply == true)
    }

    conditional {
      if ($applied == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "plan_person.fill"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "People on plans were tied to the profile of their login."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "account"
            entity_id     : $actor.account_id
            correlation_id: $input.correlation_id
            metadata      : {linked: $linked_n, already_linked: $already_n, no_login: ($no_login|count), no_profile_yet: ($no_profile|count), several_profiles: ($several|count)}
          }
        } as $_logged
      }
    }
  }

  response = {
    applied         : $applied
    people_checked  : ($agents|count)
    would_link      : $to_link
    linked          : $linked_n
    already_linked  : $already_n
    no_login        : $no_login
    no_profile_yet  : $no_profile
    several_profiles: $several
  }
}
