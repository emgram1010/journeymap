// DEMAND-1 story 03 (2026-11-21) — one row per order event received, so nothing arrives without a trace. outcome: created (a job was made), updated (the job's items were changed before work started), duplicate (nothing to do), flagged (the order changed or was cancelled after work started), no_route (no routing rule matched; listed on the Health page), held (AI and orders are paused for the account), refused (bad input), failed (the job could not be made; detail says why). Ids, counts and the order number only: no customer details and never the key. Rows are kept 30 days.
table order_inbox {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    text source_system?
    text external_id?
    text order_number?
    text order_status?
    enum outcome? {
      values = [
        "created"
        "updated"
        "duplicate"
        "flagged"
        "no_route"
        "held"
        "refused"
        "failed"
      ]
    }

    text detail?
    int work_item_id? {
      table = "work_item"
    }

    int line_count?
    int unmatched_count?
    json payload?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree"
      field: [
        {name: "account_id", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
    {type: "btree", field: [{name: "outcome", op: "asc"}]}
    {type: "btree", field: [{name: "work_item_id", op: "asc"}]}
  ]
}