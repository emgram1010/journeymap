// SAFE-1 story 03 / D-10 (2026-11-21) — who owns the signed-in person's account.
// The side table's own GET, for the same reason as GET user_status: `account_owner` is invisible
// to `account/my_team_members`, so the Team page fetches this and merges it (`mergeTeam`).
// No input: the account comes from the caller's own record, so nothing sent can widen it.
// Any signed-in person may read it (it only names who the owner is). 0 = no owner.
query "account/owner" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $me

    precondition ($me != null) {
      error_type = "accessdenied"
      error = "We couldn't find your user record. (E-USR-010)"
    }

    db.query account_owner {
      where = $db.account_owner.account_id == $me.account_id
      return = {type: "single"}
      output = ["user_id"]
    } as $own

    var $owner_uid {
      value = $own|get:"user_id":0
    }
  }

  response = {account_id: $me.account_id, owner_user_id: $owner_uid}
  tags = ["safe-1"]
}
