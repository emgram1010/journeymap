// ITEM-1 (US-ITEM-1-02) — Which items this map's Items row uses. A map
// with a 5-item work type should not have to scroll a 300-item catalog
// (D-2); this is the per-map subset, chosen once, referenced by every
// Items cell's lines.
//
// A SIDE TABLE for the usual reason (CLAUDE.md): `journey_lens` has
// several `filters=trim` text columns, and `updateTableSchema` silently
// drops them from any table it touches. Same answer as
// `journey_lens_planned_work`, `journey_stage_owner`, `user_status`.
//
// GOV-1 standards: S1 (primary key), S2 (created_at + updated_at — a
// map's item set is edited, not append-only), S3 (declared + indexed
// references on both journey_lens and item_type_id), S6 (unique
// journey_lens + item_type_id — an item is chosen at most once per
// map), S9 (delete: removing an item here cascades its lines out of
// every Items cell on this map, enforced by the API in the same
// transaction — US-ITEM-1-02's own acceptance criterion, not a
// deactivate-instead-of-delete case, since this table has no is_active
// of its own; the referenced item_type itself deactivates/restricts).
table journey_lens_item {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int journey_lens? {
      table = "journey_lens"
      description = "The Items row (a journey_lens with template_key = 'items-v1') this choice belongs to."
    }

    int item_type_id? {
      table = "item_type"
      description = "Must be active and in the SAME account as the map (API-enforced, E-ITM-002)."
    }

    int sort_order? {
      description = "Display order within the picker. Plain int, no uniqueness constraint -- ties are broken by id."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "journey_lens", op: "asc"}]}
    {
      type : "btree|unique"
      field: [
        {name: "journey_lens", op: "asc"}
        {name: "item_type_id", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "item_type_id", op: "asc"}]}
  ]
}
