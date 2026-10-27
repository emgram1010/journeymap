// CAT-1 (US-CAT-1-01) — A countable thing the business processes (e.g.
// "chair-resin", "table-6ft"). Account-level catalog, referenced by key
// from an Items row's item list (ITEM-1), the rate card (RATE-1) and
// order lines (EST-1). This is a PROCESS catalog, not inventory
// (D-IR-10): it answers "how is this processed", never "how many do I
// own" or "can it be rented" -- that stays in the booking system, joined
// optionally through external_ref.
//
// Created AFTER `method` (static/tables/136_method.xs) because
// default_method_id declares `table = "method"`, and a declared
// reference needs the target table to already exist.
//
// GOV-1 standards: S1 (primary key), S2 (created_at + updated_at), S3
// (declared + indexed reference on default_method_id), S4 (account_id
// tenancy), S6 (unique account_id + key), S7 (unit is a finite set, an
// enum not free text), S9 (delete: restrict once referenced by a
// journey_lens_item row or a stage_rate row -- enforced by the API,
// those tables do not exist yet; is_active = archive otherwise).
table item_type {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
      description = "Tenancy. An item type belongs to exactly one account, same as method."
    }

    text key? filters=trim|lower {
      description = "Stable identifier, e.g. 'chair-resin'. 2-40 chars, lowercase letters/digits/hyphens, enforced by the API (apis/catalog/*) -- this filter only trims and lowercases what is typed. Referenced by key from Items cell lines, the rate card and order lines, so it is never edited after creation (API-enforced, D-2)."
    }

    text label? filters=trim {
      description = "Display name, 1-80 chars, no HTML (API-enforced, E-CAT-003)."
    }

    enum unit?=each {
      values = ["each", "set", "pair"]
      description = "What one unit of this item is. 'set' means one line of quantity 1 covers a whole group of pieces (e.g. a game with 10 pieces), rather than counting pieces individually."
    }

    int default_method_id? {
      table = "method"
      description = "Seeds the first line in a new Items cell for this item (ITEM-1). 0 = none. A convenience only -- it never does math itself and can always be overridden per stage. Must be an active method in the SAME account, or 0 (API-enforced, E-CAT-011)."
    }

    text size_label? filters=trim {
      description = "Optional grouping label only, e.g. '6ft'. NEVER used in any calculation (D-IR-2) -- a size difference that actually changes time is a different item_type with its own rate, not a factor on this field. Up to 20 chars (API-enforced, E-CAT-009)."
    }

    text external_ref? filters=trim {
      description = "Optional seam to a booking or inventory SKU. Up to 60 chars, no HTML (API-enforced, E-CAT-010). Emgram never owns stock levels or availability (D-IR-10) -- this is a reference only."
    }

    bool is_active?=true {
      description = "Deactivate instead of delete once referenced by a map's item list or a published rate card (E-CAT-005). Turning this off hides the item from new Items-cell lines without touching history."
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
    {type: "btree", field: [{name: "default_method_id", op: "asc"}]}
  ]
}
