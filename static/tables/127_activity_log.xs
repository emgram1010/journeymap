// LOG-1 (US-LOG-1-01, -03) — The append-only record of what actually
// happened.
//
// THIS IS THE RECORD LAYER. Of the three layers — Definition (the map
// and its versions), Commitment (the plan) and Record — this table is
// the whole of the third. Everything else in the product can be
// rebuilt from its sources; this cannot. It is the only place a
// performer's reality is written down.
//
// `work_task.status` is a CACHE of replaying these rows
// (`logModel.ts::replay`). If the two ever disagree, THIS IS RIGHT and
// the row is wrong — GOV-1's audit compares them and reports the
// difference rather than quietly repairing it.
//
// Append-only (GOV-1 S10): `created_at`, no `updated_at`, and there is
// no update or delete route for this table anywhere in the API. A
// mistake is corrected by recording another event (`reopened`), never
// by editing history. That is the point: a log you can edit is not
// evidence of anything.
//
// WHY `occurred_at` IS SERVER TIME. A device clock can be wrong by
// hours, deliberately or not, and the variance numbers are computed
// from these timestamps. `client_occurred_at` is stored but never
// trusted for timing; it exists so an offline app can later say what
// the phone believed, and so the gap between the two is visible.
//
// WHY BOTH `plan_publication_id` AND `publication_item_ref`. An event
// belongs to the frozen day the performer was actually looking at, not
// to whatever the planner has since rearranged (LIVE-1). The ref is a
// string like `pt-37`, so the event stays attached to something that
// still exists after the planner task is moved or deleted.
//
// WHY `client_event_id` IS UNIQUE. One tap must be one row, however
// many times the request arrives — a phone on a bad connection retries,
// and a double-counted "started" would corrupt the duration. The
// endpoint returns the existing row with `duplicate: true` rather than
// an error, so a retry looks like success to the performer.
//
// `work_item_id` is denormalised for reads (today's log for a job
// without a join) and is checked against the task's own job on write,
// so it cannot drift.
//
// Live id 127 (the epic reserved 91; Xano assigns its own ids).
table activity_log {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int work_task_id? {
      table = "work_task"
    }

    int work_item_id? {
      table = "work_item"
      description = "Denormalised for reads. Must match the task's own job — checked on write."
    }

    enum event_type?=note {
      values = ["started", "completed", "blocked", "unblocked", "skipped", "reopened", "note"]
    }

    int performer_user_id? {
      table = "user"
      description = "Who did it, when a person did. 0 for system or AI."
    }

    int performer_agent_id? {
      table = "planner_agent"
      description = "Which agent it was done as. 0 when not applicable."
    }

    timestamp occurred_at? {
      description = "SERVER time. The authoritative moment."
    }

    timestamp client_occurred_at? {
      description = "Reserved for offline capture later. Never trusted for timing."
    }

    enum reason_code?=other {
      values = ["waiting_on_someone", "missing_information", "something_went_wrong", "other"]
      description = "Required for a `blocked` event. Ignored otherwise."
    }

    text note? filters=trim

    enum source?=manual {
      values = ["manual", "ai", "system"]
    }

    int plan_publication_id? {
      table = "plan_publication"
      description = "The frozen publication this event belongs to. Immutable target."
    }

    text publication_item_ref? filters=trim {
      description = "e.g. pt-38. Survives the planner task being moved or removed."
    }

    text client_event_id? filters=trim {
      description = "Unique. One tap = one row, however many times the request arrives."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "work_task_id", op: "asc"}, {name: "occurred_at", op: "asc"}]}
    {type: "btree", field: [{name: "work_item_id", op: "asc"}, {name: "occurred_at", op: "asc"}]}
    {type: "unique", field: [{name: "client_event_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "performer_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "performer_agent_id", op: "asc"}]}
    {type: "btree", field: [{name: "plan_publication_id", op: "asc"}]}
  ]
}
