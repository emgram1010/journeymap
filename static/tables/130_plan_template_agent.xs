// PLAN-3 (US-PLAN-3-01) — Which agent profiles belong to a template's
// roster.
//
// SAME SHAPE AS `plan_template_map`, deliberately: a template points
// at the durable thing (a published map version; an agent profile),
// never at anything that only exists inside one plan. Creating an
// instance copies this roster into fresh `planner_agent` rows in the
// new workspace — see `apis/planner/551_*` for that copy.
//
// APPEND-ONLY FOR NOW, same reason `plan_template_map` is: removing a
// row is a delete, and every delete in this backend is awaiting the
// founder's approval. `add_agent_profile_ids` on the template
// create/patch endpoints skips an id already attached, so it's safe
// to call twice.
table plan_template_agent {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int plan_template_id? {
      table = "plan_template"
    }

    int agent_profile_id? {
      table = "agent_profile"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "plan_template_id", op: "asc"}]}
    {type: "btree", field: [{name: "agent_profile_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "plan_template_id", op: "asc"}, {name: "agent_profile_id", op: "asc"}]}
  ]
}
