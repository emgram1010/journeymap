// CAT-1 (US-CAT-1-02) — A way of doing the work, shared by many item
// types (e.g. "hard-goods" = pressure wash and wipe down; "textiles" =
// washer and dryer). Account-level catalog, referenced by key from an
// Items cell's rate lines (ITEM-1) and from the rate card (RATE-1).
//
// Created BEFORE item_type on purpose: item_type.default_method_id
// declares `table = "method"`, and a declared reference needs the
// target table to already exist.
//
// `role_id` is a plain int, NOT a declared reference to `actor_role` —
// that table does not exist yet (ROLE-1 is deferred; its number is
// reserved at 80 but unused). Reserved and unvalidated in MVP, exactly
// as the epic specifies. When ROLE-1 lands, this stays additive-only:
// still no declared FK until we are certain updateTableSchema can add
// one without dropping the `trim|lower` validators below (CLAUDE.md).
//
// `sub_journey_map_id` references the EXISTING `journey_map` table and
// IS declared + indexed (S3) — unlike role_id, that table is live today.
// 0 = no sub-journey: "same steps as the stage's own cell, just a
// different rate" (PRD §3.2) is a valid, deliberate state, not a gap.
//
// GOV-1 standards: S1 (primary key), S2 (created_at + updated_at — a
// method's label/sub-journey/role can all be edited), S3 (declared +
// indexed reference on sub_journey_map_id), S4 (account_id tenancy),
// S6 (unique account_id + key), S9 (delete: restrict once referenced
// by a journey_lens_item row or a stage_rate row — enforced by the API,
// those tables do not exist yet; is_active = archive otherwise).
table method {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
      description = "Tenancy. A method belongs to exactly one account, same as item_type."
    }

    text key? filters=trim|lower {
      description = "Stable identifier, e.g. 'hard-goods'. 2-40 chars, lowercase letters/digits/hyphens, enforced by the API (apis/catalog/*) -- this filter only trims and lowercases what is typed. Referenced by key from Items cell lines and the rate card, so it is never edited after creation (API-enforced, D-2)."
    }

    text label? filters=trim {
      description = "Display name, 1-80 chars, no HTML (API-enforced, E-CAT-003)."
    }

    int sub_journey_map_id? {
      table = "journey_map"
      description = "The steps this method follows, when they differ from the stage's own cell. 0 = none ('same steps, different rate'). Must be a map in the SAME account as this method (API-enforced, E-CAT-007). This is a plain reference to the map, NOT a journey_link -- the link from an Items cell to this map is created in ITEM-1, when the method is actually used at a stage."
    }

    int role_id? {
      description = "Reserved for ROLE-1's actor_role table (deferred). 0 = none. Deliberately NOT a declared reference -- actor_role does not exist yet, and not validated against anything in MVP (CAT-1 epic, US-CAT-1-02)."
    }

    bool is_active?=true {
      description = "Deactivate instead of delete once referenced by a map's item list or a published rate card (E-CAT-005). Turning this off hides the method from new Items-cell lines without touching history."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "is_active", op: "asc"}]}
    {
      type : "btree|unique"
      field: [
        {name: "account_id", op: "asc"}
        {name: "key", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "sub_journey_map_id", op: "asc"}]}
  ]
}
