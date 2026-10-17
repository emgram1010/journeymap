// GOV-1 (US-GOV-1-12) — Per-account feature flags.
//
// GOV-1 standards: S1, S2, S3, S4 (account-scoped), S6 (unique
// account_id + flag_key), S7 (flag_key is an enum), S9 (delete =
// cascade with the account; a flag row has no history worth keeping).
// See docs/data-standards.md.
//
// WHY A TABLE AND NOT `account.feature_flags` JSON (which EPIC-GOV-1
// originally specified): adding a column to `account` means running
// updateTableSchema against it, and that silently destroys the `trim`
// validators on name/description/location/ai_context — the same bug
// that cost four validators on `user` and `event_log` during OBS-1.
// Creating a NEW table uses a different, safe code path (confirmed:
// this table's `note` validator survived creation). A row-per-flag
// table is also easier to audit and query than a JSON blob, and the
// enum means an unknown flag key cannot be stored at all.
//
// Reading flags: functions/ops/feature_enabled.xs. Unknown or missing
// flag = OFF, always. Flags are off while a feature is being built and
// turned on per account at launch.
table account_feature_flag {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
      description = "The account this flag applies to. Flags are per-account on purpose: a flag can be on for one customer and off for everyone else."
    }

    enum flag_key? {
      values = ["required_fields_ui", "publish_gate"]
      description = "Known flags only. An unknown key cannot be stored, which is what makes unknown flags safe to ignore at read time."
    }

    bool enabled?

    text note? filters=trim {
      description = "Why this flag was turned on or off, for whoever reads it later."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {
      type : "btree|unique"
      field: [
        {name: "account_id", op: "asc"}
        {name: "flag_key", op: "asc"}
      ]
    }
  ]
}
