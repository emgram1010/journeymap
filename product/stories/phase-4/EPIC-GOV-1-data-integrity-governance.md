# GOV-1 — Data Integrity Governance

**Epic ID:** GOV-1
**Feature:** Every table follows the same relational standards, and the system proves it.
**Status:** Planning
**Depends on:** OBS-1 (audit results are logged as events)
**Goal:** The database stays correct as the product grows: normalized, uniquely keyed, properly related, no duplicate facts, no orphans, no junk, predictable behaviour on delete, atomic multi-step writes, and tests plus audits that fail loudly when a rule is broken.

---

## MVP scope (after review, 2026-10-12)

| In the MVP | Deferred (post-MVP) |
|---|---|
| US-GOV-1-01 standards · 02 constraint matrix · 03 guards · 04 schema audit · 05 integrity audit (MVP checks: orphans on new links, log replay vs. task status, stored job status vs. derived) · 07 append-only tests · 09 atomic writes (tested with mocks) · **new** 10 existing delete paths use the guards · **new** 11 normalized name keys · **new** 12 feature flags | 06 duplicate audit and unique indexes on existing tables (needed only when ROLE-1/STAGE-1 extras land) · 08 stale-write standard (single planner in the MVP) |

## Context

Xano tables give us primary keys, typed references to other tables, enums and indexes. They do **not** guarantee that a referenced row still exists after a delete, that a request is allowed to touch a row, or that a multi-step write is all-or-nothing. Phase-3 already acknowledges this (it lists "every rule the schema cannot enforce" and the function that does). This epic makes that discipline standard across **all** new phase-4 tables and adds automated checks, so the rules do not depend on anyone's memory.

**Verified limits (review, 2026-10-12):** `db.transaction` is atomic (all or nothing) and already used in the repo. Xano indexes cannot use expressions such as `lower(name)` (only primary, btree, btree|unique, gin), so case-insensitive uniqueness needs a normalized column. "Append-only" can be guaranteed for **endpoints**, but the Xano admin UI and MCP table tools can still edit rows directly; the daily audit is the safety net for that.

## The standards (apply to every new table)

| # | Standard | How it is enforced |
|---|---|---|
| S1 | **Primary key** `id` on every table | Schema audit (US-GOV-1-04) |
| S2 | **`created_at`** on every table; **`updated_at`** where rows change | Schema audit |
| S3 | **Foreign keys declared** as table references, and **indexed** | Schema audit |
| S4 | **Tenancy:** every root entity carries `account_id`; every child is reachable through a parent with `account_id`; every endpoint checks ownership | Guard functions + tenancy matrix test (E2E-1) |
| S5 | **No duplicate facts:** store a fact once and reference it. Documented exceptions: immutable snapshots (`journey_map_version`, `plan_publication`) | Constraint matrix review |
| S6 | **Natural-key uniqueness** via unique indexes (names per account, one pair per join row, one cell per stage × lens) | Schema audit against a manifest |
| S7 | **Finite sets are enums**, never free text | Schema audit |
| S8 | **Required fields** are validated on every write path (Xano columns are optional by default) | Validation rules registry (VAL-1) + tests |
| S9 | **Delete behaviour is explicit** for every foreign key: *restrict* (block), *cascade* (delete children), or *archive* (soft) | Delete/propagation matrix + tests |
| S10 | **Append-only tables** have no update or delete endpoint | Append-only tests |
| S11 | **Multi-step writes are atomic** (all or nothing) | Failure-injection tests |
| S12 | **Concurrent edits are detected** (stale write rejected with a friendly message) | `expected_updated_at` standard |
| S13 | **Additive changes only** to existing tables; duplicates audited **before** any new unique index | Dry-run audit story |

## Delete and propagation matrix (the model)

