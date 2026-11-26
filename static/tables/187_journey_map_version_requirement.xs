// REQ-1 (US-REQ-1-05) — the needs FROZEN at Publish version: one row per (version, stage key, row key, requirement). Written inside Publish version's transaction, never edited, never deleted on its own (removed only with a hard-deleted map). Keyed by stage key and row key (lens_key) because those never change after creation and are the same keys a job's step uses, so a recreated cell id cannot break it. A SIDE table keyed by the version, NOT part of the snapshot: the snapshot has a content hash the frontend reproduces byte for byte, and adding to it would risk every stored hash. A version published before this table has no rows: its jobs behave as today.
// NOT PUSHED until the founder says yes. New table; no existing table is changed.
table journey_map_version_requirement {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int journey_map_version_id? {
      table = "journey_map_version"
    }

    text stage_key?
    text lens_key? {
      description = "The row key."
    }

    int requirement_id? {
      table = "requirement"
    }

    text strength? {
      description = "hard | soft"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_map_version_id", op: "asc"}, {name: "stage_key", op: "asc"}, {name: "lens_key", op: "asc"}, {name: "requirement_id", op: "asc"}]}
    {type: "btree", field: [{name: "requirement_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}
