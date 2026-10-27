// USR-1 — whether a user may still sign in, and who switched them off.
//
// A SIDE TABLE, not a column on `user`, and that is not a style choice:
// `updateTableSchema` silently drops `validators` (trim/lower/min-length)
// from any table that has them, confirmed three times now — on `user` and
// `event_log` during GOV-1, and again on `journey_stage`/`journey_lens`
// during STAGE-1. `user` carries `trim` on name, `trim|lower` on email and
// `min:8|minAlpha:1|minDigit:1` on password. Adding a column there would
// cost all of them, repairable only by hand in the Xano dashboard. Same
// answer as `account_feature_flag` and `journey_stage_owner`.
//
// ABSENCE OF A ROW MEANS ACTIVE. That is what makes this additive: every
// user who exists today needs no row and no backfill, and every existing
// endpoint that does not know about this table keeps behaving as it did.
//
// A user is referenced by `journey_architecture.owner_user`,
// `planner_agent.user_id`, `agent_profile.user_id`,
// `activity_log.performer_user_id` and `event_log.user_id`; deleting one
// behind a live reference orphans history that variance and the Health page
// read, and raises no error while doing it.
//
// AMENDED 2026-10-22 (US-USR-1-08): the founder asked for a real delete, so
// `admin/user_delete` exists. The paragraph above became its guard rather
// than its prohibition — it counts the first four of those tables and
// refuses with `E-USR-013` if any of them points at the person, naming
// deactivation as the thing to do instead. When it does proceed it destroys
// this row and the `user` row, together, in one transaction. `event_log` is
// deliberately not counted: a historical entry naming someone who has since
// been removed is what an audit trail is for.
//
// 🟡 The LIVE table description in Xano still ends "Nobody is ever
// deleted", written before that story existed. It is documentation, not
// schema, and `updateTableMetadata` is not a tool this project trusts on an
// existing table, so it was left rather than risked. One line to correct by
// hand in the dashboard.
table user_status {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    // GOV-1 standard S2. This row is edited in place every time someone is
    // switched off or back on, so it is not append-only and needs its own
    // modified stamp.
    timestamp updated_at?=now {
      visibility = "private"
    }

    // The user this status is about. Unique — one row per user, at most.
    int user_id {
      table = "user"
    }

    // Denormalised from `user`, so an account-scoped read needs no join.
    // Written from the ACTING user's own record, never from a request body.
    int account_id {
      table = "account"
    }

    // Read this as `is_active == true`, never as `!= null`: `false == null`
    // is TRUE in this engine (CLAUDE.md, VAR-1), so a null check cannot tell
    // "switched off" from "never set".
    bool is_active?=true

    timestamp deactivated_at?

    int deactivated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "user_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    // GOV-1 standard S3: every reference to another table leads an index, so
    // "what did this admin switch off?" is answerable without a table scan.
    {type: "btree", field: [{name: "deactivated_by_user_id", op: "asc"}]}
  ]

  tags = ["phase-5", "usr-1"]
}