| Parent (delete attempted) | Children | Behaviour |
|---|---|---|
| `actor_role` *(post-MVP, with ROLE-1)* | lens references, `agent_role` | **Restrict** if referenced; otherwise **archive**. Never hard-delete a used role. |
| `planner_agent` | timelines, tasks, `agent_role` | No history: phase-3 delete (work returns to backlog). With a published timeline or log events: **deactivate** (P3A-1). |
| `planner_timeline` | tasks, publication | Draft: phase-3 delete. Published: **cannot be deleted** (P3A-1). |
| `journey_lens` that owns a stage | `journey_stage.owner_lens_id` | **Restrict** until the stage is reassigned |
| `journey_map` | versions, jobs | **Restrict** if any version exists; **archive** the map instead |
| `journey_map_version` | jobs, publications | **Never deleted** (immutable) |
| `plan_template` | instances (copies) | **Archive**; instances are independent copies |
| Plan instance (`planner_workspace`) | jobs, timelines, publications, logs | **Restrict** once any job, publication or log exists; **archive** instead (`is_archived`, P3A-1) |
| `work_item` (job) | `work_task` | **Cancel**, never delete once it has log events; tasks kept for history |
| `planner_task` | `planner_task_work_task` | **Cascade** the links; work tasks return to backlog |
| `activity_log`, `plan_change_log`, `plan_publication` | — | **Append-only; never updated or deleted** (only the retention policy may prune, never for jobs still open) |

## Existing Architecture (Do Not Break)

- Phase-3 planner tables and their propagation functions.
- Existing journey-map tables (grandfathered): `journey_stage`, `journey_lens`, `journey_cell` lack some unique indexes today. They are **audited first**, then fixed only when clean.

## Non-Goals

- No re-architecture of existing tables. No cross-database foreign-key tooling. No change to leakage or automation tables.

---

## Stories

### US-GOV-1-01 — Data standards document

**File:** `docs/data-standards.md`

- S1–S13 as a one-page checklist, with a short example per rule and the exact phrase to use in table-file header comments.

**Acceptance:** every new table file header cites the standards it relies on.

### US-GOV-1-02 — Constraint matrix for phase-4 tables

**File:** `docs/data-model-phase-4.md`

- For tables 80–92 and the additive columns: primary key, foreign keys with delete behaviour, unique indexes, required fields, and **every rule the schema cannot enforce** with the function or story that does.

**Acceptance:** every foreign key appears with a delete behaviour; every API-enforced rule names its owner.

### US-GOV-1-03 — Guard function library

**Files:** `functions/guards/*.xs`

- `assert_owns(entity, account)`, `assert_same_account(a, b)`, `assert_state(entity, allowed)`, `assert_not_archived(entity)`, `assert_fresh(entity, expected_updated_at)`.
- Each failed guard throws a catalogued error code (OBS-1) and logs a `rejected` event.

**Acceptance:** every new endpoint uses guards; none re-implements ownership checks inline.

### US-GOV-1-04 — Schema conformance audit

**File:** `scripts/audit-schema.mjs` (reads `static/tables/*.xs`), run in the test script

- Fails when a **new** table (80+) lacks a primary key or `created_at`, has an unindexed reference, has a declared natural key without its unique index (from a manifest), or uses free text where an enum is declared in the matrix.
- Existing tables are reported as warnings, not failures.

**Acceptance:** adding a table that breaks a rule fails the audit with a message naming the table and rule.

### US-GOV-1-05 — Runtime integrity audit (scheduled)

**Files:** `functions/audit_integrity.xs`, scheduled by OBS-1

- Checks, per reference, that the parent exists; plus: a job's stored status differs from the status derived from its tasks; work tasks whose stage key is not in their pinned version; `planner_task_work_task` rows pointing nowhere; log rows whose task is missing; jobs with no version; publications whose hash no longer matches; replaying a task's log disagrees with its stored status; roles referenced across accounts.
- Writes one event with the findings; the Health page lists them as issues with an owner.

**Acceptance:** zero findings on clean data; every seeded corruption is detected.

### US-GOV-1-06 — Duplicate audit before new unique indexes *(deferred)*

- Dry-run report for `journey_stage (journey_map, key)`, `journey_lens (journey_map, key)` and display-order uniqueness: lists duplicates with ids; a unique index is added **only** when the report is empty.

**Acceptance:** the report runs against a clone of map data; no index is added while duplicates exist.

### US-GOV-1-07 — Append-only enforcement

- Tests prove no endpoint can change or remove rows of `activity_log`, `plan_change_log`, `plan_publication`, `journey_map_version`.

**Acceptance:** every attempt is rejected with a catalogued code and logged.

### US-GOV-1-08 — Concurrency standard *(deferred; single planner in the MVP)*

