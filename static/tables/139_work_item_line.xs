// EST-1 (US-EST-1-01) — The counts: one (job, item type, quantity) per
// line. The map owns the standards (stage_rate); this table owns what
// is actually in THIS order.
//
// WHY A CHILD TABLE, NOT `work_item.attributes`: attributes is flat
// key/value, max 50 keys, no nesting (E-JOB-004) — it cannot hold a
// per-item quantity with its own validation and its own frozen/not-
// frozen lifecycle. "Anything the system computes with is a column"
// (PRD invariant 3): estimate_job reads this table directly.
//
// `item_type_id`, NOT the item's key: the key is what `stage_rate`
// matches by (CAT-1: a key never changes after creation), but the
// line itself references the real catalog row so an active/inactive
// check and the item's label/unit are a plain join, not a second
// lookup by key. estimate_job resolves item_type_id -> key once per
// job, not per line.
//
// FROZEN ONCE WORK STARTS (E-EST-007, API-enforced): once any of the
// job's work_task rows has left `not_started`, lines may not change —
// the estimate the plan was scheduled against must not drift under
// live work. No column records this; the API checks work_task.status
// directly, the same source of truth LOG-1's engine already owns.
//
// NO DELETE CASCADE CODE: work_item has no delete endpoint in this
// codebase (jobs are cancelled, not deleted — apis/planner/557). If
// JOB-1 ever adds one, it must add this table to that transaction,
// the same way US-DEL-1-02-style cascades are added elsewhere.
//
// GOV-1 standards: S1 (primary key), S2 (created_at + updated_at — a
// line's quantity is edited via PUT, up to the freeze), S3 (declared
// + indexed references on both work_item_id and item_type_id), S6
// (unique work_item_id + item_type_id — one line per item per job,
// EC-17; the UI merges a repeated pick into one quantity instead of a
// second row).
table work_item_line {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int work_item_id? {
      table = "work_item"
      description = "The job this line belongs to."
    }

    int item_type_id? {
      table = "item_type"
      description = "Must be active, in the caller's account, and referenced by the job's pinned version's rate card at creation time (API-enforced: E-EST-002/E-EST-003)."
    }

    int quantity? {
      description = "1-9999 (API-enforced, E-EST-001)."
    }

    int flagged_quantity?=0 {
      description = "How many of this line were flagged upstream. 0 <= flagged <= quantity. Written by execution (EXE-M-1, later) -- nothing in this epic writes a nonzero value."
    }

    int created_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [
        {name: "work_item_id", op: "asc"}
        {name: "item_type_id", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "item_type_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by", op: "asc"}]}
  ]
}
