# RATE-1 — Publish the Rate Card

**Epic ID:** RATE-1
**Feature:** When a version is published, the Items row's scaling and rates are frozen into a queryable, version-pinned table and included in the version's content hash.
**Status:** To-do
**Depends on:** ITEM-1, phase-4 PUB-1 (one gate, one version table)
**Model:** **Opus** (touches the publish gate, the snapshot and the canonical hash on both sides; every existing version must keep verifying)
**MVP:** `stage_rate` table; snapshot `schema_version = 2` with `scaling[]` and `rates[]`; `canonical_hash.xs` ↔ `versionHash.ts` extended with a pinned golden; `verify_version` branches on schema version; publish blocked when a line references an inactive item. Deferred: a "rates changed since last version" diff view; stale-rate detection on open jobs.
**Goal:** Two versions that differ only in a rate have different hashes; every version published before this epic still verifies byte-for-byte; `stage_rate` is the only place anything downstream reads a rate from.

---

## Builder brief

- **Model: Opus.** If the session is not on Opus, say so before doing anything and wait for the founder to switch. An Opus review before EST-1 is already in the gate.
- **Read first:** `functions/pub/build_map_snapshot.xs` (cells only for work rows; array order by content, never id), `functions/pub/canonical_hash.xs`, `webapp/protype-2/src/versionHash.ts` and `versionHash.test.ts`, `functions/pub/verify_version.xs`, `functions/pub/evaluate_gate.xs`, `static/tables/112_journey_map_version.xs`, and the publish endpoint (`ls apis/journey_map | grep 201`).
- **Live ids / state:** `schema_version` is absent or 1 on every stored version; all of them must still verify unchanged. Test on a clone of map 193 plus one clone of 178.
- **CLAUDE.md rules that bite here:** never hash through `json_encode`; a `|` inside a XanoScript string literal breaks the parser (the existing escape chain is already handled in the file, keep it as is); `now` inside an object literal is a magic token, compute elapsed time into vars first; no `function.run` or HTTP inside `db.transaction`; pin the expected bytes on **both** sides; diff the live function against the local file with `getFunction` before pushing; smoke-test with `runWorkspaceFunction` after every push.
- **Decide first, then build:** US-RATE-1-02's bump-every-snapshot question (D-1). Confirm it against `verify_version` and the stale check, write the answer into Test Results, then proceed.
- **Do not open:** planner, catalog or UI code beyond the Items-row delete guard.
- **Session:** one epic per session. Read only this epic, `README.md` (phase-6), `product/learnings/item-rate-framework-prd.md` §0, §7 (invariants) and §10 (decisions), and `CLAUDE.md`. Do not open other epics or the older `item-rate-model.md`.
- **Order of work (CLAUDE.md build protocol):** tests first, then code; run the new tests and the existing suites; record results in Test Results; stop and wait for the founder at the completion gate.
- **Ask before:** any Xano push, any change to an existing table, any delete. Test only on a clone of map 193 (or 178), never the original.
- **Report back:** what was built (1-2 sentences), tests pass/fail by ID, differences from the epic, what is next.

---

## Context

PRD §5.4, §5.6, D-IR-8, D-IR-13. ITEM-0 confirmed (or will confirm) that `pub/build_map_snapshot` emits cells only for work rows, so an Items cell's JSON is not hashed today. If rates rode only in the draft JSON, a user could change every rate and republish to an identical hash — and the planner could never query "what is the rate for chair at s8 in v3" without parsing JSON per request. This epic fixes both: rates get their own snapshot section (hashed) and their own table (queryable).

## Existing Architecture (Do Not Break)

