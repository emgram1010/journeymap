# PUB-1 — Publish Version

**Epic ID:** PUB-1
**Feature:** Publishing a journey map checks it and freezes an immutable version that live work is pinned to.
**Status:** Planning
**Depends on:** AUTH-1
**Goal:** "Publish version" is a certification event: the server re-checks readiness, rejects with specific reasons if not ready, and otherwise stores a frozen, hash-verified version of the map's work definition. Existing publish behaviour (status active, automation compile, webhooks) keeps working.

---

## Context

`apis/journey_map/201_journey_map_journey_map_id_publish_POST.xs` today sets `status = "active"`, compiles the automation snapshot and pushes to webhooks, with **no gate and no version history**. `automation_snapshot` keeps one upserted record per map (not immutable history). `journey_map.version` is text only.

The earlier initiative (`product/validation-publish-execution/publishing/`) plans a publish gate (US-PUB-01…06) and version pinning and history (US-PUB-07…09). Behaviour tests in this epic are written so they hold whichever table design wins.

## Existing Architecture (Do Not Break)

- Publish endpoint 201 and the `publish_map` MCP tool: unchanged results when the gate flag is off.
- `automation_snapshot` and `stage_automation_config` keep their purpose (automation graph for external tools).
- Version pinning (`workflow_execution.map_version`) in the earlier initiative is not implemented here.

## Non-Goals

- No input/output coherence check yet. No dry-run simulation (later). No editing or deleting versions, ever.

## Decisions (resolved 2026-10-12, D-39)

