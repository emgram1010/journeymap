// USR-1 (US-USR-1-01) — The side table's own list endpoint.
//
// This exists because of AUTH-1. A field that really lives in a side table is
// invisible to the original table's list endpoint — `GET
// account/my_team_members` queries `user` and only `user`, so a status kept
// in `user_status` would read as `undefined` in the browser forever, with no
// error, no matter how correct the write path is. That cost a day once; the
// fix both times is the same shape as this: a small, no-filter GET for the
// side table, merged into the frontend's state by a dedicated fetch.
//
// Account-scoped, and the scope comes from the caller's own record. There is
// no input at all, deliberately: nothing a caller sends can widen what they
// see.
//
// Rows exist only for users whose status has been touched. A user with no row
// here is ACTIVE — the frontend's merge treats absence that way, and so does
// `usr/assert_not_last_admin`.
query "user_status" verb=GET {
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

    // No `paging` on purpose: with it the result stops being a plain array and
    // `foreach`/indexing fail (CLAUDE.md).
    db.query user_status {
      where = $db.user_status.account_id == $me.account_id
      return = {type: "list"}
      output = ["id", "user_id", "account_id", "is_active", "deactivated_at", "deactivated_by_user_id"]
    } as $statuses
  }

  response = $statuses
  tags = ["phase-5", "usr-1"]
}