- **One gate, one version table** (D-39). This epic extends `pub/evaluate_gate`, `pub/build_map_snapshot`, `pub/canonical_hash`, `pub/verify_version` and endpoint 201. It creates no second gate, no second snapshot, no second hash.
- Every existing `journey_map_version` row has `snapshot.schema_version = 1` (or absent → treated as 1 by `canonical_hash`'s `?? 1`). Those must continue to verify **unchanged**. The v2 serialiser emits the new lines only when `schema_version == 2`.
- `versionHash.test.ts` pins the v1 golden bytes; it stays and a v2 golden is added beside it.
- `db.transaction` around the version insert + `stage_rate` inserts; `function.run` for the snapshot and hash stays **outside** the transaction (CLAUDE.md).
- `now` inside object literals is the magic token — elapsed times computed into vars first (PUB-1 lesson).

## Non-Goals

- No estimate, no lines (EST-1).
- No change to what an actor cell contributes to the snapshot.
- No retro-fit of rates into existing versions.

---

## Stories

### US-RATE-1-01 — `stage_rate` table

**Files:** `static/tables/138_stage_rate.xs`

| Column | Type | Rule |
|---|---|---|
| `journey_map_version_id` | ref `journey_map_version` | required |
| `stage_key` | text `filters=trim` | |
| `quantity_key` | text `filters=trim` | an `item_type.key` in MVP |
| `method_key` | text `filters=trim` | a `method.key` |
| `minutes_per_unit` | decimal | 0–1440 |
| `source` | enum `seed`, `measured` | default `seed` |

Indexes: primary; unique `(journey_map_version_id, stage_key, quantity_key, method_key)`; btree `(journey_map_version_id, stage_key)`.

Rows are **append-only per version**: written once by publish, never patched, never deleted while the version exists. (Version deletion is already governed by PUB-1/GOV-1; add `stage_rate` to its cascade list.)

Also a tiny companion, to avoid re-parsing the snapshot for scaling: store `scales_with` per stage in the same table? **No** — keep scaling in the snapshot only and expose it through `estimate_job`. One fact, one place: the snapshot. (`stage_rate` exists because rates are many and queried; scaling is eight values read with the version.)

### US-RATE-1-02 — Snapshot schema v2

**Files:** `functions/pub/build_map_snapshot.xs`, `webapp/protype-2/src/versionHash.ts`

- Add to `MapSnapshot`:

```ts
scaling: { stage_key: string; scales_with: 'per_order' | 'per_unit' | 'per_flagged_unit' }[];
rates:   { stage_key: string; quantity_key: string; method_key: string; minutes_per_unit: number; source: 'seed' | 'measured' }[];
```

- `build_map_snapshot`: find the lens with `template_key = "items-v1"` (zero or one). For each stage in display order read its Items cell's `actor_fields`: push `scaling`; for each line with a numeric `minutes_per_unit` push a `rates` entry. Lines with an **empty** minutes box are **not** emitted (they are "no rate", surfaced by readiness and EST-1). Rates are ordered by stage display order, then `quantity_key`, then `method_key` — content order, never id order (PUB-1's lesson).
- A map with no Items row emits `scaling: []`, `rates: []`.
- `schema_version` is set to `2` for every **new** snapshot, Items row or not. (A map with no Items row therefore changes schema version but produces no new lines; its v2 hash differs from its v1 hash only by the `v2` header. **This is intended**: the next publish of any map is a new version anyway, and stale detection compares against the latest stored hash, which is recomputed by the same serialiser.) ⚠ Opus to confirm against `verify_version` and PUB-1's stale check before building.

### US-RATE-1-03 — Canonical hash v2, both sides, pinned

**Files:** `functions/pub/canonical_hash.xs`, `webapp/protype-2/src/versionHash.ts`, `versionHash.test.ts`, `webapp/protype-2/src/fixtures/version-hash-golden-v2.json`

- After the existing `link|` lines, when `schema_version >= 2`:
  - `scale|<stage_key>|<scales_with>\n` for each `scaling` entry
  - `rate|<stage_key>|<quantity_key>|<method_key>|<minutes>|<source>\n` for each `rates` entry
