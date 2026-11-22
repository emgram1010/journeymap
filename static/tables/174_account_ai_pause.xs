// AIM-1 story 06 (2026-11-21) — the account-wide "Pause all AI" switch. One row per account (unique). is_paused true = every AI member in the account is refused on its next call, and incoming orders are queued instead of processed. No row = not paused. Written only by an admin endpoint that refuses an AI caller.
table account_ai_pause {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?
    int account_id? {
      table = "account"
    }

    bool is_paused?
    int updated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [{name: "account_id", op: "asc"}]
    }
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}