- **One gate.** For generic maps the gate checks the MVP readiness rules (AUTH-1) **plus a real map title** (not empty or a default placeholder). Failures use the structured `gate_failures[]` shape planned in the earlier initiative (US-PUB-04). The earlier initiative's stricter checks (validator row, cost rate, leakage completeness, automation hand-offs) apply later, **only** to atomic or automation maps.
- **One version table.** `journey_map_version` is the single frozen version and history. Each row links to the `automation_snapshot` compiled in the same publish (`automation_snapshot_id`). AI runs will later pin to this table too (this replaces US-PUB-07/08's separate pinning and history).
- **Rollout.** The gate is controlled by the account flag `publish_gate` (GOV-1, US-GOV-1-12): off while building, on at launch.
- **Stale detection** (story 05) is deferred.

---

## Stories

### US-PUB-1-01 — Server-side readiness evaluation

**File:** `functions/evaluate_map_readiness.xs`, endpoint `GET journey_map/{id}/readiness`

- Same rules and reason codes as AUTH-1. Returns `{ ready, blockers[], warnings[] }`.
- Warnings (not blockers) in this epic: stage without done-when, owner cell without friction/notes is *not* a warning.

**Acceptance:** results equal the AUTH-1 golden fixtures case by case.

### US-PUB-1-02 — Gate inside publish (flagged)

- With the `publish_gate` flag on, publish rejects when blockers exist, returning structured `gate_failures[]` (`code`, `stage_key`, `lens_key`, `message`). Existing behaviour when the flag is off.

**Acceptance:** rejection changes **nothing** (map stays draft, no version written, no webhook, no compile).

### US-PUB-1-03 — Immutable version snapshot

**File:** `static/tables/82_journey_map_version.xs`

- Fields: `id`, `created_at`, `journey_map_id`, `version_no` (monotonic per map), `snapshot` JSON (stages in order with owner row, rows with their "does planned work?" value, work cells' task, done-when and duration in minutes, links), `content_hash`, `readiness_report` JSON, `automation_snapshot_id` (nullable), `published_by`, `published_at`.
- Unique `(journey_map_id, version_no)`.
- Written in the same transaction as the publish; if the write fails, publish fails.

**Acceptance:** each successful publish adds exactly one version with the next number.

### US-PUB-1-04 — Immutability and verification

- No update or delete endpoint exists for versions. Direct API attempts are rejected.
- `verify_version(id)` recomputes the hash from the stored snapshot.

**Acceptance:** verification passes untouched; fails if a snapshot is tampered with in a test.

### US-PUB-1-05 — Version read APIs and stale detection *(read APIs in MVP; stale detection deferred)*

- List versions for a map; get one version.
- `is_stale` is true when the live map has changed since the latest version (content hash of live definition ≠ latest version hash).

**Acceptance:** edit after publish → stale; republish → not stale; no-op save does not flip stale.

### US-PUB-1-06 — Regression of existing publish

- Flag off: identical response and side effects to today, including automation compile and webhooks.

**Acceptance:** existing tests and `automation_snapshot` output unchanged.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-PUB-1-01 | Unit | Hash function on the same definition with reordered keys | Same hash |
| UT-PUB-1-02 | Unit | Hash after changing a duration by 1 minute | Different hash |
| UT-PUB-1-03 | Unit | Hash ignores timestamps and ids that are not part of the definition | Same hash |
| FT-PUB-1-01 | Functional (`workflow_tests/16_publish_version.xs`) | Readiness endpoint over every AUTH-1 golden fixture | Matches expected codes |
| FT-PUB-1-02 | Functional | Publish a ready map (gate on) | Success; version 1 written; status active |
| FT-PUB-1-03 | Functional | Publish a not-ready map (gate on) | Rejected with `gate_failures[]`; no version, status still draft, no webhook/compile |
| FT-PUB-1-04 | Functional | Map 178 clone, gate on | Rejected; lists `OWNER_NOT_WORK_ROLE` for stages 1–4 and 7 |
| FT-PUB-1-05 | Functional | Fix owners on the clone, publish | Success |
| FT-PUB-1-06 | Functional | Publish twice | `version_no` 1 then 2; version 1 content unchanged |
| FT-PUB-1-07 | Functional | Attempt to update/delete a version via API | Rejected |
| FT-PUB-1-08 | Functional | `verify_version` on untouched / tampered snapshot | Pass / fail |
| FT-PUB-1-09 | Functional | Edit live map after publish | `is_stale = true`; republish → false |
| FT-PUB-1-10 | Functional | Gate flag off, publish any map | Same behaviour as before this epic |
| FT-PUB-1-11 | Functional | Snapshot write failure (simulated with a unit-test mock) | Publish fails; map stays draft |
| FT-PUB-1-14 | Functional | Map with an empty or default title | Rejected with a `gate_failures[]` entry |
| FT-PUB-1-15 | Functional | Successful publish | Version row links the automation snapshot compiled in the same publish |

FT-PUB-1-09 (stale) runs when stale detection is built.
| FT-PUB-1-12 | Functional | Other account's map | Denied |
| FT-PUB-1-13 | Functional | Regression: `workflow_tests/1–9` | Green |

**Completion gate:** all pass → record results → ready for PLAN-1.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity: `journey_map_version` (82)**

| Aspect | Rule |
|---|---|
| Keys | PK `id`; `journey_map_id → journey_map` (indexed, required); `published_by → user` |
| Uniqueness | `(journey_map_id, version_no)` |
| Required | map, version_no, snapshot, content_hash, published_by, published_at |
| Delete | **Never deleted or updated** (immutable). A map with versions can only be **archived**. |
| Atomic | Version row, map status change and automation compile succeed or fail **together** |
| Snapshot exception | The snapshot intentionally stores a frozen copy of the definition (documented exception to "no duplicate facts") |

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Not ready to publish | "This map isn't ready yet. {n} things need attention." (lists each, with a link) | `E-PUB-001` |
| Could not save the version | "We couldn't publish. Nothing was changed. Reference: {ref}." | `E-PUB-002` |
| Version fails verification | "A saved version doesn't match its fingerprint. An engineer needs to look at this." | `E-PUB-003` |
| Not your map | "You don't have access to this map." | `E-PUB-004` |
| Map archived | "This map is archived and can't be published." | `E-PUB-005` |

**Events logged** (`feature = PUB-1`): `evaluate_readiness`, `publish_version` (`success` with version number and duration; `rejected` with code; `failure`), `verify_version` (daily), `stale_detected`. The Health page shows **time of the last successful publish**.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-PUB-1-G01 | Functional | Schema audit on table 82 | Pass |
| FT-PUB-1-G02 | Functional | Failure injected after the version row, before the status change | Nothing persists; map unchanged |
| FT-PUB-1-G03 | Functional | Every rejection above | Friendly message, Reference, event with code, nothing written |
| FT-PUB-1-G04 | Functional | Successful publish | `success` event with version number and duration |
| FT-PUB-1-G05 | Functional | Delete or update a version | Rejected and logged |
| FT-PUB-1-G06 | Functional | Archive a map that has versions | Allowed; delete is blocked |
| FT-PUB-1-G07 | Functional | Daily verification detects a tampered snapshot | Issue appears on the Health page, owner = engineer |

## Test Results

_Not yet run._