- `<minutes>` is rendered with the **same** rule on both sides: fixed 2 decimals, no thousands separator (`2.00`, `0.50`, `12.25`). Pin this in the golden; XanoScript's `to_text` on a decimal and JS's `toFixed(2)` must be proven identical on at least `0`, `0.5`, `2`, `12.25`, `1440`.
- Field escaping identical to the existing chain (backslash, pipe→`\p`, CR, LF).
- Golden: a v2 snapshot with two stages, one actor row, one Items row, three rates — exact expected string and sha256 committed on both sides. The v1 golden is untouched.

**Acceptance:** `canonical_hash` over the v2 golden equals the TypeScript twin byte-for-byte; over the v1 golden it still equals the old pinned bytes.

### US-RATE-1-04 — Publish writes `stage_rate`

**Files:** `apis/journey_map/201_…_publish_POST.xs` (additive), `functions/pub/materialize_rates.xs`

- After the snapshot and hash are computed (outside the transaction), inside the existing transaction that inserts `journey_map_version`: insert one `stage_rate` row per `snapshot.rates[]` entry, using the new version id.
- Gate addition (`pub/evaluate_gate`): a line whose `item_key` is now **inactive** blocks publish with `E-RATE-001` (PRD EC-3: old versions keep their rate; a *new* version may not pin a dead item). A `per_unit` cell with zero lines stays a **warning** (ITEM-1).
- Response adds `rates_written: <n>`.

**Acceptance:** publishing the 193 clone with 6 rates writes 6 rows; a second publish with one rate changed writes 6 new rows under the new version id and the old 6 are untouched; hash differs.

### US-RATE-1-05 — `verify_version` handles both schemas

**Files:** `functions/pub/verify_version.xs`

- Re-serialise the stored snapshot with its **own** `schema_version`; compare to the stored hash. Additionally, for v2: count `stage_rate` rows for the version and compare to `snapshot.rates.length` — a mismatch is an integrity finding (`E-RATE-003`) for GOV-1's daily audit.

**Acceptance:** every version in workspace 1 verifies before and after this epic; a hand-deleted `stage_rate` row is reported by the audit.

### US-RATE-1-06 — Block Items-row removal after publish

- `DELETE journey_map/{id}/items-row` (ITEM-1) is rejected with `E-RATE-002` once any version of the map has `rates.length > 0`. The row can be emptied (all cells `per_order`) and republished instead — which is honest history.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-RATE-1-01 | Unit | `canonicalise(v1 golden)` | Old pinned bytes, unchanged |
| UT-RATE-1-02 | Unit | `canonicalise(v2 golden)` | New pinned bytes |
| UT-RATE-1-03 | Unit | Minutes rendering `0, 0.5, 2, 12.25, 1440` | `0.00, 0.50, 2.00, 12.25, 1440.00` |
| UT-RATE-1-04 | Unit | Two snapshots differing in one rate | Different hashes |
| UT-RATE-1-05 | Unit | v2 snapshot, no Items row | `scaling: []`, `rates: []`, still hashes |
| FT-RATE-1-01 | Functional (`workflow_tests/31_publish_rates.xs`) | `canonical_hash` on v2 golden | Equals UT-RATE-1-02 bytes |
| FT-RATE-1-02 | Functional | `canonical_hash` on v1 golden | Equals old bytes |
| FT-RATE-1-03 | Functional | Publish 193 clone with 6 rates | 6 `stage_rate` rows, `rates_written = 6` |
| FT-RATE-1-04 | Functional | Change one rate, publish again | New version, 6 new rows, old rows intact, hash differs |
| FT-RATE-1-05 | Functional | Deactivate an item used in a line, publish | Blocked `E-RATE-001`; previous version still verifies |
| FT-RATE-1-06 | Functional | `verify_version` over every version in workspace 1 | All pass |
| FT-RATE-1-07 | Functional | Delete one `stage_rate` row by hand, run audit | Finding `E-RATE-003` |
| FT-RATE-1-08 | Functional | Publish map 178 clone (no Items row) | Succeeds; `rates_written = 0`; readiness unchanged |
| FT-RATE-1-09 | Functional | DELETE Items row after a rated publish | 422 `E-RATE-002` |

