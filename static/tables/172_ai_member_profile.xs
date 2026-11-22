// AIM-1 (2026-11-21) — marks ONE login as an AI member and holds its "job description". A row here is what makes a login an AI (D-3): the tool gate then applies aim/check to every call, the app's own screens refuse it, and it can never get a password reset link. user_id is unique: one profile per login. manager_user_id is the accountable person; purpose is one line; allowed_actions is a list chosen from the fixed list in aim/policy (read, draft_map, draft_plan, own_work) and can never contain a ceiling action; plan_ids limits it to those plans (empty = no plan at all). is_paused true = switched off or paused automatically (paused_reason says which). Caps are writes per hour and per day. Written only by admin endpoints that refuse an AI caller.
table ai_member_profile {
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

    int user_id? {
      table = "user"
    }

    int manager_user_id? {
      table = "user"
    }

    text purpose?
    json allowed_actions?
    json plan_ids?
    bool is_paused?
    text paused_reason?
    timestamp paused_at?
    int writes_per_hour?
    int writes_per_day?
    int updated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "user_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {
      type : "btree"
      field: [{name: "manager_user_id", op: "asc"}]
    }
  ]
}