// LIVE-1 (US-LIVE-1-01, US-LIVE-1-04) — What the planner changed
// after a day went live.
//
// Publishing does not freeze the planner, only the performer's view.
// The planner may keep moving, adding, removing and re-timing work —
// and every one of those writes a row here.
//
// WITHOUT THIS, PLAN-VS-ACTUAL WOULD LIE. A day quietly rearranged
// after publishing would look, in hindsight, as though it had always
// been planned that way, and every variance figure computed from it
// would be flattering and wrong. This table is what keeps the
// comparison honest.
//
// Nothing is written for a DRAFT day — there is no publication to
// measure against yet, and a draft is meant to be rearranged freely.
// Confirmed live: the same edit wrote a row on a published day and
// nothing on a draft one.
//
// `item_ref` points at the PUBLISHED item (`pt-<planner_task_id>` at
// publish time), not at a planner task row, so a change stays
// attached to something that still exists even after the task is
// removed (review finding F5).
//
// Append-only (GOV-1 S10): `created_at`, no `updated_at`. There is no
// update or delete route for this table, by design.
//
// Live id 126 (the epic reserved 90; Xano assigns its own ids).
table plan_change_log {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int timeline_id? {
      table = "planner_timeline"
    }

    int plan_publication_id? {
      table = "plan_publication"
      description = "The publication this change is measured against."
    }

    text item_ref? filters=trim {
      description = "Stable reference to the published item, e.g. pt-37. Never a live row id."
    }

    enum change_type?=moved {
      values = ["moved", "added", "removed", "duration_changed", "reassigned"]
    }

    json before?

    json after?

    int changed_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "timeline_id", op: "asc"}]}
    {type: "btree", field: [{name: "plan_publication_id", op: "asc"}]}
    {type: "btree", field: [{name: "changed_by", op: "asc"}]}
  ]
}
