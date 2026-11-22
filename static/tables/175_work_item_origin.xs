// DEMAND-1 (2026-11-21) — where a job came from, when it came from an order in an outside system. One row per job (work_item_id unique) and one job per order (unique account_id + source_system + external_id): that second index, not a check, is what makes the same order sent ten times at once produce one job. The row is inserted FIRST, as a claim with work_item_id 0, then the job is made. is_unplanned marks work that arrived after planning. order_flag sits beside the job's normal status (the five step statuses never change): order_changed or order_cancelled after work started, cleared by a person. Only what the work needs is kept: order number, dates and fulfilment type. No customer name, address, phone, price or note.
table work_item_origin {
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

    int work_item_id? {
      table = "work_item"
    }

    text source_system?
    text external_id?
    text order_number?
    text starts_on?
    text ends_on?
    text fulfilment?
    bool is_unplanned?
    enum order_flag? {
      values = ["none", "order_changed", "order_cancelled"]
    }

    text lines_fingerprint?
    timestamp flag_cleared_at?
    int flag_cleared_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [
        {name: "account_id", op: "asc"}
        {name: "source_system", op: "asc"}
        {name: "external_id", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "flag_cleared_by_user_id", op: "asc"}]}
  ]
}