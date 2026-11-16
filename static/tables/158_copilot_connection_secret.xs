// COP-6 story 02 (2026-11-16) — the WRITE-ONLY login for one connection in ONE business. A login can
// be set, replaced and removed; it is never returned by any endpoint, screen or tool, never logged,
// and is attached to the outgoing request by the server only (the copilot never sees it).
//
// Founder decision 2026-11-16: ENCRYPTED IN XANO. Written only by POST copilot/connection_login
// (659) through copilot/login_seal (JWE A256KW + A256GCM, key = env COPILOT_SECRET_KEY, never in
// the database); opened only by the server-only copilot/login_open. Removing a login deletes the
// row and switches the connection off, logged without the value. Unique (journey_architecture_id,
// connection_id). (The live column description still says "encrypted value, or a reference".)
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key.
table copilot_connection_secret {
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

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business the login belongs to. Never shared."
    }

    int connection_id? {
      table = "copilot_connection"
    }

    text secret_value? {
      visibility = "private"
      description = "The protected login (encrypted value, or a reference to an outside store). Never returned, never logged."
    }

    int set_by_user_id? {
      table = "user"
      description = "The person who last set or replaced it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_architecture_id", op: "asc"}, {name: "connection_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "connection_id", op: "asc"}]}
    {type: "btree", field: [{name: "set_by_user_id", op: "asc"}]}
  ]
}