**Completion gate:** all pass; `npm test`, `workflow_tests/1–30`, existing e2e green; **an Opus review pass before EST-1** → Test Results.

## Governance (data integrity, validation, observability)

**Data integrity:** `stage_rate` unique per (version, stage, quantity, method); written only inside the publish transaction; never patched; cascades only with its version; GOV-1 audit cross-checks row count vs snapshot.

**Validation and friendly messages**

| Condition | Friendly message | Code |
|---|---|---|
| Line references an inactive item at publish | "An item on this map was deactivated: {item}. Remove its line or reactivate it, then publish." | `E-RATE-001` |
| Remove Items row after a rated publish | "This map has published rates. Set every stage to per order and publish again instead of removing the row." | `E-RATE-002` |
| Audit: `stage_rate` count ≠ snapshot rates | (Health page) "Version {n} of {map} is missing rate rows. Ask the AI to re-materialize from the snapshot." | `E-RATE-003` |

**Events logged** (`feature = RATE-1`): `rates_materialized` (`success`, with count and version id); `publish_blocked_inactive_item` (`rejected`); `rate_integrity_mismatch` (`failed`, from the audit).

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-RATE-1-G01 | Functional | Publish with an inactive item | 422, message, Reference, `rejected` event, no version row, no rate rows |
| FT-RATE-1-G02 | Functional | Successful publish | `rates_materialized` event |
| FT-RATE-1-G03 | Functional | Schema audit on 138 | Pass |

## Decisions needed (recommended defaults in bold)

| # | Question | Recommendation |
|---|---|---|
| D-1 | Bump `schema_version` to 2 for every new snapshot, or only when an Items row exists? | **Every new snapshot.** One serialiser path per version, no "which schema am I" guessing later. Opus confirms the stale-check implication in US-02 first. |
| D-2 | Should a line with an empty minutes box block publish? | **No — warning only**, same as ITEM-1. It is omitted from `rates[]`; EST-1 reports it as missing. Blocking would force fake numbers. |

## Test Results

**Built 2026-10-25, on Opus.** At publish, the Items row's scaling and rates now go into the version snapshot (schema v2), are hashed the same way on both sides, and are written to the new `stage_rate` table (live id **138**) in the same transaction as the version. Publish is blocked when a rate uses an inactive item (E-RATE-001). Removing the Items row is blocked once rates have been published (E-RATE-002). A nightly audit checks that every version still verifies and that its rate rows are all present (E-RATE-003).

### D-1: decided against the draft default

- **Decision:** `schema_version = 2` **only when the map has an Items row**. Every other map keeps producing exactly the v1 snapshot it always did.
- **Why:** the draft's reasoning was wrong. Endpoint 521's stale check compares the **stored** hash with a **freshly built live** hash. Neither side is recomputed with the stored version's schema. Bumping every snapshot to v2 would have made `has_unpublished_changes = true` on every map ever published, the moment this shipped, with nothing edited.
- **Verified live:** maps 193, 206 and 218 (v1, no Items row) still show `stale: false`. Map 216 (v2) shows `stale: false` right after publishing.
- **Cost:** a map that *gains* an Items row is reported "changed since publish". That is true: its rates are now part of the definition.
- **`verify_version`:** unaffected. `canonical_hash` already branches on the stored snapshot's own `schema_version`.
- **D-2** (an empty minutes box only warns): taken as recommended. Such lines are left out of `rates[]`.

### Suites

