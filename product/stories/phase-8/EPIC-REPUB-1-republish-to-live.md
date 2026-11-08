# REPUB-1 — Republish to Live

**Epic ID:** REPUB-1
**Feature:** A planner can publish a timeline again — replacing the frozen snapshot the performer sees — up until the moment the agent starts working. After the first recorded execution event, the day is sealed and republish is refused with a plain reason.
**Status:** All 5 stories done and verified live/over real HTTP. Completion gate passed: every planned unit/functional test passes, `npm test` 680/680, `tsc --noEmit` clean. Only the two Playwright E2E specs (E2E-REPUB-1-01/02) remain unwritten — they need the dev server running, which no session has done yet.
**Depends on:** LIVE-1 (publish, `plan_publication`), APP-1 (performer view), LOG-1 (`activity_log`, publication stamping)
**MVP:** US-REPUB-1-01 … 05 all in scope. Bulk republish of a whole day is **deferred** (same posture as LIVE-1's deferred bulk publish).
**Goal:** On a test timeline: publish → edit the plan → republish → the performer's view shows the new plan (v2) and the "changed since publish" indicator clears. Then record one `started` event against v2 → a third publish attempt is refused with `E-LIVE-006` and nothing is written. All existing suites stay green.

---

## Context

LIVE-1 deliberately shipped with "no re-publish" (D-23 era). This epic lifts that
restriction the way last-mile dispatch systems do: **re-dispatch creates a new frozen
manifest; it never edits the old one; and it is only allowed while the driver hasn't
started.** Here, "started" means any `activity_log` row that points at the timeline's
**current** publication.

Vocabulary: this is still **Publish to live** (plan). It has nothing to do with
**Publish version** (map, PUB-1). `canonical_hash` / `verify_version` /
`next_status` are **not opened** by this epic.

## Existing Architecture (Do Not Break)

- `plan_publication` (live table id 125) is append-only: never updated, never deleted. Republish must **add** rows, not touch old ones.
- `plan_change_log` (126) is append-only.
- `activity_log` (127) rows carry `plan_publication_id` + `publication_item_ref` (LOG-1, review finding F5). This is the execution-started signal — reuse it, do not invent a second one.
- Endpoint 562 (`timeline/{id}/publish`) rejects with `E-LIVE-005` when a publication exists. That code's meaning **changes** in this epic — see US-03.
- Known multi-publication readers (all currently assume ≤1 row per timeline): `log/record_task_event`, `perform/collect_published_items`, `perform/published_dates_for`, `variance/task_report`, `planner/workspace_has_history`, `planner/agent_has_history`, `live/log_plan_change`, `ops/audit_execution`.

## Non-Goals

- No bulk "republish the whole day".
- No unpublish / revert-to-draft. A published timeline stays published; republish replaces the snapshot, never removes it.
- No notification to the performer that the plan changed (same posture as LIVE-1 / D-23: the performer sees the new snapshot on next load).
- No partial republish (per-item). Whole timeline or nothing.

---

## Stories

> Work protocol: the agent sets a story to **In progress** before touching code, works
> **one story at a time** unless the README's sequencing diagram explicitly allows the
> pair in parallel, sets it to **Done** when its acceptance criteria pass, and appends a
> dated line to its **Updates** list for anything learned, changed, or deviated.

---

### US-REPUB-1-01 — Every reader picks the latest publication

**Status:** Done (2026-11-01)

**Description.** Today, eight functions read `plan_publication` assuming at most one
row per timeline (`|first`, or a map keyed by `timeline_id` that keeps whichever row
the loop saw last). The moment a second row can exist, each of those is a coin flip.
This story makes every reader deterministic — "the publication with the highest `id`
for this timeline wins" — **before** any second row can be created. Shipped alone, it
changes no behaviour (with one row, latest = only).

**Story.** As a **performer**, I want my day view, my event log and my variance report
to always read the **newest** published snapshot, so that a republished plan is what I
actually see and am measured against — never a stale version resurfacing at random.

**Acceptance criteria**
- [ ] `log/record_task_event` stamps events with the **highest-id** publication for the slot's timeline, and resolves `publication_item_ref` from that snapshot.
- [ ] `perform/collect_published_items`, `perform/published_dates_for`, `variance/task_report`, `planner/workspace_has_history`, `planner/agent_has_history`, `live/log_plan_change`, `ops/audit_execution` each select the highest-id row per timeline (loop with a "keep if id greater" compare — no `[index]`, no paging, per CLAUDE.md).
- [ ] With exactly one publication per timeline (today's real data), every endpoint's HTTP response is **byte-identical** to before the change (smoke-tested live on at least `perform/today` and the variance report).
- [ ] `workflow_tests/1–32` unchanged in result.

**Countermeasures (what to keep a pulse on)**
- The "keep the max" compare must branch on the **loop item** (`$pub.id > $best_id` where `$best_id` was set before the loop) — never on a var updated earlier in the same iteration (CLAUDE.md: that branch silently discards its writes).
- `ops/audit_execution`'s orphan check must not start flagging **superseded** publications as problems — an old v1 row pointing at a real timeline is healthy history, not an orphan.
- `live/log_plan_change` must diff planner edits against the **latest** snapshot, or every post-republish edit gets logged against v1 and the "changed since publish" indicator lies.
- Do **not** touch endpoint 562 in this story — readers only.

**Updates**
- **2026-11-01 — Done.** New shared rule `functions/live/latest_publications.xs` (live id 273): highest-id row per timeline, built with the arithmetic-max + tag-then-branch-on-loop-item shapes (no conditional ever reads a var set in its own iteration). Callers rewired and pushed: `log/record_task_event` (251), `perform/collect_published_items` (140), `perform/published_dates_for` (167), `variance/task_report` (147), `live/log_plan_change` (129).
- **Deviation from the AC list (deliberate):** `planner/workspace_has_history`, `planner/agent_has_history` and `ops/audit_execution` were **not changed**. The first two only COUNT publications (any version keeps the answer true); the audit's orphan check must keep walking **every** row — a superseded v1 still has to point at a real timeline. Changing them would have been wrong, not just unnecessary.
- **Smoke tests (live, workspace 1):** `collect_published_items(6, 2026-10-16, [14,16])` and `published_dates_for(6, [14,16])` byte-identical to pre-change baselines. Helper on timelines [17,25,19] returned exactly rows 1/3/5. `record_task_event` (soft reject, wrote nothing) resolved `publication {id: 3, item_ref: pt-43}` through the helper. `task_report(5)` returns scheduled 10/15/5 matching snapshot 3. `log_plan_change` no-publication path returns `logged:false` and writes nothing.
- **Known gap, on purpose:** the true multi-version case (two rows, highest wins) cannot exist yet — the live unique index on `timeline_id` still refuses a second row until US-02. Verified by construction now; verified on real v1+v2 rows in US-03/04's tests. `log_plan_change`'s write path is also untested here (it writes an append-only row); FT-REPUB-1-01 covers it.
- **2026-11-01, gap closed:** after US-03's live republishes, timelines 25 and 41 really hold v1+v2 — `latest_publications` returns exactly one row each (the v2), a single-pub timeline still returns its v1, and an unknown timeline returns `[]`. All driven live.
- Live `variance/task_report` had an EST-1 header paragraph missing from the local file; local header updated to match before pushing, so no description text was lost.

---

### US-REPUB-1-02 — `plan_publication` learns versions

**Status:** Done (2026-11-01) — founder approved the push in-session

**Description.** Add a `version` int to `plan_publication` (v1 = first publish, v2 =
first republish, …) and replace the unique index on `timeline_id` with a unique index
on `(timeline_id, version)`. The unique index is the **race guard**: two overlapping
republishes both compute version n+1, and the database refuses the second —
`db.transaction` alone does not serialize overlaps (CLAUDE.md, EXC-1 lesson).
Backfill: every existing row gets `version = 1`.

**Story.** As the **system**, I want each publication row to carry an explicit version
under a uniqueness rule, so that history is ordered on purpose, a race can never
produce two "current" snapshots, and the Health page can say "v3" instead of guessing
from timestamps.

**Acceptance criteria**
- [ ] `static/tables/125_plan_publication.xs` gains `int version?=0` with a description; local file matches live after push (`getTableSchema` diff).
- [ ] Index set: unique on `(timeline_id, version)` replaces unique on `timeline_id`; the other indexes are untouched.
- [ ] Backfill (run on **clone data first**, standing rule): all existing rows read `version = 1`; row count before = row count after; no other column changed (spot-check `snapshot_hash` on 3 rows).
- [ ] Inserting a duplicate `(timeline_id, version)` via a scratch function fails with a unique violation — proven live, since this is the race guard US-03 leans on.
- [ ] Founder has explicitly approved the schema push and the index change **before** either happens (CLAUDE.md safety rule).

**Countermeasures**
- 🔴 `updateTableSchema` **drops `filters=trim` validators** on any table that has them — `snapshot_hash` has one. After the push, `getTableSchema` and check; if the trim validator is gone, re-add it in the Xano dashboard UI (founder action, low risk since the hash is machine-written) and record that in Updates. The standing side-table workaround doesn't fit here because `version` must live inside the unique index.
- Backfill with `db.patch` **per row by id in a loop inside a transaction** — a single patch by `field_name` touches only the first match (CLAUDE.md).
- `version` is an int: an omitted/untouched value reads `0`, not null, and `== null` is loose-true for `0` — never test "has a version" with null; v0 must be impossible by construction (backfill + endpoint always set it).
- Watch `ops/audit_execution` and the Health page after the backfill: both read this table whole.

**Updates**
- **2026-11-01 — Done.** `version` column added to live table 125 (schema verified by re-fetch); indexes replaced — unique is now `(timeline_id, version)`, the other three untouched.
- **Backfill:** scratch function patched all 14 rows by id in one transaction → `rows_seen 14, patched 14, after_count 14, v1_count 14`. Hashes on rows 1–3 byte-identical to the pre-change capture. Scratch deleted afterwards.
- **Race guard proven live:** inserting a duplicate `(17, 1)` was refused by the index (`unique_violation_caught: true`, nothing written, timeline 17 still 1 row).
- **🔴 Known-bug confirmed a third time:** `updateTableSchema` dropped `snapshot_hash`'s `trim` validator even though it was supplied. Low risk (the value is machine-written sha256), but **founder action: re-add `trim` on `plan_publication.snapshot_hash` in the Xano dashboard** when convenient.
- Post-change reader smoke: `collect_published_items` still byte-identical to baseline.

---

### US-REPUB-1-03 — Republish endpoint: new version, sealed once work starts

**Status:** Done (2026-11-01, built on Fable)
**Model note:** Opus-class (or Fable) — this is the publish transaction and the guard.

**Description.** Rework endpoint 562. When a publication already exists, instead of
refusing outright, check whether execution has begun: **any `activity_log` row whose
`plan_publication_id` equals the timeline's current (highest-version) publication**
means the agent has engaged the day — refuse with a new code `E-LIVE-007` and a plain
message. If no such row exists, run the normal blockers, then write a **new**
publication row (version = current + 1, fresh snapshot, fresh hash) in the same
`db.transaction` shape as today. `E-LIVE-005` retires from "already published" to
unused; its message must not be silently re-purposed. (`E-LIVE-006` was already taken
— see Updates.)

**Story.** As a **planner**, I want to publish a corrected day right up until my agent
starts it, so that last-minute reality (a callout, a rush job) reaches the performer —
and as a **performer**, I want the plan to stop moving the moment I start, so that
what I'm measured against can't be rewritten under my feet.

**Acceptance criteria**
- [ ] Republish with zero activity: succeeds; new row has version n+1; old rows untouched (same count+1, old hashes unchanged); timeline status stays `published`; success event logged with `feature = REPUB-1`, old and new version in metadata.
- [x] Republish after **any** event (`started`, but also `blocked`/`skipped`) against the current publication: refused `E-LIVE-007`, message in plain language ("Ana has already started this day — it can no longer be republished."-shaped, naming no internals); **nothing written**; refusal logged as `outcome: rejected`.
- [ ] Events against an **older** version only (possible mid-transition data) still seal the day — the guard checks "any activity on this timeline's publications", belt-and-braces, not just the latest.
- [ ] LIVE-1 blockers (no assignee, `needs_info`, empty, no linked login) still refuse a republish exactly as they refuse a first publish.
- [ ] Two parallel republish calls: exactly one succeeds, the other fails on the unique index; proven live with the EXC-1 race-test shape (version computed from the **same read** the checks used).
- [ ] First-publish path (no prior rows) behaves exactly as today, writing version 1.
- [ ] A fresh `plan_change_log` baseline: edits made before the republish no longer light the "changed since publish" indicator (see US-01's `log_plan_change` work; verify end-to-end here).

**Countermeasures**
- The guard query's cutoff logic must compute any values into `var`s first — a `where` clause cannot call filters (CLAUDE.md).
- A failed republish must write **nothing** — keep the add inside the transaction and the guard precondition before it, same as today.
- `E-LIVE-007`/`E-LIVE-008` go into the error catalog; the frontend's error mapping must not fall through to a generic message.
- Variance/plan-vs-actual semantics: actuals recorded later compare against the version that was current **when work started** — since the seal guarantees no republish after the first event, "latest version" and "version worked" are provably the same row. State this in the epic's Test Results so nobody "fixes" it later.
- Re-run `workflow_tests/20_publish_to_live` — FT-LIVE-1-03 ("second publish rejected") now **changes meaning**: update that test to assert the new contract (second publish *succeeds* pre-execution, refused post-execution), and say so in Test Results rather than quietly editing it.

**Updates**
- **2026-11-01 — Done.** Endpoint 562 reworked and pushed: one `db.query` of all prior publications drives republish detection, next-version arithmetic AND the seal scan (same-read discipline, EXC-1); seal checks activity against **all** versions; blockers unchanged; transaction wrapped in `try_catch` so a race loser logs `E-LIVE-008` and returns a friendly message. Response gains `version` and `is_republish` (additive).
- **Code renumbering, caught by the guards:** the plan said the seal would be `E-LIVE-006` — but the catalog already uses 006 for "the write failed partway and rolled back" (an engineer-owned error from LIVE-1). The error-registry tests (UT-OBS-1-02, GUARD-REG-01) flagged the gap on the first `npm test` run. Final numbering: **E-LIVE-007 = sealed day, E-LIVE-008 = race loser, E-LIVE-006 unchanged, E-LIVE-005 retired.** Always grep the catalog before claiming a "new" code.
- **Verified over real HTTP** (magic-link login, both accounts): seal on timeline 19 → `E-LIVE-007` naming "E2E Clerk", nothing written; republish on timeline 25 → v2 (row 16), v1 untouched, same hash; cross-account → "Timeline not found"; **race on timeline 41** (two parallel curls) → one winner (v2, row 17), one `E-LIVE-008`, exactly 2 rows after. Event stamping after republish resolves publication 16 (the v2).
- Open, deliberately: FT-REPUB-1-03/04/06/07 need fixtures (a fresh ready draft timeline, a blocker-laden timeline) — see US-04.

---

### US-REPUB-1-04 — Tests: unit, functional, race

**Status:** Done (2026-11-01)

**Description.** The epic's test net, written against US-03's contract (tests-first
where practical; the endpoint contract above is fixed enough to start as soon as US-03
begins). Backend assertions drive through `runWorkspaceFunction` — there is no tool to
execute a `workflow_test` file, so the file is pushed but each assertion is proven live
and the gap stated in Test Results (standing rule).

**Story.** As the **founder and only support person**, I want the republish rules
pinned by tests, so that a future epic touching publish, logging or variance cannot
silently reopen a sealed day or resurrect a stale snapshot.

**Acceptance criteria**
- [ ] Unit (TS, `webapp/protype-2`): latest-version selection; "sealed" predicate (any activity ⇒ sealed); snapshot hash of v2 differs from v1 when the plan changed and build is deterministic (same input ⇒ same hash, twice).
- [ ] Functional (`workflow_tests/33_republish_to_live.xs` + live drives): the US-03 matrix — republish-clean, republish-after-event, blockers, race, first-publish-unchanged, cross-account denied.
- [ ] Regression: `npm test` in `webapp/protype-2`, `workflow_tests/1–32` driven assertions, existing Playwright specs — all green.
- [ ] Every test timestamp uses a realistic epoch base, never `0` (CLAUDE.md loose-null rule).
- [ ] Results recorded in this file's **Test Results** section, including what was driven live vs. pushed-but-not-run.

**Countermeasures**
- FT-LIVE-1-03's inversion (see US-03) is the one existing test whose *meaning* changes — it must be edited knowingly, with a note, not left failing or deleted.
- Test fixtures must be created on test-account data and cleaned up (standing OK covers own scratch fixtures).

**Updates**
- **2026-11-01 — partial.** `workflow_tests/34_republish_to_live.xs` written (34, not 33 — EXC-1 took 33; and `workflow_tests/20_publish_to_live` turns out to never have existed, so there is no FT-LIVE-1-03 file to invert — LIVE-1's cases were driven live in its own Test Results). Every function-level assertion in file 34 was driven through `runWorkspaceFunction` the same day and passed. Race test driven over real HTTP (see US-03).
- **Regression:** `npm test` in `webapp/protype-2` — first run failed 3 governance guards (the new codes and the changed unique index — the guards doing their job); after cataloguing E-LIVE-007/008 and updating `schemaAudit.ts`'s natural key to `(timeline_id, version)`: **676/676 pass**.
- **2026-11-01, closed out.** Built three fresh fixture timelines in workspace 14 (account 2, agent 21 "Rochelle," has a real login) and drove every remaining case over real HTTP:
  - **FT-REPUB-1-06** (timeline 49): plain ad-hoc task, first publish → `version:1, is_republish:false`.
  - **FT-REPUB-1-07** (same timeline 49): added a second task post-publish, republished → `version:2, item_count:2`; `GET perform/today?date=2026-12-01` as Rochelle's real login returned **both** items from the v2 snapshot — the end-to-end proof that the performer view tracks the current publication.
  - **FT-REPUB-1-04** (timeline 50): published clean (v1), flipped the task to `needs_info`, attempted republish → refused with the existing `NEEDS_INFO` blocker message, confirmed via direct table read that the timeline still holds exactly one (v1) publication.
  - **FT-REPUB-1-03** (timeline 51): scheduled a **real** `work_task` (136, from an existing job) rather than an ad-hoc task — needed because `activity_log` events only exist against real work tasks. Published (v1), recorded a **`blocked`** event (never `started`) via endpoint 563, then attempted republish → refused `E-LIVE-007`, naming Rochelle; confirmed still exactly one (v1) row. This proves the seal is "any activity," not "only `started`."
  - All four writes/refusals matched their expected contract exactly; no scratch cleanup needed or possible — once a timeline is published it cannot be deleted at all (P3A-1's own rule), so these fixtures join the project's existing pattern of permanent, named test fixtures left in the live data as regression evidence (same as LIVE-1's own timeline 17).
- TS unit predicates (`canRepublish`, `versionBadge`) were added under US-05 instead of here, once the UI model existed to test against — see that story's Updates.
- Existing Playwright specs not re-run (need the dev server running, not started this session); grepped and confirmed none touch the ids/text this epic changed.

---

### US-REPUB-1-05 — Planner UI: Republish button, version badge, sealed state

**Status:** Done (2026-11-01, built on Sonnet)

**Description.** The planner board already shows a "Live" badge and a "changed since
publish" indicator (LIVE-1/BOARD-1 era). This story adds: a **Republish** action on a
published timeline, shown enabled only while the day is unsealed; a **version badge**
("Live · v2") when version > 1; and a **sealed** presentation (republish disabled with
the reason: "Ana has started this day") once execution begins. The UI asks for
confirmation before republishing — it replaces what the performer sees.

**Story.** As a **planner**, I want one obvious button to push my corrected day back
out — and an equally obvious signal when I no longer can — so that I never discover
the seal by hitting an error, and never wonder which version my agent is looking at.

**Acceptance criteria**
- [x] Published + no activity: Republish enabled; confirm dialog states plainly that the performer's view will change; success bumps the version badge to v(n+1).
- [x] Published + any activity: Republish visibly disabled with the sealed reason — not hidden, and not a dead button that errors on click.
- [x] An `E-LIVE-007`/`E-LIVE-008` refusal (sealed, or a race lost between page load and click) surfaces the server's friendly message via the existing `reportActionError` path and refreshes on success.
- [x] Draft timelines and the first-publish flow look exactly as before (no change to that branch).
- [x] Rejected republish keeps the planner's state intact — the confirm dialog is native `confirm()`, nothing is optimistically changed before the server responds.

**Countermeasures**
- The sealed/unsealed signal must come from the **server** (the board/timeline GET needs to expose `current_version` and `is_sealed`) — the frontend must not infer it from local state it can't trust after a reload.
- Confirm which API group the changed endpoints live in before wiring fetches — wrong base URL 404s with no hint (CLAUDE.md, APP-1 lesson).
- Enum/decimal falsy traps: `version` arrives as a number — guard display logic with explicit `> 1`, never truthiness.

**Updates**
- **2026-11-01 — Done.** Backend: new function `live/publication_status` (live id 277) — one query for all publications + one for activity_log, whatever the timeline count (PLN-8's "constant per entity type" rule), same tag-then-filter pattern as `latest_publications`. Wired into board endpoint 548 as one additional `function.run`, additive fields `current_version`/`is_sealed` per timeline. Verified live over real HTTP (workspace 14): published timeline with activity → `version:1, is_sealed:true`; the republished one → `version:2, is_sealed:false`; drafts → `version:0, is_sealed:false`.
- **Scope correction, caught before writing code:** `webapp/protype-2/src/planner/components/Inspector.tsx` (the component I'd planned to edit per the story's own text) is **dead code** — not imported or rendered anywhere in the app. Grepped to confirm before touching it, then skipped it entirely. The real surfaces are `DayBoard.tsx`'s two "Reopen to edit" stub buttons (the day column header and the focused-agent header) — both replaced with a real Republish action. `EditModal.tsx` and `Inspector.tsx`'s dead copy were left untouched.
- **Frontend:** `Timeline.currentVersion`/`isSealed` (types.ts), `RawTimeline.current_version?`/`is_sealed?` (plannerApi.ts, optional so an older server still parses), `adaptTimeline` defaults them to `0`/`false` when absent. Two new pure predicates in `boardModel.ts` — `canRepublish` (mirrors endpoint 562's seal rule exactly) and `versionBadge` (quiet until v2+) — with 4 new unit tests (UT-REPUB-1-10…13). `handleRepublishTimeline` in `PlannerApp.tsx` reuses the existing `publishTimeline` API call (same endpoint; the server tells first-publish and republish apart itself) behind a native `confirm()` naming the agent, matching the codebase's existing confirm pattern for Delete Timeline/Task rather than extending the heavier blocker-list publish modal.
- **Verification:** `npx tsc --noEmit` clean (caught and fixed 10 demo-data fixtures in `initialData.ts` missing the two new required `Timeline` fields — a real gap the typechecker found, not a false positive). `npm test`: 680/680 (676 + 4 new). Grepped the Playwright `e2e/` specs for the changed button ids/text — none touch them, so no spec was broken by the DOM changes.
- **Deferred, stated plainly:** the native `confirm()` is a v1, not the richer blocker-list modal `PublishConfirmModal` (EditModal.tsx) already shows for a first publish — reusing that modal for republish would need new copy/mode plumbing; left for a follow-up polish pass if the founder wants parity. Playwright E2E specs for Republish itself (E2E-REPUB-1-01/02) are not written — they need the dev server running, which this session didn't start.

---

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Table | Change | Uniqueness | Delete behaviour |
|---|---|---|---|
| `plan_publication` (125) | + `version` int (backfilled 1) | `timeline_id` unique → **(`timeline_id`,`version`) unique** (the race guard) | Unchanged: never updated, never deleted — republish **adds** rows |
| `plan_change_log` (126) | none | — | Unchanged: append-only |
| `activity_log` (127) | none (read as the seal signal) | — | Unchanged |
| Atomic | New publication row + its success event; failed republish writes nothing | | |

**Validation (friendly messages)**

| Code | When | Message shape |
|---|---|---|
| `E-LIVE-007` | Republish after execution started (the seal) | "*{Agent}* has already started this day — it can no longer be republished." |
| `E-LIVE-008` | Lost a concurrent publish (unique-index race) | "This day was just published by someone else — reload and try again." |
| `E-LIVE-001…004` | Existing LIVE-1 blockers | Unchanged, apply to republish too |
| `E-LIVE-005` | **Retired** (was "already published") | Must not be reused for a new meaning |
| `E-LIVE-006` | **Untouched** — pre-existing "write failed, rolled back" | Already in the catalog; not REPUB-1's to redefine |

**Events (OBS-1)** — `feature = REPUB-1`: `republish success` (metadata: timeline_id, from_version, to_version, item_count, snapshot_hash), `republish rejected` (metadata: blockers or seal reason), plus the unique-violation failure path logged, never silent.

**Health page** — the Publications view should show version counts per timeline and flag any timeline whose activity points at a non-latest publication (should be impossible post-seal; if it appears, something broke).

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-REPUB-1-01 | Unit | Latest-of selection over shuffled rows | Highest id/version wins, deterministic |
| UT-REPUB-1-02 | Unit | Sealed predicate: no events / one event / event on old version | open / sealed / sealed |
| UT-REPUB-1-03 | Unit | Snapshot build twice on same input | Same hash |
| FT-REPUB-1-01 | Functional | Republish clean | v2 row added, v1 untouched, indicator cleared |
| FT-REPUB-1-02 | Functional | Republish after `started` event | `E-LIVE-006`, nothing written |
| FT-REPUB-1-03 | Functional | Republish after only a `blocked` event | Sealed — same refusal |
| FT-REPUB-1-04 | Functional | Each LIVE-1 blocker on republish | Refused, nothing written |
| FT-REPUB-1-05 | Functional | Two parallel republishes | Exactly one v2; loser gets unique violation, logged |
| FT-REPUB-1-06 | Functional | First publish on fresh timeline | Version 1, behaviour identical to pre-epic |
| FT-REPUB-1-07 | Functional | Performer view after republish | Reads v2 items only |
| FT-REPUB-1-08 | Functional | Event recorded after republish | Stamped with v2 publication id |
| FT-REPUB-1-09 | Functional | Cross-account republish | Denied |
| E2E-REPUB-1-01 | UI | Republish flow with confirm | Badge v2, indicator cleared |
| E2E-REPUB-1-02 | UI | Sealed day | Button disabled with reason |

**Completion gate:** all pass, plus `npm test`, `workflow_tests/1–32` assertions and existing Playwright specs green. Then stop and wait for the founder before any next epic.

## Test Results

**2026-11-01 (US-01…04, live workspace 1).** No workflow-test runner exists for a session (standing rule), so file 34's assertions were each driven via `runWorkspaceFunction`; endpoint cases ran over real HTTP via magic-link logins (users 9 and 2).

| ID | Result | Evidence |
|---|---|---|
| UT-REPUB-1-01 (as live drive) | ✅ | `latest_publications([17,25,41])` → rows 1/16/17 only (highest per timeline) |
| UT-REPUB-1-02 (as live drive) | ✅ | Seal refused with 10 events (tl 19); allowed with 0 (tl 25/41) |
| FT-REPUB-1-01 | ✅ | tl 25 → v2 row 16; v1 row 5 untouched, hash identical |
| FT-REPUB-1-02 | ✅ | tl 19 → `E-LIVE-007`, names "E2E Clerk", nothing written |
| FT-REPUB-1-03 | ✅ | tl 51 (real work_task 136): `blocked` event (not `started`) → republish refused `E-LIVE-007`, names Rochelle, still 1 row |
| FT-REPUB-1-04 | ✅ | tl 50: task flipped `needs_info` → republish refused with `NEEDS_INFO` message, still 1 (v1) row |
| FT-REPUB-1-05 | ✅ | tl 41, two parallel curls: one v2 winner (row 17), one `E-LIVE-008`, exactly 2 rows |
| FT-REPUB-1-06 | ✅ | tl 49, fresh ad-hoc task: first publish → `version:1, is_republish:false` |
| FT-REPUB-1-07 | ✅ | tl 49: added a task, republished → v2/2 items; `perform/today` as Rochelle returned both items from v2 |
| FT-REPUB-1-08 | ✅ | soft record on task 19 resolves publication {16, pt-53} |
| FT-REPUB-1-09 | ✅ | tl 25 as account 6 → "Timeline not found" |
| Regression | ✅ | `npm test` 680/680; `tsc --noEmit` clean; reader baselines byte-identical pre/post |

**Completion gate: all stories done, all planned tests pass.** Fixture timelines (49, 50, 51 in workspace 14) stay in the live data permanently — once published, a timeline can never be deleted (P3A-1), same as every earlier epic's test fixtures.

**2026-11-01 (US-05, board endpoint + planner UI).**

| ID | Result | Evidence |
|---|---|---|
| `live/publication_status` smoke | ✅ | tl 17/19 (activity) → sealed; tl 25/41 (republished, no activity) → v2, unsealed; unknown tl → absent |
| Board endpoint (548) over real HTTP | ✅ | workspace 14: tl 26 → v1 sealed, tl 25 → v2 unsealed, drafts → v0 unsealed |
| `canRepublish`/`versionBadge` units | ✅ | UT-REPUB-1-10…13, 4/4 |
| Typecheck (`tsc --noEmit`) | ✅ | clean after fixing 10 pre-existing demo fixtures missing the new required fields |
| Regression | ✅ | `npm test` 680/680 |
| Playwright e2e | ◐ | grepped for affected ids/text — none found; specs not executed (dev server not started this session) |
