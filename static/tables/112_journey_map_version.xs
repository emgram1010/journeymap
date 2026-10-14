// PUB-1 (US-PUB-1-03) — One immutable, frozen version of a map's work
// definition, written on every successful "Publish version".
//
// IMMUTABLE BY RULE, NOT BY SCHEMA: there is deliberately no update or
// delete endpoint for this table (US-PUB-1-04). A map that has versions
// is archived, never deleted (GOV-1 standard S9). `content_hash` is a
// sha256 over the canonical serialisation of `snapshot` (see
// functions/pub/canonical_hash.xs) so tampering is detectable.
//
// DOCUMENTED EXCEPTION to "no duplicate facts" (GOV-1): `snapshot` is a
// deliberate frozen copy of the live definition. That is the point of a
// version — live work pins to this, not to the editable map.
table journey_map_version {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int journey_map_id? {
      table = "journey_map"
      description = "The map this version was cut from. Required in practice — enforced by the publish endpoint."
    }

    int version_no? {
      description = "Monotonic per map, starting at 1. Unique with journey_map_id."
    }

    json snapshot? {
      description = "Frozen work definition: title, stages in order with their owner, rows with does_planned_work, work cells (task, done-when, duration in minutes), and links."
    }

    text content_hash? filters=trim {
      description = "sha256 of the canonical serialisation of snapshot. Recomputed by verify_version to detect tampering."
    }

    json readiness_report? {
      description = "The readiness result at publish time: {ready, blockers[], warnings[]}. Kept for audit — why this version was allowed through the gate."
    }

    int automation_snapshot_id? {
      table = "automation_snapshot"
      description = "The automation snapshot compiled in the same publish, when one was produced. Nullable."
    }

    int published_by? {
      table = "user"
      description = "Who published it."
    }

    timestamp published_at? {
      description = "When the publish completed."
    }
  }

  // Every FK is the first field of an index — GOV-1 standard S3, enforced by
  // scripts/audit-schema.mjs (which caught the two missing ones here).
  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "journey_map_id", op: "asc"}, {name: "version_no", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "automation_snapshot_id", op: "asc"}]}
    {type: "btree", field: [{name: "published_by", op: "asc"}]}
  ]
}
