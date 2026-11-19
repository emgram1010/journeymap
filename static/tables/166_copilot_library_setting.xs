// COP-11 (2026-11-18) — the three size and tidiness limits of one account's skill library, as
// settings the owner can change, not numbers in code. One row per account; no row = the defaults
// (50 items, 4000 words, 30 days, trusted after 5 uses, switched off after 2 overrides), which copilot/skill_write, copilot/skill_library and the
// stale flag all fall back to the same way.
//
// Written ONLY by POST copilot/library_settings (a signed-in admin), inside server bounds:
// items 10-200, words 1000-20000, days 7-365. Never written by an AI tool.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key (account_id).
table copilot_library_setting {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int account_id? {
      table = "account"
    }

    int max_active_items? {
      description = "The most items that may be active at once. Default 50."
    }

    int max_load_words? {
      description = "About how many words of skills one run loads. Default 4000."
    }

    int stale_after_days? {
      description = "An active item not used for this many days is flagged. Default 30."
    }

    int updated_by_user_id? {
      table = "user"
    }

    int trial_min_uses? {
      description = "COP-9-05: a trial item becomes trusted after this many uses (in at least 2 chats or runs) with no owner override. Default 5."
    }

    int trial_max_overrides? {
      description = "COP-9-05: a trial item the owner undoes or edits this many times is switched off and flagged. Default 2."
    }

    int step_up_daily_cap? {
      description = "COP-13 part B: the most times in 24 hours the copilot may ask to use the stronger, dearer model. Default 5."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
