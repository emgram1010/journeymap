// SAFE-1 story 03 (2026-11-21) — ONE place that answers "what rank does this person hold in
// their account": owner, admin or member, and whether the login is an AI.
// The owner comes from `account_owner` (table 167, D-10); admin/member from `user.role`;
// AI from `ai_identity`. The reset endpoint asks this about both the actor and the target,
// so the "who may reset whom" rule (D-9) never holds its own copy of these facts.
// An unknown user returns found = false and rank "none"; never throws.
function "usr/account_rank" {
  input {
    int user_id
  }

  stack {
    db.query user {
      where = $db.user.id == $input.user_id
      return = {type: "single"}
      output = ["id", "account_id", "role"]
    } as $u

    var $uid {
      value = $u|get:"id":0
    }

    var $acct {
      value = $u|get:"account_id":0
    }

    var $role {
      value = $u|get:"role":""
    }

    db.query account_owner {
      where = $db.account_owner.account_id == $acct
      return = {type: "single"}
      output = ["user_id"]
    } as $own

    var $owner_uid {
      value = $own|get:"user_id":0
    }

    db.query ai_identity {
      where = $db.ai_identity.user_id == $uid
      return = {type: "count"}
    } as $ai_count

    // Real ids start at 1, so a 0 here means "not found" (never a real user).
    var $found {
      value = $uid > 0
    }

    var $is_owner {
      value = $found && $acct > 0 && $owner_uid == $uid
    }

    var $is_admin {
      value = $found && $role == "admin"
    }

    var $rank {
      value = ($is_owner ? "owner" : ($is_admin ? "admin" : ($found ? "member" : "none")))
    }
  }

  response = {found: $found, user_id: $uid, account_id: $acct, rank: $rank, is_owner: $is_owner, is_admin: $is_admin, is_ai: ($ai_count > 0), account_owner_user_id: $owner_uid}
}
