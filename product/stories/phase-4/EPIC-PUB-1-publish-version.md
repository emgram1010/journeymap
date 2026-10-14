# PUB-1 — Publish Version

**Epic ID:** PUB-1
**Feature:** Publishing a journey map checks it and freezes an immutable version that live work is pinned to.
**Status:** Done (see Test Results) — gate, versions and integrity all built and verified end-to-end over real HTTP; gate ships behind `publish_gate`, which is OFF everywhere
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

**2026-10-14 — Opus 5 build pass. Built, pushed to workspace 1, and verified end to end over real authenticated HTTP.**

This is the first epic whose endpoints were driven over genuine authenticated HTTP rather than only at the function level: the browser session from AUTH-1 was reused to call the live API with a real bearer token, which closed the verification gap VAL-1, TIME-1 and STAGE-1 all had to leave open.

### What shipped

| Piece | Where |
|---|---|
| `journey_map_version` table | `static/tables/112_journey_map_version.xs` — **Xano assigned id 112, not the 82 the README reserved** (ids are auto-assigned; 82 was free but unused). README corrected. |
| Canonical serialisation + hash | `functions/pub/canonical_hash.xs` (91) + `webapp/protype-2/src/versionHash.ts` |
| Snapshot builder | `functions/pub/build_map_snapshot.xs` (92) |
| Server readiness (AUTH-1 parity) | `functions/pub/evaluate_readiness.xs` (93) |
| Publish gate (readiness + real title) | `functions/pub/evaluate_gate.xs` (94) |
| Version verification | `functions/pub/verify_version.xs` (95) |
| Gate + version write in publish | `apis/journey_map/201_..._publish_POST.xs` (201, modified) |
| Readiness / versions / one-version reads | apis 520, 521, 522 |
| Functional spec | `workflow_tests/16_publish_version.xs` |

### Story results

| Story | State | Evidence |
|---|---|---|
| 01 Server-side readiness | ✅ | Returns `{ready, blockers[], warnings[]}` via `GET journey_map/{id}/readiness` (api 520). Verified identical to AUTH-1 twice: against the **live QA map** (server said `ready_count 1 / total 8` with 7 × `NO_OWNER` — exactly what the browser UI showed), and against the **AUTH-1 golden fixture** (stages 1–4 and 7 `OWNER_NOT_WORK_ROLE`, stages 5/6/8 `NO_TASK` + `NO_DURATION`). |
| 02 Gate inside publish (flagged) | ✅ | Gate runs before the first write. Rejection returns 400 / `E-PUB-001` with the friendly message. |
| 03 Immutable version snapshot | ✅ | Version 1 then 2 written on successive publishes, each with `content_hash`, `readiness_report`, `published_by`, `published_at`, and the automation snapshot it was compiled with. |
| 04 Immutability and verification | ✅ | No update/delete endpoint exists — `DELETE` and `PATCH` on `/journey_map_version/{id}` both return 404. `verify_version` passes on untouched rows and fails on a tampered one. |
| 05 Version read APIs | ✅ (stale detection deferred per D-39) | `GET journey_map/{id}/versions` and `GET journey_map_version/{id}` (the latter also reports `verified`). |
| 06 Regression of existing publish | ✅ | With the flag off: HTTP 200, status active, automation snapshot version incremented, webhooks path unchanged, `map_version`/`gate` null. |

### Functional cases, run live

| ID | Result |
|---|---|
| FT-PUB-1-01 | ✅ Readiness over the AUTH-1 golden fixture matches code for code |
| FT-PUB-1-02 | ✅ Ready map, gate on → success, version 1 written, status active |
| FT-PUB-1-03 | ✅ Not-ready map, gate on → rejected; **verified nothing changed**: map still draft, automation snapshot still v3, version table still empty |
| FT-PUB-1-04 | ✅ Map 178's shape reports `OWNER_NOT_WORK_ROLE` for stages 1–4 and 7 (run against the fixture, not the live map — see note below) |
| FT-PUB-1-06 | ✅ Publish twice → `version_no` 1 then 2; identical content produced an identical hash, proving determinism across publishes |
| FT-PUB-1-07 | ✅ `DELETE` and `PATCH` on a version → 404 |
| FT-PUB-1-08 | ✅ `verify_version` true on untouched; changing one stored duration 15→16 flipped it false |
| FT-PUB-1-10 | ✅ Gate flag off → behaviour identical to before this epic |
| FT-PUB-1-12 | ✅ Another account's map → 403 `E-PUB-004` |
| FT-PUB-1-14 | ✅ Title "Untitled Journey Map" → `PLACEHOLDER_TITLE`, publish 400 |
| FT-PUB-1-15 | ✅ Version row links the automation snapshot compiled in the same publish (`automation_snapshot_id: 17`) |
| UT-PUB-1-01/02/03 | ✅ 10 unit tests in `versionHash.test.ts`; both pinned hashes confirmed byte-identical against the live Xano function |
| FT-PUB-1-G01 | ✅ Schema audit passes — **after it caught two real defects** (see below) |
| FT-PUB-1-G03 | ✅ Rejections logged with `E-PUB-001` / code and nothing written |
| FT-PUB-1-G04 | ✅ Success events carry version number and real duration (1794 ms, 2159 ms) |

