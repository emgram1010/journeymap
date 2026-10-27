// USR-2 (US-USR-2-01) — the side table's own list endpoint.
//
// Third time this exact shape has been needed, and the reason has not changed
// since AUTH-1 cost a day on it: a field that really lives in a side table is
// INVISIBLE to the original table's list endpoint. `GET
// account/my_team_members` queries `user` and only `user`, so a grant kept in
// `user_module_access` reads as `undefined` in the browser forever, with no
// error, however correct the write path is. `GET user_status` is the same
// shape for the same reason, and the frontend merges all three explicitly
// (`mergeTeam`).
//
// Account-scoped, and the scope comes from the caller's OWN record. There is
// no input at all, deliberately: nothing a caller sends can widen what they
// see.
//
// NOT ADMIN-ONLY, on purpose. Every signed-in user needs their own grants to
// know which sidebar items to draw, and an admin needs the whole account's to
// fill in the Team page — one endpoint answers both, scoped to the account
// either way. It returns ids, module keys and booleans; there is nothing in a
// grant row that one colleague should be kept from seeing about another, and
// an admin-only version would mean a second endpoint doing the same query.
query "user_module_access" verb=GET {
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
    // `foreach`/indexing both fail (CLAUDE.md).
    db.query user_module_access {
      where = $db.user_module_access.account_id == $me.account_id
      return = {type: "list"}
      output = ["id", "user_id", "account_id", "module", "granted", "granted_at", "granted_by_user_id"]
    } as $grants
  }

  response = $grants
  tags = ["phase-5", "usr-2"]
}
