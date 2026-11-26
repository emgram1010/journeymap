// REQ-1 story 03 — The people on a plan, and for each whether they are tied to a lasting profile. A dedicated read for the SIDE table planner_agent_profile (the plan's people list does not read it, so "no profile" would never show: the AUTH-1 lesson). Any member of the account may read; another account's plan is "Plan not found". For a person with NO link it also offers what an admin can confirm: the profile that belongs to their LOGIN, and profiles with the same name (nothing is ever linked by name on its own: a person clicks each one, and a name shared by two profiles is only reported with its count). Every key is hoisted into a variable first (a pipe nested inside a filter argument fails at runtime); every lookup is a plain map read.
query "workspace/{workspace_id}/person-link" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
      sort = {planner_agent.id: "asc"}
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
    } as $links

    db.query user {
      where = $db.user.account_id == $actor.account_id
      return = {type: "list"}
      output = ["id", "name"]
    } as $account_users

    var $account_user_ids {
      value = [-1]
    }

    var $user_names {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($account_users) {
      each as $u {
        array.push $account_user_ids {
          value = $u.id
        }

        var.update $t {
          value = $u.id|to_text
        }

        var.update $k {
          value = "u:" ~ $t
        }

        var.update $user_names {
          value = $user_names|set:$k:$u.name
        }
      }
    }

    db.query agent_profile {
      where = ($db.agent_profile.user_id in $account_user_ids) || ($db.agent_profile.user_id == 0 && $db.agent_profile.account_id == $actor.account_id)
      return = {type: "list"}
    } as $profiles

    var $profile_name {
      value = {}
    }

    var $by_login {
      value = {}
    }

    var $login_count {
      value = {}
    }

    var $by_name {
      value = {}
    }

    var $name_count {
      value = {}
    }

    var $shown {
      value = ""
    }

    var $own_name {
      value = ""
    }

    var $login_name {
      value = ""
    }

    var $lname {
      value = ""
    }

    var $puid {
      value = 0
    }

    var $n {
      value = 0
    }

    foreach ($profiles) {
      each as $p {
        var.update $puid {
          value = $p.user_id ?? 0
        }

        var.update $t {
          value = $puid|to_text
        }

        var.update $k {
          value = "u:" ~ $t
        }

        var.update $login_name {
          value = ($user_names|get:$k:null) ?? ""
        }

        var.update $own_name {
          value = $p.name ?? ""
        }

        var.update $shown {
          value = ($own_name != "") ? $own_name : $login_name
        }

        var.update $t {
          value = $p.id|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $profile_name {
          value = $profile_name|set:$k:$shown
        }

        var.update $t {
          value = $puid|to_text
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

        var.update $by_login {
          value = $by_login|set:$k:$p.id
        }

        var.update $lname {
          value = $shown|lower
        }

        var.update $k {
          value = "n:" ~ $lname
        }

        var.update $n {
          value = (($name_count|get:$k:null) ?? 0) + 1
        }

        var.update $name_count {
          value = $name_count|set:$k:$n
        }

        var.update $by_name {
          value = $by_name|set:$k:$p.id
        }
      }
    }

    var $link_of {
      value = {}
    }

    foreach ($links) {
      each as $l {
        var.update $t {
          value = $l.planner_agent_id|to_text
        }

        var.update $k {
          value = "a:" ~ $t
        }

        var.update $link_of {
          value = $link_of|set:$k:$l.agent_profile_id
        }
      }
    }

    var $out {
      value = []
    }

    var $pid {
      value = 0
    }

    var $pname {
      value = ""
    }

    var $uid {
      value = 0
    }

    var $login_pid {
      value = 0
    }

    var $login_n {
      value = 0
    }

    var $name_pid {
      value = 0
    }

    var $name_n {
      value = 0
    }

    var $has_name {
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

        var.update $pid {
          value = ($link_of|get:$k:null) ?? 0
        }

        var.update $t {
          value = $pid|to_text
        }

        var.update $k {
          value = "p:" ~ $t
        }

        var.update $pname {
          value = ($profile_name|get:$k:null) ?? ""
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

        var.update $login_pid {
          value = ($by_login|get:$k:null) ?? 0
        }

        var.update $login_n {
          value = ($login_count|get:$k:null) ?? 0
        }

        var.update $lname {
          value = ($a.name ?? "")|lower
        }

        var.update $k {
          value = "n:" ~ $lname
        }

        var.update $name_pid {
          value = ($by_name|get:$k:null) ?? 0
        }

        var.update $name_n {
          value = ($name_count|get:$k:null) ?? 0
        }

        var.update $has_name {
          value = ($lname != "")|to_int
        }

        // The login's own profile is offered only for a real login, and only when it is the one profile of that login.
        var.update $login_pid {
          value = $login_pid * (($uid != 0)|to_int) * (($login_n == 1)|to_int)
        }

        var.update $name_pid {
          value = $name_pid * $has_name * (($name_n == 1)|to_int)
        }

        var.update $name_n {
          value = $name_n * $has_name
        }

        array.push $out {
          value = {
            planner_agent_id    : $a.id
            name                : $a.name
            kind                : $a.kind
            user_id             : $uid
            is_active           : $a.is_active
            profile_id          : $pid
            profile_name        : $pname
            login_profile_id    : $login_pid
            name_match_profile_id: $name_pid
            name_match_count    : $name_n
          }
        }
      }
    }
  }

  response = {workspace_id: $input.workspace_id, people: $out}
}
