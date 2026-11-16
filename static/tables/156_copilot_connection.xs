// COP-6 story 01 (2026-11-16) — the CONNECTIONS LIBRARY: the outside systems an account's copilot
// could use (a booking tool, an inbox, accounts). General on purpose: a row names a system and what
// it can read and change; nothing here knows any one outside system. Switching it on is per
// business (copilot_connection_switch); its login is per business (copilot_connection_secret).
//
// Unique (account_id, key): one entry per system per account. Never deleted: a retired entry keeps
// its history (status "retired").
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key.
table copilot_connection {
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

    text key? filters=trim|lower {
      description = "Short machine name, unique in the account, e.g. booking-tool."
    }

    text name? filters=trim {
      description = "What the owner sees."
    }

    text description? filters=trim

    enum status? {
      values = ["available", "retired"]
      description = "retired = no longer offered; history kept."
    }

    int created_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}, {name: "key", op: "asc"}]}
    {type: "btree", field: [{name: "created_by_user_id", op: "asc"}]}
  ]
}
