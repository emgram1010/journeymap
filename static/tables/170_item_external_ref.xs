// SCALE-1 story 03 (2026-11-21) — links a product in an outside system to a catalog item, so an order line lands on the right item and gets the right time. Named for the pattern, not a vendor: source_system + external_id. item_type_id 0 with not_an_item false = "a product still to link" (it shows in the Products to link list); not_an_item true = a fee or deposit, ignored on future orders. Unique (account_id, source_system, external_id): one product, one row; several products may point at one item. external_name comes from outside: plain text, capped, shown escaped.
table item_external_ref {
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

    text source_system?
    text external_id?
    text external_name?
    int item_type_id? {
      table = "item_type"
    }

    bool not_an_item?
    int seen_count?
    timestamp last_seen_at?
    int updated_by_user_id? {
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
    {type: "btree", field: [{name: "item_type_id", op: "asc"}]}
  ]
}