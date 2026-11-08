// LIVE-1 (US-LIVE-1-01) — One agent's day, frozen at the moment it
// was published to live.
//
// NOT THE SAME AS "PUBLISH VERSION" (PUB-1, `journey_map_version`),
// which freezes a journey map. This freezes a DAY: what one person
// was asked to do, in what order, for how long.
//
// NEVER UPDATED, NEVER DELETED. The performer reads this snapshot and
// nothing else, so a planner rearranging the day afterwards cannot
// change what someone has already been told to do (decision D-23).
// Confirmed live: after a scheduled step was re-timed from 30 to 55
// minutes post-publish, this snapshot still read 30 and its hash was
// unchanged.
//
// REPUB-1: a timeline may now be published MORE THAN ONCE, up until the
// agent starts working it. Each republish ADDS a row with version n+1;
// old versions stay forever as history. "Current" = highest version
// (equivalently highest id) — the one rule, in
// functions/live/latest_publications.xs. The unique index on
// (timeline_id, version) is the RACE GUARD: two overlapping republishes
// both compute n+1 and the database refuses the second (db.transaction
// alone does not serialize overlaps — CLAUDE.md, EXC-1).
//
// `snapshot_hash` is the tamper-evidence: re-serialising the stored
// snapshot must reproduce it, the same guarantee PUB-1 gives a map
// version.
//
// Append-only (GOV-1 S10): `created_at`, no `updated_at`. A documented
// exception to "no duplicate facts": the snapshot deliberately
// duplicates the plan, because the whole point is that it stops
// following it.
//
// LOG EVENTS POINT AT `plan_publication_id` + `item_ref`, NEVER at a
// planner task (review finding F5). A planner task can be moved or
// removed after publishing; the published item cannot, so history
// stays attached to something that still exists.
//
// Live id 125 (the epic reserved 89; Xano assigns its own ids).
table plan_publication {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int timeline_id? {
      table = "planner_timeline"
      description = "REPUB-1: no longer unique on its own — one row per (timeline, version)."
    }

    int version?=0 {
      description = "REPUB-1: 1 = first publish, +1 per republish. Unique with timeline_id (the race guard). Backfilled to 1 for all pre-REPUB rows; 0 is impossible by construction."
    }

    int published_by? {
      table = "user"
    }

    timestamp published_at?

    json snapshot? {
      description = "Ordered items, each with a stable item_ref, planned start, scheduled and expected minutes, assignee and labels."
    }

    text snapshot_hash? filters=trim {
      description = "sha256 of the canonical serialisation (liveModel.ts::canonicalizePublication). Must never change."
    }

    int item_count?=0 {
      description = "How many items were frozen. Cached so the Health page need not parse the snapshot."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "timeline_id", op: "asc"}, {name: "version", op: "asc"}]}
    {type: "btree", field: [{name: "published_by", op: "asc"}]}
  ]
}
