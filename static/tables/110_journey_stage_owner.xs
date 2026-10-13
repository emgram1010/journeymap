// STAGE-1 (US-STAGE-1-01/02/03) — Stage ownership, one row per owned stage.
//
// WHY A TABLE AND NOT `journey_stage.owner_lens_id` (what EPIC-STAGE-1
// originally specified): journey_stage has several `filters=trim` text
// columns (key, label, stage_goal, primary_actor_lens). Adding a column
// via updateTableSchema is confirmed (twice, OBS-1) to silently drop
// trim/lower/min-length validators on every OTHER field in the table —
// same reason account_feature_flag (GOV-1) exists instead of a column
// on `account`. A missing row means "no owner set" — the same meaning
// a null owner_lens_id column would have had.
//
// `primary_actor_lens` (the old text key) is left untouched and still
// written alongside this table by update_stage_contract (US-STAGE-1-04)
// so the two stay in agreement during the transition.
table journey_stage_owner {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int journey_stage? {
      table = "journey_stage"
      description = "The stage this owner assignment is for. One row per stage — see the unique index."
    }

    int owner_lens_id? {
      table = "journey_lens"
      description = "The lens (actor row) that owns this stage. Must belong to the same journey_map as the stage — enforced by the stage PATCH endpoint, not the database."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "journey_stage", op: "asc"}]}
    {type: "btree", field: [{name: "owner_lens_id", op: "asc"}]}
  ]
}