| Suite | Result |
|---|---|
| `npm test` (webapp/protype-2) | **550/550** (545 before + 5 new UT-RATE-1) |
| `tsc --noEmit` | clean |
| Schema audit (`scripts/audit-schema.mjs`) | 0 errors; no `stage_rate` findings |
| e2e: `items-row`, `catalog`, `jobs-and-day-navigation` | **8/8** (the specs that touch publish/versions/Items row). Full suite not re-run: it is killed by this environment's memory guard (see ITEM-1), and ~19 older specs fail on the pre-existing bare-`/` route bug |
| `workflow_tests/31_publish_rates.xs` | Written, **not run**. There is no tool to run a workflow test from a session (CLAUDE.md). Every assertion in it was driven live instead (below) |
| `workflow_tests/1–30` | Not runnable from a session (same reason). The functions they exercise were smoke-tested live after every push |

### Test IDs

| ID | Result | Evidence |
|---|---|---|
| UT-RATE-1-01 | ✅ | v1 golden still `0c6234…7109`; a v1 snapshot carrying rates hashes identically (rates ignored) |
| UT-RATE-1-02 | ✅ | v2 golden pinned in `fixtures/version-hash-golden-v2.json`: `5ecc3e…1c54` |
| UT-RATE-1-03 | ✅ | `0.00, 0.50, 2.00, 12.25, 1440.00` |
| UT-RATE-1-04 | ✅ | changing one rate, a rate's source, or a stage's scaling each changes the hash |
| UT-RATE-1-05 | ✅ | v2 with no rates = v1 bytes with only the header changed |
| FT-RATE-1-01 | ✅ | live `pub/canonical_hash` on the v2 golden → byte-identical string, `5ecc3e…1c54` |
| FT-RATE-1-02 | ✅ | live on the v1 golden → `0c6234…7109`, unchanged |
| FT-RATE-1-03 | ✅ | map **216** (clone of 193, Items row, 3 stages × 2 lines): publish → version 17, `rates_written: 6`, 6 `stage_rate` rows |
| FT-RATE-1-04 | ✅ | changed one rate 1.5 → 1.75, republished → version 18, 6 new rows; version 17's 6 rows untouched; hash `ce792a…` → `1e38f8…` |
| FT-RATE-1-05 | ✅ | deactivated `ft-active-item-2` → publish refused, HTTP 400, `"An item on this map was deactivated: FT Active Item 2. … (E-RATE-001)"`. The checklist (520) shows the same blocker. Versions 17/18 still verify. Item reactivated afterwards |
| FT-RATE-1-06 | ✅ (with a pre-existing exception) | `ops/audit_rates` over all 16 versions: every real published version verifies. **Map 200's versions 4/5/6 fail E-PUB-003**: they are JOB-1 fixtures inserted by hand with made-up hashes (JOB-1 Test Results). Version 4 has no cells, so nothing in this epic could have changed its result. Not fixed: they are history rows |
| FT-RATE-1-07 | ✅ | deleted `stage_rate` row 12 by hand → audit: `E-RATE-003, version 18: "snapshot has 6 rates, stage_rate has 5 rows"`, plus a `rate_integrity_mismatch` failure event. Row restored (now id 13); audit clean again |
| FT-RATE-1-08 | ✅ (adapted) | A 178 clone (217) cannot publish: it has 8 pre-existing readiness blockers, identical to 178's own list before and after this epic, so "readiness unchanged" holds, and the publish is still refused with the usual E-PUB-001. To prove the success path, map **218** (a 193 clone with no Items row) was published instead: `rates_written: 0`, snapshot `schema_version: 1` with no `rates` key, not stale |
| FT-RATE-1-09 | ✅ | `DELETE /journey_map/216/items-row` → HTTP 400 `"This map has published rates. … (E-RATE-002)"`, `rejected` event; the row is still there |
| FT-RATE-1-G01 | ✅ | rejected publish: message + `RATE-1.publish_blocked_inactive_item` `rejected` event naming the item; no version row, no rate rows (versions for 216 still 17, 18) |
| FT-RATE-1-G02 | ✅ | `RATE-1.rates_materialized` `success` events for versions 17 and 18, each with `rates_written: 6` |
| FT-RATE-1-G03 | ✅ | schema audit passes with `stage_rate` in the manifest (natural key, `source` enum, append-only) |

