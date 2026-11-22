// SCALE-1 story 01 (2026-11-21) — an item an order asked for that could not become an order line: its key is not in the catalog (or is switched off), or its outside product is not linked yet. Never dropped quietly: it is kept here by name so the job can show "no time set" for it and the Health page can count them. Adds 0 minutes to the estimate. Rows are written once when the job is made and are not edited.
table work_item_unmatched_line {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int work_item_id? {
      table = "work_item"
    }

    text source_system?
    text external_id?
    text label?
    int quantity?
    enum reason? {
      values = ["unknown_item", "unlinked_product"]
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}