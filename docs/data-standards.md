# Data standards (GOV-1)

Every **new** table in this codebase follows these. The schema audit
(`npm test` in `webapp/protype-2`, via `src/ops/schemaAudit.ts`) enforces
the machine-checkable ones and fails the build when a new table breaks
them. Existing tables created before GOV-1 are **grandfathered**: the
audit reports them as warnings, never failures.

Put this line in the header comment of every new table file, listing the
standards that needed a judgement call:

```
// GOV-1 standards: S1-S4, S6, S7, S9 (delete = restrict, see docs/data-model-phase-4.md)
```

---

## The thirteen standards

| # | Standard | What it means in practice | Enforced by |
|---|---|---|---|
| **S1** | Primary key | Every table has `int id` with a `{type: "primary"}` index. | Schema audit |
| **S2** | Timestamps | Every table has `created_at`. Tables whose rows change also have `updated_at`. Append-only tables deliberately have **no** `updated_at`. | Schema audit |
| **S3** | Declared + indexed references | A column pointing at another table declares `table = "other"` **and** has a btree index. Without the index, every join and every orphan check does a full scan. | Schema audit |
| **S4** | Tenancy | Every root entity carries `account_id`. Every child is reachable from a root that has one. Every endpoint proves ownership with a guard before reading or writing. | `functions/guards/*`, E2E-1 tenancy matrix |
| **S5** | No duplicate facts | Store a fact once; reference it everywhere else. **Documented exceptions:** immutable snapshots (`journey_map_version`, `plan_publication`) deliberately copy data, because their whole job is to freeze it. | Constraint matrix review |
| **S6** | Natural-key uniqueness | If two rows would be "the same thing" to a human, a unique index says so: a name per account, one row per join pair, one cell per stage × lens. | Schema audit (manifest) |
| **S7** | Finite sets are enums | A fixed list of values is an `enum` column, never free text. | Schema audit |
| **S8** | Required fields validated on write | Xano columns are optional by default, so "required" is an API rule, not a schema rule. Every write path validates it. | VAL-1 rules registry |
| **S9** | Explicit delete behaviour | Every reference declares one of: **restrict** (block the delete), **cascade** (delete the children), **archive** (soft-delete instead). No reference is left undecided. | Delete matrix + tests |
| **S10** | Append-only means append-only | `activity_log`, `plan_change_log`, `plan_publication`, `journey_map_version` have **no** update or delete endpoint. Corrections are new rows. | Append-only tests |
| **S11** | Multi-row writes are atomic | Anything writing more than one row runs inside `db.transaction`. A failure halfway leaves nothing behind. | Failure-injection tests (mocks) |
| **S12** | Concurrent edits are detected | Edit endpoints take `expected_updated_at` and refuse a stale write rather than overwriting someone. *(Deferred while there is a single planner.)* | `assert_fresh` guard |
| **S13** | Additive changes only | Never remove or retype a column on an existing table. Audit for duplicates **before** adding any unique index to an existing table. | Review + dry-run audit |

---

## Hard-won platform constraints

These come from pushing real code to Xano and watching it fail. The full
list, with the exact error messages, is in `CLAUDE.md` under
"XanoScript constraints — verified live". The two that shape **schema**
decisions:

- **Never run `updateTableSchema` against a table that has column
  validators** (`trim`, `lower`, password rules). It silently drops every
  one of them, across the whole table, even when you submit them back
  unchanged. Creating a *new* table is safe (different code path).
  To add a column to an existing table that has validators, either do it
  in the Xano dashboard UI, or put the new data in a new table instead.
- **Case-insensitive uniqueness needs a `*_key` column.** Xano indexes
  cannot be expressions, so there is no `unique(lower(name))`. Store a
  second column (`name_key`, `filters=trim|lower`) and put the unique
  index on `(account_id, name_key)`. The display column keeps the user's
  original casing. (S6 + US-GOV-1-11.)

---

## Guards (S4, S9, S12)

Ownership and state checks are **never** written inline in an endpoint.
They call the shared library so the rule, the error code and the logged
event are identical everywhere:

| Guard | Use it when | Error code |
|---|---|---|
| `guards/assert_owns` | Before reading or writing anything owned by an account. | `E-GOV-001` |
| `guards/assert_same_account` | Before linking two entities together. | `E-GOV-002` |
| `guards/assert_state` | Before an action that only makes sense in certain states. | `E-GOV-003` |
| `guards/assert_not_archived` | Before writing to anything archivable. | `E-GOV-004` |
| `guards/assert_fresh` | Before an edit that could overwrite someone else's. *(S12, deferred.)* | `E-GOV-005` |

Every guard logs a `rejected` event through `ops/log_event` before it
throws, so a refused action is just as visible on the Health page as a
broken one.
