// STAGE-1 (US-STAGE-1-06) — "Does this row do planned work?" switch,
// one row per lens that has been explicitly set (MVP replacement for
// ROLE-1).
//
// WHY A TABLE AND NOT `journey_lens.does_planned_work` (what
// EPIC-STAGE-1 originally specified): journey_lens has several
// `filters=trim` text columns (key, label, description, template_key,
// role_prompt, persona_description, standing_constraints). Same
// confirmed updateTableSchema bug as journey_stage_owner above.
//
// A missing row means "not set" — the default comes from the lens's
// actor_type (yes for internal/ai_agent, no otherwise), computed by
// functions/does_planned_work.xs. A present row's value always wins
// over the type default.
table journey_lens_planned_work {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int journey_lens? {
      table = "journey_lens"
      description = "The lens (actor row) this switch applies to. One row per lens — see the unique index."
    }

    bool does_planned_work? {
      description = "Explicit override. No row for a lens means 'use the type default' instead."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "journey_lens", op: "asc"}]}
  ]
}