- Edit endpoints for planner tasks, timelines, plan instances and templates accept `expected_updated_at`; mismatch → friendly "This was changed by someone else. Reload to see the latest." (no overwrite).

**Acceptance:** two simultaneous edits: the second is rejected and nothing is lost.

### US-GOV-1-09 — Atomic writes and failure injection

- Operations that write more than one row (publish version, add job, record event, publish to live, create instance from template) run in one `db.transaction`.
- Failures are simulated with **Xano unit-test mocks**, never with test switches inside production endpoints (review finding F18).

**Acceptance:** after a simulated failure, no partial rows exist.

### US-GOV-1-10 — Existing delete paths go through the guards (review finding F6)

- Every existing path that deletes journey-map rows (journey-map UI delete endpoints, AI tools such as `mutate_structure`) calls the same guards: a row that owns a stage cannot be deleted; a map with published versions cannot be deleted (archive instead).

**Acceptance:** each existing delete path is listed in the constraint matrix and tested; none can create an orphan.

### US-GOV-1-11 — Normalized name keys (review finding F4)

- Wherever a name must be unique regardless of case, store a second column `name_key` (`filters=trim|lower`) and put the unique index on it (with `account_id`). The display name keeps the user's casing.

**Acceptance:** "Sales Coordinator" and " sales coordinator " collide; the original casing is preserved for display.

### US-GOV-1-12 — Feature flags (review finding F11)

- One place for flags: `account.feature_flags` (JSON, additive). Flags used in the MVP: `required_fields_ui`, `publish_gate`.
- Rollout: off while building; turned **on** for an account at launch; turning off restores today's behaviour.

**Acceptance:** each flag switches behaviour per account; unknown flags are ignored safely.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-GOV-1-01 | Unit | Schema-audit parser on a table missing `id` | Fails naming the table |
| UT-GOV-1-02 | Unit | Table with an unindexed reference | Fails |
| UT-GOV-1-03 | Unit | Table whose natural key lacks a unique index | Fails |
| UT-GOV-1-04 | Unit | A fully compliant table | Passes |
| UT-GOV-1-05 | Unit | Grandfathered table with an issue | Warning only |
| UT-GOV-1-06 | Unit | Matrix lint: every FK in tables 80–92 has a delete behaviour | Pass |
| FT-GOV-1-01 | Functional (`workflow_tests/26_data_integrity.xs`) | Run the schema audit on current tables | Pass |
| FT-GOV-1-02 | Functional | Cross-account access on every new endpoint (generated list) | All denied |
| FT-GOV-1-03 | Functional | Attempt each restrict-delete in the matrix | Blocked with a catalogued message |
| FT-GOV-1-04 | Functional | Attempt each cascade-delete | Children handled; no orphans |
| FT-GOV-1-05 | Functional | Seed each corruption type, run the integrity audit | Each detected; clean data → zero |
| FT-GOV-1-06 | Functional | Duplicate audit on a clone with a seeded duplicate | Reported; index not added |
| FT-GOV-1-07 | Functional | Update/delete on each append-only table | Rejected and logged |
| FT-GOV-1-08 | Functional | Two edits with the same `expected_updated_at` | Second rejected; first persisted |
| FT-GOV-1-09 | Functional | Failure injected in each multi-write operation | No partial data |
| FT-GOV-1-10 | Functional | Integrity audit result visible as an event and on the Health page | Yes |
| FT-GOV-1-11 | Functional | Delete through each existing path (UI endpoint, `mutate_structure`) a row that owns a stage | Blocked with a friendly message |
| FT-GOV-1-12 | Functional | Duplicate names differing only in case/spaces | Second rejected; display casing kept |
| FT-GOV-1-13 | Functional | Flags on/off per account | Behaviour switches; other accounts unaffected |
| FT-GOV-1-14 | Functional | Job whose stored status disagrees with its tasks | Detected by the audit |

FT-GOV-1-06 and FT-GOV-1-08 run when their deferred stories are built.

**Completion gate:** all pass; schema audit runs inside `npm test`.

## Test Results

**2026-10-13 — Opus 5 build pass. Built, pushed to Xano workspace 1, and smoke-tested live.**

### Done and verified

