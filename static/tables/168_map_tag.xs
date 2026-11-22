// TAG-1 story 01 (2026-11-21) — one tag per account, stored once. name is what people see;
// name_key is the lower-case, trimmed form computed by tags/tag_key (never by a column filter,
// which a schema change can drop). Unique (account_id, name_key) is what stops two requests
// making "ops" twice.
table map_tag {
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

    text name?
    text name_key?
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
        {name: "name_key", op: "asc"}
      ]
    }
  ]
}