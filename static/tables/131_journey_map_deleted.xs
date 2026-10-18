// US-DEL-1-07 (2026-10-18) — Which maps are soft-deleted, and by whom.
//
// A ROW HERE MEANS "DELETED". No row means the map is live. Restoring
// is removing the row, which is why this table is NOT append-only —
// it is a marker, not a record. The permanent record of the action
// lives in `event_log` under feature DEL-1, and that one is guarded
// against deletion (`historyTables.ts`).
//
// WHY A TABLE AND NOT `journey_map.is_deleted` (founder's decision,
// 2026-10-18): journey_map has several `filters=trim` text columns
// (title, primary_actor, journey_scope and more). Adding a column via
// updateTableSchema is confirmed — twice, on two different tables —
// to silently drop trim/lower validators on every OTHER field in that
// table. Same reason journey_stage_owner, journey_lens_planned_work
// and account_feature_flag all exist as side tables instead.
//
// WHY NOT REUSE `status = "archived"`: Archive is already a distinct
// user action in the Dashboard, meaning "hide this from my list but
// keep it". Collapsing "archived" and "deleted" into one value would
// take a working feature away to avoid creating a table.
//
// EVERY LIST OF MAPS MUST EXCLUDE THESE. A side table is invisible to
// the plain map queries unless they are told about it — exactly the
// trap AUTH-1 hit with journey_stage_owner, where the value came back
// undefined forever because the list endpoint never joined it. The
// readers that filter on this are `GET journey_map` (18) and
// `GET journey_map_attachable` (578).
//
// Live id 131.
table journey_map_deleted {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int journey_map_id? {
      table = "journey_map"
      description = "The soft-deleted map. One row per map — see the unique index. Removing the row restores it."
    }

    int deleted_by? {
      table = "user"
      description = "Who deleted it. 0 for a system or bulk action."
    }

    text reason? filters=trim {
      description = "Optional free text, e.g. 'test data cleanup'. Shown in the delete audit."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "deleted_by", op: "asc"}]}
  ]
}
