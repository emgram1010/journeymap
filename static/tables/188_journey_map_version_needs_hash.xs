// REQ-1 (US-REQ-1-05) — one row per published version that has frozen needs: how many, and a hash of them for tamper evidence (checked by the nightly audit, with the snapshot's own hash). A sixth table beyond the five in the epic: the epic says "each version stores a hash of its frozen needs" and also "no column is added to journey_map_version", so the hash needs a home of its own. The hash is built by explicit concatenation in a fixed order (sorted by stage key, row key, requirement id), never through a JSON encoder, with "::" as the separator and never the pipe character. A version with no needs has NO row here; the fixed "no needs" hash is pinned in a test on both sides.
// NOT PUSHED until the founder says yes. New table; no existing table is changed.
table journey_map_version_needs_hash {
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

    int need_count?

    text needs_hash? {
      description = "sha256 of the frozen needs, fixed order."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_map_version_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}
