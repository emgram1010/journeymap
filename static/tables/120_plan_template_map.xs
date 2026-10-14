// PLAN-1 (US-PLAN-1-01) — Which published maps a template accepts.
//
// A link table, append-only by GOV-1 standard S10: a row is added or
// removed, never edited, so it has `created_at` and deliberately NO
// `updated_at` (the schema audit checks for exactly this, and the
// manifest entry in schemaAudit.ts marks it appendOnly).
//
// Only a map with at least one PUBLISHED version may be attached
// (US-PLAN-1-02, E-PLAN-004). A draft map has no frozen content to
// generate work from, so accepting one would let a plan promise work
// that does not exist yet. That rule is API-enforced — the schema
// cannot see whether a version exists.
//
// Live id 120 (the epic reserved 84; Xano assigns its own ids).
table plan_template_map {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int plan_template_id? {
      table = "plan_template"
    }

    int journey_map_id? {
      table = "journey_map"
      description = "Must have at least one published version — enforced in PLAN-1's API, not here."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "plan_template_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "plan_template_id", op: "asc"}, {name: "journey_map_id", op: "asc"}]}
  ]
}