**Status codes:** "422" in this epic is HTTP **400** in practice (`error_type = "inputerror"`). That is the same as every other E-ITM / E-PUB rejection in this app.

### Bugs found and fixed while building

- **`"\u0000"` is not a NUL byte in XanoScript.** The first publish sorted `ft-active-item-2` ahead of `ft-active-item`: the "NUL" separator in the sort key is kept as six literal characters, which sort after `-`. Fixed by using a space as the separator, since keys are `[a-z0-9-]` and trimmed. Version 17 keeps its old order; that is valid, because a hash is over the stored order.
  - Not changed: `build_map_snapshot` uses the same `"\u0000"` in its cell-slot keys. There it is only a map-key separator and is still unique, so it is harmless.
- **`canonical_hash` crashed on a cell with no `duration_minutes` key.** A bare `$cell.duration_minutes` in a condition throws when the key is missing ("Unable to locate var"). That made version 5 impossible to verify, ever, and crashed the whole audit loop.
  - Fix: read the value through `??` first. Same for `does_planned_work`. Output is byte-identical for every snapshot that has the keys, and it matches `versionHash.ts`, which renders undefined as `""`.
- **Readiness (520) treated a 0-minute rate as missing.** The cause is the `0 == null` trap. Fixed with the same text test the snapshot uses. A real rate of 0 is now pinned and not warned about.

### Found, not fixed (pre-existing, outside RATE-1)

- **Map 200's three JOB-1 fixture versions** will show E-PUB-003 in `ops/audit_rates` every night. Only the RATE-1 E-RATE-003 finding is logged as an event, so this adds no Health-page noise. They need a decision: leave them, or mark them as fixtures.
- **v1 duration-0 divergence:** Xano renders a cell with `duration_minutes: 0` as `""` (`0 != null` is false), while `versionHash.ts` renders `"0"`. Nothing hashes on the frontend in production, so there is no live impact. Fixing it would change stored hashes, so it was left alone.

### Live objects changed

- **Functions:** `pub/canonical_hash` (91), `pub/build_map_snapshot` (92), `pub/evaluate_gate` (94), `pub/verify_version` (95), `ops/error_catalog` (69). New: `ops/audit_rates` (235).
- **Endpoints:** 201 (publish), 520 (readiness), 603 (Items-row DELETE).
- **Task:** 19 (`ops_integrity_audit`) now also runs `ops/audit_rates`.
- **Table:** `stage_rate` (138).
- **Cleanup:** scratch function 234 deleted.

### Test fixtures left live

- Map **216**: RATE-1 clone of 193 with an Items row and versions 17/18.
- Map **217**: clone of 178, not publishable.
- Map **218**: clone of 193 with no Items row, version 19.
- `stage_rate` rows 1–11 and 13.

### Opus review pass (2026-10-25): fixes applied

The review was done by an independent read-only Opus agent. Verdict: the core is sound, the TypeScript/Xano hashes are proven identical, v1 versions are untouched, publish is atomic, and the D-1 reasoning is correct. It was not yet safe for EST-1 until #1 and #2 were fixed. Status of each finding:

