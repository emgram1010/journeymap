// COP-2 (2026-11-15) — a scratch row used ONLY by copilot/canon_json to put a JSON value into the
// database's own normal form. Found live: a json column comes back with its keys re-ordered
// (by length, then alphabetically), so a value read from the database never json_encodes the
// same as the same value sent by a caller. Writing the caller's value here and reading it back
// gives both sides the same order. Rows are deleted straight after; an empty table is normal.
//
// GOV-1: S1 primary key; S2 created_at. Not history: rows are transient by design.
table copilot_json_canon {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    json body?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
  ]
}
