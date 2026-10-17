// AUTH-1 — list every stage ownership row, so the frontend can hydrate
// Stage.ownerLensId. journey_stage itself has no owner_lens_id column (see
// journey_stage_owner's table header, STAGE-1); the plain `GET /journey_stage`
// list endpoint never had this field to return. Small table (one row per
// stage that has an owner), no map filter — the frontend matches rows to its
// own stages by journey_stage id.
query journey_stage_owner verb=GET {
  api_group = "journey-map"

  input {
  }

  stack {
    db.query journey_stage_owner {
      return = {type: "list"}
    } as $model
  }

  response = $model
}
