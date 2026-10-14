// PLN-1 (US-PLN-1-01) — Per-account planner settings. One row per account.
//
// Created lazily by the first `GET planner/settings` (PLN-4), which also
// seeds the four default models into planner_model. Nothing is seeded at
// migration time (US-PLN-1-07).
table planner_settings {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
      description = "Tenancy root. One settings row per account."
    }

    text currency_symbol? filters=trim {
      description = "Display only. Defaults to $ in the API when blank."
    }

    decimal human_hourly_rate? {
      description = "Blended hourly cost for a person agent. Non-negative, enforced by the API (PLN-4)."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}]}
  ]
}
