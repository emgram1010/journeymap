// USR-2 — which of the three modules a person has been granted.
//
// One row per (user, module). The three modules are the three things in the
// sidebar: `intelligence` (the Intelligent Layer), `planning` (the Planner),
// `execution` (Execution).
//
// A SIDE TABLE, and for the usual reason: `updateTableSchema` silently drops
// `validators` from any table that has them, confirmed four times now — `user`
// and `event_log` (GOV-1), `journey_stage`/`journey_lens` (STAGE-1). `user`
// carries trim on name, trim|lower on email and min:8|minAlpha:1|minDigit:1 on
// password, and three columns on `user` would cost all of them. Same answer as
// `account_feature_flag`, `journey_stage_owner` and `user_status`.
//
// 🔴 ABSENCE OF A ROW MEANS NOT GRANTED — the opposite default to
// `user_status`, where absence means active. That is deliberate and it is the
// safe direction for a permission: a missing row, a failed write, a half-run
// backfill and a brand-new user all land on "no". The cost is that every
// existing user DOES need a backfill before enforcement is switched on, which
// `usr/backfill_module_access` does and story 01 verifies by counting rows
// rather than by trusting the function's own report (the OBS-1 heartbeat
// lesson: it ran for eight hours writing nothing and reported success).
//
// 🔴 `granted` IS A BOOL, so read it as `granted == true` and never as
// `!= null`: `false == null` is TRUE in this engine (CLAUDE.md, VAR-1), so a
// null check cannot tell "revoked" from "never set" — and both of those must
// mean no.
//
// WHY A `granted` BOOL AND NOT ROW-PRESENCE: revoking by deleting the row
// would throw away who granted it and when. A revoke flips the bool and writes
// an event; the history survives. It also means the unique index below does
// the work of keeping one answer per (user, module) — a second row cannot
// exist to disagree with the first.
//
// WHY `module` IS TEXT AND NOT AN ENUM: a fourth module becomes a
// configuration change rather than a schema migration on a live table. The
// allow-list is still strict — it lives in `functions/usr/module_keys.xs` and
// every write validates against it (E-USR-007).
table user_module_access {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    // GOV-1 standard S2. This row is edited in place on every grant and
    // revoke, so it is not append-only and needs its own modified stamp.
    timestamp updated_at?=now {
      visibility = "private"
    }

    // The person this grant is about.
    int user_id {
      table = "user"
    }

    // Denormalised from `user`, so an account-scoped read needs no join.
    // Written from the ACTING admin's own record, never from a request body.
    int account_id {
      table = "account"
    }

    // One of `intelligence` | `planning` | `execution`. Validated against
    // `usr/module_keys` on every write, never against a literal list copied
    // into an endpoint.
    text module filters=trim

    // Read as `granted == true`. Default false: a row that exists but was
    // never explicitly granted is not a grant.
    bool granted?=false

    int granted_by_user_id? {
      table = "user"
    }

    timestamp granted_at?

    // Kept when the grant is revoked, so "who took this away, and when?" is
    // answerable from the row itself and not only from `event_log`.
    int revoked_by_user_id? {
      table = "user"
    }

    timestamp revoked_at?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    // 🔴 The real guard against two rows disagreeing about one answer. Built
    // with the table, not added later.
    {type: "btree|unique", field: [{name: "user_id", op: "asc"}, {name: "module", op: "asc"}]}
    // The middleware's read on every request: "this user, this module".
    // Covered by the unique index above; this one serves the account-scoped
    // Team page read instead.
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    // GOV-1 standard S3: every reference to another table leads an index, so
    // "what did this admin grant?" is answerable without a table scan.
    //
    // Both of these were caught by `schemaAudit.test.ts` (FT-GOV-1-01) before
    // the table was pushed — the revoke one was missing on the first draft.
    // That test reads this directory, so the standard is enforced on the file
    // rather than remembered.
    {type: "btree", field: [{name: "granted_by_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "revoked_by_user_id", op: "asc"}]}
  ]

  tags = ["phase-5", "usr-2"]
}
