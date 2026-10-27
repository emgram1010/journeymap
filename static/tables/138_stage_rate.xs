// RATE-1 (US-RATE-1-01) — The published, version-pinned rate card:
// minutes per unit of one item, by one method, at one stage, frozen at
// publish time. One row per entry in `journey_map_version.snapshot.rates`.
//
// WHY A TABLE AND NOT ONLY THE SNAPSHOT: rates are many and queried
// ("what is the rate for chair-resin at s8 in v3?"); parsing a snapshot
// per request would be slow and every reader would re-implement it. The
// snapshot stays the source of truth for the HASH; this table is the
// source of truth for READS. Scaling (one value per stage) deliberately
// stays in the snapshot only — one fact, one place.
//
// APPEND-ONLY, WRITTEN ONLY BY PUBLISH: rows are inserted in the same
// db.transaction as their journey_map_version row (endpoint 201), never
// patched, never deleted. Versions themselves are never deleted
// (US-DEL-1-02), so neither are these — it is listed in
// src/ops/historyTables.ts. GOV-1's audit (ops/audit_rates) cross-checks
// the row count against snapshot.rates (E-RATE-003).
//
// Keys are plain text, not references: `quantity_key` is an
// item_type.key and `method_key` a method.key AT PUBLISH TIME. A key is
// never edited after creation (CAT-1 D-2), and a deactivated item keeps
// its old rates on old versions on purpose (PRD EC-3).
//
// GOV-1 standards: S1 (primary key), S2 (created_at only — append-only),
// S3 (declared + indexed reference on journey_map_version_id), S6
// (unique version + stage + quantity + method), S7 (source is an enum).
table stage_rate {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int journey_map_version_id? {
      table = "journey_map_version"
      description = "The version this rate belongs to. Required in practice — written only by the publish endpoint."
    }

    text stage_key? filters=trim {
      description = "The stage's key in that version's snapshot."
    }

    text quantity_key? filters=trim {
      description = "What is counted. An item_type.key in MVP."
    }

    text method_key? filters=trim {
      description = "How it is done. A method.key."
    }

    decimal minutes_per_unit? {
      description = "Minutes for one unit, 0–1440, at most 2 decimals (validated on the Items cell, E-ITM-004)."
    }

    enum source?=seed {
      values = ["seed", "measured"]
      description = "seed = typed on the map. measured = learned from execution (EXE-M-1, later)."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [
        {name: "journey_map_version_id", op: "asc"}
        {name: "stage_key", op: "asc"}
        {name: "quantity_key", op: "asc"}
        {name: "method_key", op: "asc"}
      ]
    }
    {
      type : "btree"
      field: [
        {name: "journey_map_version_id", op: "asc"}
        {name: "stage_key", op: "asc"}
      ]
    }
  ]
}
