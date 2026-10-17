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
      description = "Unique — one publication per timeline. Re-publishing is not in the MVP."
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
    {type: "btree|unique", field: [{name: "timeline_id", op: "asc"}]}
    {type: "btree", field: [{name: "published_by", op: "asc"}]}
  ]
}
