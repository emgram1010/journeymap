// REQ-1 (US-REQ-1-01) — one list of requirements per account: a named thing a person can hold and a step can need. No type column and no seeded rows: a licence, a tool, a clearance and a language are all just names, and the list starts empty. name_key is the trimmed, lower-case, single-spaced form of the name; the unique index on (account, name_key) is what makes "Forklift" and " forklift " one requirement and what settles two parallel adds. The key is computed in ONE function (req/normalize_name) and stored, never produced by a column filter (updateTableSchema drops validators). A rename changes `name` only; the key is recomputed and must stay unique. is_active = false is "archived": it can no longer be newly picked, and it still shows wherever it is already used. Deleted only while nothing points at it.
// NOT PUSHED until the founder says yes (CLAUDE.md: ask before any schema push). New table; no existing table is changed.
table requirement {
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

    text name? {
      description = "As shown. 1 to 60 characters, no HTML (validated by req/validate_name)."
    }

    text name_key? {
      description = "Lower-case, trimmed, single-spaced name. Unique per account."
    }

    text description?

    bool is_active?=true {
      description = "false = archived."
    }

    int created_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}, {name: "name_key", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by", op: "asc"}]}
  ]
}
