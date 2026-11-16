// COP-6 stories 01/04 (2026-11-16) — one connection switched on or off for ONE business, and how it
// last went. A connection is reachable for a business only when a row here says is_on = true;
// no row = off. One business's switch never serves another: unique (journey_architecture_id,
// connection_id), and the gate check reads only the pinned business's row.
//
// last_ok_at / failing_since / last_error_code give Health "which connection is failing, since
// when, for which business" (story 04) without writing one event per failure: the row is patched
// in place, and only the first failure and the recovery are logged as events.
//
// Switching off keeps the row (and its history in event_log). Edited in place.
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key.
table copilot_connection_switch {
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
      description = "The business."
    }

    int connection_id? {
      table = "copilot_connection"
    }

    bool is_on?

    timestamp last_ok_at? {
      description = "When it last worked. 0 = never."
    }

    timestamp failing_since? {
      description = "First failure of the current run of failures. 0 = not failing."
    }

    text last_error_code? filters=trim

    int updated_by_user_id? {
      table = "user"
      description = "The person who last switched it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_architecture_id", op: "asc"}, {name: "connection_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "connection_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
