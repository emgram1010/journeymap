// JOB-1 (US-JOB-1-01) — One real instance of a work type.
//
// A job holds IDENTITY, ATTRIBUTES AND STATUS — and nothing else.
// There is deliberately no column for task text, durations, owners or
// done-when. All of that is read through `journey_map_version_id`,
// the published version this job is PINNED to.
//
// That pin is the point. Editing the live map, or publishing a newer
// version, cannot change work already in flight: the job keeps
// reading the frozen snapshot it started with. One source of truth,
// and live work that is immune to later edits.
//
// `status` is a CACHED value. LOG-1's engine is the only thing that
// writes it, and it is derived from the tasks by
// `webapp/protype-2/src/jobModel.ts::deriveJobStatus`. GOV-1's daily
// audit compares the two; if they disagree, the derived one is right
// (review finding F12).
//
// `attributes` is free key/value in the MVP (D-44), shaped
// {key: {value, source, entered_at}} so a controlled intake schema
// can replace it later without a migration. Every entry records
// WHERE it came from and WHEN.
//
// Live id 122 (the epic reserved 86; Xano assigns its own ids).
table work_item {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
    }

    int workspace_id? {
      table = "planner_workspace"
    }

    int journey_map_version_id? {
      table = "journey_map_version"
      description = "The PINNED published version. A job's content is read through this, never from the live map."
    }

    text title? filters=trim {
      description = "1-120 characters, no HTML (API-enforced, E-JOB-001)."
    }

    enum status?=open {
      values = ["open", "in_progress", "blocked", "completed", "cancelled"]
      description = "CACHED. Written only by LOG-1's engine; derived from the tasks. GOV-1's audit checks it."
    }

    json attributes? {
      description = "{key: {value, source, entered_at}}. Max 50 keys, no nested objects (API-enforced, E-JOB-004)."
    }

    int parent_work_item_id? {
      description = "Optional parent job. A plain int, not a declared self-reference: Xano cannot reference a table while creating it, and adding the reference later needs updateTableSchema, which silently drops this table's trim validators (CLAUDE.md). 0 = no parent."
    }

    int created_by? {
      table = "user"
    }

    timestamp started_at?

    timestamp finished_at?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}, {name: "status", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_version_id", op: "asc"}]}
    {type: "btree", field: [{name: "parent_work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_by", op: "asc"}]}
  ]
}