### The dual implementation is verified, not assumed

The hash exists in two places (`versionHash.ts` and `canonical_hash.xs`). Rather than trust that they agree, both were run over the same two fixtures and compared byte for byte:

- Normal fixture → `0c62343204f24db1f11a906693f342101ee41122eaa7402f25cb3d3db9c97109` on both sides, identical canonical strings.
- Escaping fixture (a pipe, a newline and a backslash inside values) → `5c2e823ffb28c9f34090532733b3ec4c4846948d5334a238e9c53d8746d3160e` on both sides.

Both values are pinned in `versionHash.test.ts` **and** in `workflow_tests/16_publish_version.xs`. A failure in either is a breaking-change alarm, not a value to update: every version row written before such a change would stop verifying.

JSON encoding is deliberately not used for hashing — key order, whitespace and unicode escaping differ between encoders, which would have made the two sides drift silently.

### Bugs found and fixed during this epic

1. **`now` inside an object literal is not the numeric clock.** `duration_ms: (now - $started_at)` passed the parser and then failed at runtime with `"Not numeric."` on the first real publish, because inside an object literal `now` is the magic `"now"` token (as in `data = {created_at: "now"}`), not a number. Fixed by computing `now|to_int` into vars and subtracting those. Caught because the publish was tested live rather than assumed from a clean push.
2. **The schema audit caught two missing indexes in the new table** — `automation_snapshot_id` and `published_by` are foreign keys and GOV-1 standard S3 requires every FK to lead an index. Added as index-only changes (not `updateTableSchema`, which would have dropped the `content_hash` trim validator). This is the governance gate doing exactly its job on brand-new work.

### Deliberate deviations

- **The status change moved.** It used to run *before* the compile, so a failed compile left a map marked active with a stale snapshot. It now sits inside a `db.transaction` with the automation snapshot and the version row, so all three land or none do (US-PUB-1-03, GOV-1 atomicity). Verified: `db.transaction` works here, and an `as` variable assigned inside one is still readable outside it.
- **The archived check (E-PUB-005) is inside the gate**, so it only applies when `publish_gate` is on. US-PUB-1-06 requires flag-off behaviour to be identical to today, and publishing an archived map is allowed today. Turning the flag on fixes both at once.
- **Two response fields were added** (`map_version`, `gate`), null when the flag is off. Strictly this is not a byte-identical response, but extra null keys break no JSON consumer and the original four fields are untouched.
- **FT-PUB-1-04 ran against map 178's *shape*, not map 178 itself.** Publishing the founder's real map would set it active, regenerate its AI summary and fire webhooks. CLAUDE.md says to use a clone and never the original; `clone_scenario` is still broken (`Unable to locate var: cell.stage_key`), so the fixture carries the same stage/owner arrangement instead. The access-denial case was tested against 178 using the **read-only** readiness endpoint, which cannot write.

### Not done / open

- **FT-PUB-1-09 (stale detection)** — deferred by D-39, as the epic states. The groundwork is in place: identical content provably hashes identically across publishes, and `GET .../versions` returns `latest_hash`.
- **FT-PUB-1-11 (snapshot write failure), FT-PUB-1-G02 (failure injected mid-publish)** — both need Xano unit-test mocks to force a write to fail. Not built; the transaction that makes them pass *is* built and verified to exist, but "it rolls back correctly under injected failure" is asserted, not proven.
- **FT-PUB-1-13 (regression: `workflow_tests/1–9`)** — those files exist in the repo but there is no exposed tool to run a workflow test (`runUnitTest` rejects a workflow test id, and no `runWorkflowTest` exists). Same limitation that left `workflow_tests/25_observability.xs` unrun. `workflow_tests/16_publish_version.xs` is committed as the spec, and **every assertion in it was executed individually** via `runWorkspaceFunction` and passed — but the file itself has never been run by a runner.
- **The Publish button's new wiring is type-checked, not seen.** The server flow is fully verified over HTTP, but the button's `onClick → publishMapVersion` path was not exercised in a browser: the dev server was stopped by the system for low memory before that check, and restarting it needs the founder's go-ahead.
- **`publish_gate` is OFF for every account** (`account_feature_flag` had no rows; the only row added is for a throwaway QA account). Nothing about live publishing changed for the founder's account.

`npm test`: 212/212 pass (202 prior + 10 new in `versionHash.test.ts`). `npm run lint`: same pre-existing, unrelated `e2e/chat-session-crud.spec.ts` failure.