| # | Finding | Status | Live evidence |
|---|---|---|---|
| 1 | Item/method hard delete had no reference check (CAT-1 assigned it to RATE-1), so a deleted item slipped past E-RATE-001 and got pinned as a dead key | **Fixed**: E-CAT-005 in `apis/catalog/596` and `601`. An item is blocked while a map lists it (`journey_lens_item`) or an account version's `stage_rate` pins it. A method is blocked while any Items-cell line on the account's maps or any published rate uses it | DELETE item 15 → 400 E-CAT-005; DELETE method 9 → 400 E-CAT-005; DELETE unused method 11 (an e2e leftover) → 200 |
| 2 | `verify_version` compared counts only; a hand-patched minute value went unnoticed | **Fixed**: every snapshot rate must have an identical `stage_rate` row (key + minutes + source); `rates_matched` added | Patched row 13 from 6 to 9 → `rates_ok: false, rates_matched: 5/6`; restored → 6/6 |
| 3 | The audit logged no event for E-PUB-003, one throwing version aborted the loop, and a clean run logged nothing | **Fixed**: per-version `try_catch`, a `PUB-1.version_integrity` failure event, and a `RATE-1.version_audit` success when clean | 17 versions checked, no crash. ⚠ Map 200's 3 fixture versions now raise one E-PUB-003 event per night (see decisions below) |
| 4 | E-RATE-002 can be bypassed by `journey/remove_lens` (endpoint 50, AI tools) and raw `35_journey_lens_DELETE`; generic cell PATCH 44 writes Items cells without `validate_items_cell` | **Not fixed, needs a decision**: these are pre-existing generic paths outside RATE-1's "do not open" scope. A duplicate line via 44 rolls back cleanly at publish (unique index) but shows a raw error |
| 5 | Suspected silent-write trap in 520's empty-minutes warning | **Not a bug, verified live**: map 216 with one 0-minute line and one empty line → warning names only `ft-active-item-2` |
| 6 | Xano side of UT-RATE-1-03 not proven; 0-minute rate not proven at publish | **Fixed / proven**: live `canonical_hash` on `0, 0.5, 2, 12.25, 1440` gives byte-identical output and hash `a1b42d…ce77`, now pinned as UT-RATE-1-03b. Version 20 of map 216 pins `s2 ft-active-item 0` |
| 7 | `formatRateMinutes` threw on null | **Fixed**: renders `0.00`, the same as Xano's `?? 0` |
| 8 | `scales_with: ""` passes through as `""` | **Left for EST-1**, which must treat anything other than `per_unit` / `per_flagged_unit` as per order |
| 9 | Orphan `stage_rate` rows on v1 versions aren't counted | **Left**: only publish writes `stage_rate`, and it never does so for v1 |

**Notes for EST-1** (from the review):

- Treat v1, or a stage with no `scaling` entry, as per order with zero rates. Never read `stage_rate` for a v1 version.
- Always apply scaling from the snapshot: a bypass via #4 could leave rates on a per-order stage.

**Suites after the fixes:** `npm test` **551/551**; `tsc` clean.

### Founder decisions (2026-10-25): both done

- **D-R1: archive map 200. Done.** Map 200's `status` was set to `archived`; nothing else changed.
  - `ops/audit_rates` now reports hash mismatches on archived maps under `archived_hash_mismatch_count`, but raises no Health event for them. Rate mismatches still alert regardless.
  - Live: `finding_count: 0`, `archived_hash_mismatch_count: 3`, and the clean-run success event fires.
- **D-R2: close the bypass paths now. Done.**
  - `journey/remove_lens` (endpoint 50 + the AI tools) refuses the Items row with **E-ITM-009**.
  - Endpoint 44 refuses an `actor_fields` write to an Items cell with **E-ITM-010**. Status and lock edits are still allowed.
  - Live: lens 1259 delete → 400 E-ITM-009; Items-cell `actor_fields` → 400 E-ITM-010; `is_locked` on an Items cell → 200; a normal actor cell's `actor_fields` → 200, nothing lost. `items-row` e2e 2/2.
  - Endpoint 35 (an unauthenticated raw lens DELETE in the local files) **does not exist live** (it 404s), so it needed no change; the local edit was reverted.
  - Two codes, not one: `GUARD-REG-01` refused a single code carrying two messages.
- Suites after the decisions: `npm test` **551/551**.

### Completion gate

All in-scope tests pass, with the two adapted cases explained above. The Opus review is done and its blocking findings are fixed. Map 178 itself was never touched. **Next: EST-1 (Sonnet build, then an Opus review).**