| Story | State | Evidence |
|---|---|---|
| 01 standards doc | ✅ | `docs/data-standards.md` |
| 02 constraint matrix | ✅ | `docs/data-model-phase-4.md` |
| 03 guard library | ✅ live | `guards/assert_owns` (74), `assert_same_account` (75), `assert_not_archived` (76), `assert_state` (77), `assert_fresh` (78). All five smoke-tested on **both** paths. `assert_fresh` built but intentionally unwired (S12 deferred). |
| 04 schema audit | ✅ | `src/ops/schemaAudit.ts` + 13 unit tests in `npm test` (128/128). `scripts/audit-schema.mjs` for the readable report. New table 108 passes clean. |
| 05 integrity audit | ✅ live (existing-table checks) | `ops/audit_integrity` (80) + `tasks/19_ops_integrity_audit.xs` (daily 04:00 UTC). Later epics add their own checks. |
| 11 normalized name keys | ✅ as a standard | Documented in S6/data-standards; applied by the manifest (`actor_role`, `plan_template` require `name_key`). No table needs one yet. |
| 12 feature flags | ✅ live | Table `account_feature_flag` (108) + `ops/feature_enabled` (79). Verified: off by default, off for unknown keys, on per-account only, other accounts unaffected (**FT-GOV-1-13**). |

**End-to-end proof:** a guard refusal now shows up on the Health page as a grouped issue with a plain-English message, the correct owner (engineer vs. user) and a fix hint — the full OBS-1 + GOV-1 loop working together.

### Deviation from the epic, deliberate

US-GOV-1-12 specified `account.feature_flags` as a JSON column. **Built as a separate `account_feature_flag` table instead.** Adding a column to `account` requires `updateTableSchema`, which silently destroys that table's four `trim` validators (the bug that cost four validators during OBS-1). Creating a new table uses a different, safe path — confirmed, since this table's own validator survived. The table is also better relationally: a real enum for `flag_key` and a unique index, instead of an unvalidatable blob.

### Found while building: 729 real orphans in production

The integrity audit's first run, over 1,231 cells / 139 stages / 163 lenses:

| Check | Count |
|---|---|
| `journey_cell.journey_map` | 577 |
| `journey_lens.journey_map` | 76 |
| `journey_stage.journey_map` | 52 |
| `journey_stage.primary_actor_lens` | 24 |
| `journey_cell.stage`, `journey_cell.lens` | 0 |

The first three are one root cause: **deleting a journey map leaves its children behind.** Nothing reads them, so this is not urgent, but the delete path needs a guard (US-GOV-1-10) before it grows. The fourth is the fragile text key STAGE-1 replaces — already broken in 24 places, which is itself the argument for replacing it.

### Also fixed: a silent production failure in OBS-1

The heartbeat task had been running every 5 minutes for ~8 hours and writing **nothing**. Cause: `transform_timestamp` called inside a `db.query` `where` clause, which compiles to SQL and cannot call filter functions. `ops/health` had the identical bug and would have failed the first time it was opened. Both fixed and verified. Caught by comparing `event_log`'s row count against the rows this session had created — the task history showed it running happily.

Two more verified XanoScript constraints added to `CLAUDE.md`: no filter functions inside a `where` clause; no pipe nested inside a filter argument.

### Deferred — and why

| Story | Reason |
|---|---|
| 06 duplicate audit + unique indexes on existing tables | Only needed when ROLE-1/STAGE-1 extras land. |
| 08 concurrency standard | S12; single planner in the MVP. The guard exists, unwired. |
| 07 append-only enforcement tests | Tests `activity_log`, `plan_change_log`, `plan_publication`, `journey_map_version` — **none of these tables exist yet**. |
| 09 atomic writes | The operations it covers (publish version, add job, publish to live) **do not exist yet**. |
| 10 existing delete paths use guards | Needs `journey_stage.owner_lens_id` (STAGE-1) and `journey_map_version` (PUB-1). |

**This is a real sequencing finding, not an omission:** GOV-1's enforcement stories target tables that later epics create. They should be completed **by the epic that creates each table**, which is also when the integrity-audit check for it gets written. The constraint matrix lists each one with its owning epic so none is lost.

### Still outstanding from OBS-1

The four validators dropped by `updateTableSchema` still need restoring **by hand in the Xano dashboard**: `trim` on `user.name`, `trim`+`lower` on `user.email`, password strength on `user.password`, `trim` on `event_log.action`.
