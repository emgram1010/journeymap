// AIM-1 story 03 (2026-11-21) — an access token for ONE AI member, for the outside tool address. Only the SHA-256 hash is stored; the token itself is shown once when made and never again. token_hash is unique. A token is live when revoked_at is empty and expires_at is in the future. scope_actions may narrow the member's own allowed actions (empty = the same as the member); it can never widen them, because the gate takes the overlap. last_used_at is stamped on use. Rows are never deleted: a revoked token stays as history.
table agent_access_token {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int user_id? {
      table = "user"
    }

    text token_hash?
    text label?
    json scope_actions?
    int created_by_user_id? {
      table = "user"
    }

    timestamp expires_at?
    timestamp last_used_at?
    timestamp revoked_at?
    int revoked_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [{name: "token_hash", op: "asc"}]
    }
    {type: "btree", field: [{name: "user_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}