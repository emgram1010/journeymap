// PLN-1 (US-PLN-1-01) — The AI model price list, per account.
//
// The four defaults (DEFAULT_MODELS in the planner frontend) are seeded on
// the first `GET planner/settings` (PLN-4) with is_custom = false; anything
// the account adds itself is is_custom = true.
//
// DEVIATION FROM THE EPIC: `updated_at` is not in US-PLN-1-01's column
// list, but rates are editable (PLN-4), so the table is not append-only and
// GOV-1 standard S2 requires it. Added deliberately.
table planner_model {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
      description = "Tenancy root."
    }

    text model_key? filters=trim {
      description = "Stable identifier, e.g. claude-sonnet-4-5. Unique within an account."
    }

    text label? filters=trim

    decimal input_per_1m? {
      description = "Cost per 1M input tokens. Non-negative, enforced by the API (PLN-4)."
    }

    decimal output_per_1m? {
      description = "Cost per 1M output tokens. Non-negative, enforced by the API (PLN-4)."
    }

    bool is_custom?=false {
      description = "False for the four seeded defaults, true for anything the account added."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}, {name: "model_key", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}
