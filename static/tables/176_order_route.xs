// DEMAND-1 story 03 (2026-11-21) — an order source the account accepts orders from, and its key. Named for the pattern (source_system), not a vendor. Only the SHA-256 hash of the key is stored; the key is shown once when made. key_hash is unique, so a key identifies exactly one account and source. is_enabled false = orders from it are refused. Also holds the routing rule (decision D-5): an order from this source whose fulfilment type equals match_fulfilment (or any, when that is empty) becomes a job in plan workspace_id from map journey_map_id, made in the name of created_by_user_id. One source may have several rows, one per fulfilment type; the rows of a source share the key.
table order_route {
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
    text key_hash?
    text match_fulfilment?
    int workspace_id? {
      table = "planner_workspace"
    }

    int journey_map_id? {
      table = "journey_map"
    }

    bool is_enabled?
    int created_by_user_id? {
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
        {name: "match_fulfilment", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "key_hash", op: "asc"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
  ]
}