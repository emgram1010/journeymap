// AUTH-1 / STAGE-1 — list every explicit does_planned_work override, so the
// frontend can hydrate Lens.plannedWorkOverride and compute the effective
// value with the already-tested stageOwnerModel.doesPlannedWork(actorType,
// override). Small table (overrides only, not every lens), so no paging or
// map filter — the frontend matches rows to its own lenses by journey_lens id.
query journey_lens_planned_work verb=GET {
  api_group = "journey-map"

  input {
  }

  stack {
    db.query journey_lens_planned_work {
      return = {type: "list"}
    } as $model
  }

  response = $model
}
