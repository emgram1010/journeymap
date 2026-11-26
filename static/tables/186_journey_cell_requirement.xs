// REQ-1 (US-REQ-1-04) — what a STEP of the map needs: one row per (step, requirement), hard or soft. A step is one cell (one stage of one row). Hard means the work must go to someone who holds it; soft means preferred. A side table, not a column on journey_cell. The step is the ONE place a need is stored: "apply to the whole row" is a bulk write to its steps, never a second store. A draft edit: nothing reaches a job until the map is published (story 05 freezes it into journey_map_version_requirement). Deleted with its cell, row, stage or map.
// NOT PUSHED until the founder says yes. New table; no existing table is changed.
table journey_cell_requirement {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int account_id? {
      table = "account"
    }

    int journey_map_id? {
      table = "journey_map"
    }

    int journey_cell_id? {
      table = "journey_cell"
    }

    int requirement_id? {
      table = "requirement"
    }

    text strength? {
      description = "hard | soft (validated by the writer). Same meaning everywhere: hard refuses, soft warns."
    }

    int updated_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_cell_id", op: "asc"}, {name: "requirement_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "requirement_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by", op: "asc"}]}
  ]
}
