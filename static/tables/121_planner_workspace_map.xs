// PLAN-1 (US-PLAN-1-03) — The instance's OWN copy of the maps it
// accepts.
//
// THIS TABLE IS THE WHOLE POINT OF THE TEMPLATE/INSTANCE SPLIT. The
// rows are copied from `plan_template_map` at the moment the instance
// is created and never read from the template again. Editing the
// template afterwards — adding a map, removing one — cannot reach a
// plan that already exists.
//
// Without this, a plan's accepted maps would silently change under
// people mid-quarter whenever someone tidied the template.
//
// Append-only link table (GOV-1 S10): `created_at`, no `updated_at`.
//
// Live id 121 (the epic reserved 85; Xano assigns its own ids).
table planner_workspace_map {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int workspace_id? {
      table = "planner_workspace"
    }

    int journey_map_id? {
      table = "journey_map"
      description = "Copied from the template at creation time. Independent of the template from then on."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "workspace_id", op: "asc"}, {name: "journey_map_id", op: "asc"}]}
  ]
}
