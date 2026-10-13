# E2E-1 — End-to-End Validation

**Epic ID:** E2E-1
**Feature:** Proof that the whole loop works and nothing leaks between layers.
**Status:** Planning
**Depends on:** all other phase-4 epics
**Goal:** One synthetic job travels **map → publish version → plan template → instance → job → schedule → publish to live → perform → log → variance** with no manual data re-entry. Integrity audits confirm nothing is orphaned, copied or crossing accounts, and that no existing capability regressed.

---

## MVP scope (after review, 2026-10-12)

- Runs against the **MVP slice** in the README: no role registry, no blocks, no bulk publish, no stage aggregates, no LEAN-1 migration.
- The synthetic map uses existing cell fields (task, done-when, duration) and the rows' "does planned work?" switch.
- Includes one **Done without Start** case.
- The supportability drill is a **demo checklist** (each problem found and explained using only the Health page), not a timed test (review finding F22).
- FT-E2E-1-06 (blocks) is deferred.

## Context

Each epic tests itself. This epic tests the **seams**: version pinning under change, ownership of the three durations, append-only guarantees, tenancy everywhere, and data safety on real maps.

## Existing Architecture (Do Not Break)

- Everything in the earlier epics, plus existing suites: `npm test`, `workflow_tests/1–9`, existing Playwright specs.

## Non-Goals

- No performance or load testing beyond a sanity check. No new features.

---

## Stories

### US-E2E-1-01 — Synthetic loop fixture and test

**File:** `workflow_tests/24_end_to_end_loop.xs`

- Builds a **non-logistics** 3-stage map (for example: Receive → Check → File) with two work-doing rows and one customer-type row.
- Runs the full loop in one test and asserts after every step.

**Acceptance:** completes with the expected statuses, timestamps, durations and variance; uses only public APIs.

### US-E2E-1-02 — A second, different work type

- Repeats the loop with a different shape (for example: two roles, no continuous stages) in the **same plan instance** to prove the planner can group work types manually.

**Acceptance:** both jobs schedule and execute; each stays pinned to its own map's version.

### US-E2E-1-03 — Pinning under change

- Publish v1 → create a job → edit the live map → publish v2 → create a second job → run both.

**Acceptance:** job 1 content and expected minutes remain v1; job 2 uses v2; the variance report reflects each job's own expected values.

### US-E2E-1-04 — Integrity audit queries

**File:** `scripts/audit-loop-integrity.mjs` (and an equivalent Xano function)

- Detects: work tasks whose stage/lens key is missing from the pinned version; planner links to missing work tasks; log rows without a task; work items without a version; publications whose snapshot hash no longer matches; timelines marked published without a publication.

**Acceptance:** audit returns zero findings after the full loop; each seeded corruption is caught.

### US-E2E-1-05 — Tenancy matrix

- For every new endpoint, call as a second account and as an unassigned performer.

**Acceptance:** every call is denied or returns nothing; a generated table of endpoints × results is saved with the test results.

### US-E2E-1-06 — Data-safety rehearsal on real data

- Clone map 178; run the STAGE-1 owner backfill (dry-run, then real, then again); attempt publish with the gate on. (LEAN-1 and ROLE-1 backfills are deferred with those epics.)

**Acceptance:** backfill is idempotent; publish rejects until stage owners are fixed (stages 1–4 and 7 are owned by a customer-type lens today); after fixing, publish succeeds; the original map 178 is untouched.

### US-E2E-1-07 — Regression gate and sanity performance

- Run all existing suites. Hydrated read of a job with 20 tasks and the today list for a performer with 50 items each respond within a reasonable time (record the numbers; set the threshold after the first run).

**Acceptance:** existing suites green; numbers recorded in Test Results.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-E2E-1-01 | Functional | Full loop, work type A | All steps pass; log, durations, variance as expected |
| FT-E2E-1-02 | Functional | Second work type in the same instance | Both execute; correct pinning |
| FT-E2E-1-03 | Functional | Publish v2 mid-flight | Job 1 on v1, job 2 on v2 |
| FT-E2E-1-04 | Functional | Planner changes after publish to live | Performer view unchanged; change log rows present |
| FT-E2E-1-05 | Functional | Planner tweaks duration | Expected unchanged; scheduled changed; variance shows both |
| FT-E2E-1-06 | Functional | Block with continuous stages | Shows as one scheduled item; two log-able steps |
| FT-E2E-1-07 | Functional | Blocked with a reason, then unblocked, then done | Log shows all events; blocked minutes reported |
| FT-E2E-1-08 | Functional | Outlier task | Flagged |
| FT-E2E-1-09 | Functional | Audit after the loop | Zero findings |
| FT-E2E-1-10 | Functional | Audit after seeded corruptions | Each caught |
| FT-E2E-1-11 | Functional | Tenancy matrix | All denied/empty |
| FT-E2E-1-12 | Functional | Map 178 clone rehearsal | Owner backfill idempotent; gate behaves as described; original untouched |
| FT-E2E-1-13 | Functional | Regression: `workflow_tests/1–9`, `npm test`, existing e2e | Green |
| FT-E2E-1-14 | Functional | A performer taps Done without Start | Accepted; variance shows unknown actual with a warning |
| E2E-E2E-1-01 | UI (Playwright) | Author a small map → publish → plan → publish to live → perform on a phone viewport | Whole path works through the UI |

**Completion gate:** all pass; results recorded; phase-4 epics moved to `completed-epics/`.

## Governance and Supportability Validation

These stories prove the governance epics (OBS-1, GOV-1, VAL-1) hold across the whole loop.

### US-E2E-1-08 — Governance audit across the loop

- After the full loop, run the schema audit and the runtime integrity audit.

**Acceptance:** zero findings; every seeded corruption is detected and appears on the Health page with an owner.

### US-E2E-1-09 — Supportability drill (a non-engineer can diagnose)

- Seed one of each: validation rejection, permission rejection, stale write, logging failure, integrity corruption.
- Using **only the Health page**, identify each problem, who can fix it, and copy the diagnostic bundle for the AI.

**Acceptance:** each problem is found and explained using only the Health page, recorded as a demo checklist; the bundle for each contains the catalog entry, ordered events, entity ids and no sensitive values.

### US-E2E-1-10 — Every step leaves a trail

- Walk the loop and verify an event exists for each step: publish version, create instance, add job, schedule, publish to live, each performer action, and each variance computation (success), plus one rejection and one failure per feature.

**Acceptance:** a checklist of expected events matches the log exactly (nothing missing, nothing duplicated).

### US-E2E-1-11 — Junk-in test across all forms

- Run the VAL-1 junk corpus through every phase-4 form and endpoint end to end.

**Acceptance:** nothing junk is stored; every rejection is friendly, referenced and logged.

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-E2E-1-G01 | Functional | Schema audit + integrity audit after the loop | Zero findings |
| FT-E2E-1-G02 | Functional | Seeded corruptions | Each detected, listed with owner |
| FT-E2E-1-G03 | Functional | Event checklist for the loop | Exact match |
| FT-E2E-1-G04 | Functional | Junk corpus through all endpoints | Nothing stored; 422/409/403 shapes correct |
| FT-E2E-1-G05 | Functional | Diagnostic bundle for each seeded problem | Complete, redacted, tenant-safe |
| E2E-E2E-1-G01 | UI | Supportability drill through the Health page | Each issue found and explained in plain language |

## Test Results

_Not yet run._
