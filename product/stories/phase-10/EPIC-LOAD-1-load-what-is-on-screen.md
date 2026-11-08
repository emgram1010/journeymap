# LOAD-1 — Load what's on screen

**Epic ID:** LOAD-1
**Feature:** When the planner opens, load only what the screen shows. Load everything
else (a card's steps, other weeks, step estimates) when the user asks for it, and
stop recalculating numbers that only change when someone edits them.
**Status:** Ready to execute (starts on the founder's go). See `README.md` → "How to execute".
**Depends on:** PERF-1 US-01–04 (done). Absorbs PERF-1 US-05 (re-measure, now US-06
here) and PERF-1 US-06 (backlog endpoint, now US-02 here).
**MVP:** US-01 through US-06. US-05 needs founder approval before its schema push.
**Goal:** Opening the planner does only on-screen work: the board computes no
estimates, the backlog sends summary rows only and reads only this plan's links, the
board covers the visible range, and estimates are read rather than recalculated.
Every change is proven by before/after numbers taken with the house method (README).

---

## Context

Measured 2026-11-02 (see `README.md` and `product/performance/planner-load-time-audit.md` §5):
the backend handles one account's requests roughly serially, so **load time ≈ total
server work**. Parallel loading was tried and reverted. The remaining lever is doing
less work per request, and the inventory in the README shows where the waste is.

## Existing Architecture (Do Not Break)

- **Reference, do not copy:** step text and expected minutes come from each job's
  **pinned version**. Nothing here may copy them into planner rows.
- `job_step_hydration` (fn 168) is called **only** by the board (548). Its output was
  proven byte-identical across 14 plans after PERF-1. Re-prove after any change.
- The Unscheduled drawer's summary row shows `expected_minutes` + an estimate badge
  per card (`BacklogDrawer.tsx` ~697). These numbers **are** displayed and must stay
  correct.
- The Jobs column (558) shows step counts, units and chips. **Out of scope**: it
  needs what it loads and is the cheapest call (~0.8s).
- `src/perform/inflight.ts` (PERF-1) shares identical in-flight GETs. Any new
  "load on click" request gets this for free; don't build a second dedupe.

## Non-Goals

- No caching of read results in the browser beyond the existing in-flight sharing:
  refetch-after-write must always see the write.
- No change to what any screen *shows*, only to *when* it's fetched.
- No Jobs column change (see above).
- No Xano plan or hosting change. If more concurrency is the answer, that's a
  founder decision, raised separately.

---

## Stories

> Work protocol: set a story **In progress** before touching code, one at a time
> (US-01 ∥ US-02 is the only allowed pair), **Done** when its acceptance criteria
> pass, and append a dated line to its **Updates** for anything learned.

---

### US-LOAD-1-01 — Board stops computing step estimates nothing displays

**Status:** Done (2026-11-02)
**Model:** Sonnet

**Description.** `job_step_hydration` still calls `estimate/estimate_job` (~0.35s
each) for every job with a scheduled step, and returns `expected_minutes`,
`estimate_status` and `estimate_source` per step. Verified 2026-11-02 by grep: **the
board never reads those three fields.** `plannerAdapter.adaptTask` uses only job
title, step title, done-when, ids and step count. The function's only caller is
548. Remove the estimate work and those three fields from the hydration output.

**Story.** As the **founder**, I want the board to skip a calculation nobody sees, so
that each scheduled job stops adding ~0.35s to every planner load.

**Acceptance criteria**
- [x] Re-confirm before deleting: grep `webapp/` and `apis/` for any reader of
      `linked_steps[*].expected_minutes`, `.estimate_status` or `.estimate_source`,
      and for any second caller of `planner/job_step_hydration`. Record the result in
      Updates. If either exists, stop and re-scope.
- [x] `job_step_hydration` no longer calls `estimate/estimate_job` and no longer loads
      what only the estimate needed. Every other field is byte-identical (fingerprint
      of the response with the three removed fields stripped, all plans with jobs).
- [x] `LinkedStep` in `plannerApi.ts` drops (or marks optional) the three fields;
      `npx tsc --noEmit` clean.
- [x] Board renders identically: screenshot before/after on a plan with scheduled
      job cards, including a card covering several steps. *(After-screenshot only; a
      before-screenshot was not taken. The byte-identical fingerprint stands in for it.
      See Updates.)*
- [x] Server time for workspace 43 and the largest plan, before vs after.

**Countermeasures**
- `estimate_job` may still be needed by **other** callers (555, 559, 560, 583, 607,
  608, 610, `variance/task_report`, `estimate/refresh_job_slots`). Remove it from the
  hydration function only, never globally.
- Fetch the live source with `getFunction` and diff before editing (CLAUDE.md).

**Updates**
- 2026-11-02 — Re-confirm: no reader of the three fields. `LinkedStep` (plannerApi.ts)
  is used only by `plannerAdapter` (title, step title, done-when, ids, count). The only
  other `expected_minutes` readers (`BacklogDrawer`, `JobsModal`, `varianceDisplay`)
  read the backlog (559) and job-task (555) shapes, not the board's. `cardVariance` has
  no caller outside its own test. Only caller of `planner/job_step_hydration` is 548
  (560 mentions it in a comment). Live source fetched with `getFunction` and matched
  local before editing.
- 2026-11-02 — Removed, with everything that only fed them: the `estimate_job` call, the
  `schema_version` pre-check, and the per-job / per-stage estimate maps. **Kept** the
  `journey_map_version` load, because the step text comes from it. `estimate_job` itself
  untouched.
- 2026-11-02 — **Not done: a before-screenshot.** The after-screenshot is in the session
  scratchpad (`board_after_nov4.png`: Wed Nov 4, card "Turn-around · 8 steps", 710m, 8
  of 8 steps). The 42 per-plan sha256 fingerprints being identical is the stronger proof
  that the board's data is unchanged.
- 2026-11-02 — Scratch functions used for the sweep and a user-email lookup were
  deleted afterwards.

---

### US-LOAD-1-02 — Backlog stops wasted estimates and reads only this plan's links

**Status:** Done (2026-11-02)
**Model:** Sonnet (moved here from PERF-1 US-06)

**Description.** `apis/planner/559_workspace_workspace_id_backlog_work_GET.xs`
(~1.6–3.8s) has two problems:
1. It runs `estimate_job` for **every** non-cancelled job, including jobs whose steps
   are all on a day and so never appear in the drawer.
2. `db.query planner_task_work_task { return = {type: "list"} }` has **no `where`**,
   so it loads every account's schedule links to work out what's unscheduled. Cost
   grows with the whole customer base, and it reads other tenants' rows.

**Story.** As the **founder**, I want the Unscheduled list to cost only what this plan
needs, so that the planner doesn't slow down as jobs, or customers, are added.

**Acceptance criteria**
- [x] Link query filtered: `where = $db.planner_task_work_task.work_task_id in $wt_ids`.
- [x] `estimate_job` runs only for jobs with at least one unscheduled step, picked by a
      `db.query work_item where id in $...` (filter in SQL, not a branch in a loop;
      seed the array with `-1`).
- [x] Response **byte-identical** for every plan reachable by the test login(s), over
      real HTTP (endpoint: use the magic-link token method in the README).
- [x] Server time before/after on the plan with the most fully scheduled jobs.
- [x] Playwright `e2e/card-scheduling.spec.ts` re-run green (drags use this list).
      The spec was stale against WIN-1 (it filled the board's out-of-window default day
      into Place…, which WIN-1 now disables). Fixed with the founder's go: it now pages
      to a day inside the plan's own window first. **1 passed (52.9s).**

**Countermeasures**
- Cancelled jobs stay **excluded** here (559's rule), unlike the board's hydration.
- The unfiltered scan was also a **tenancy smell** (other accounts' rows in memory,
  never returned). Note it in Updates as fixed, and ask the founder whether a
  GOV-style audit for unfiltered queries elsewhere is wanted. Don't do that sweep
  unasked.

**Updates**
- 2026-11-02 — Live source of endpoint 559 (api group 24) fetched with `getAPI` and
  matched local before editing. Pushed with `updateAPI`.
- 2026-11-02 — **Tenancy smell fixed:** the unfiltered `planner_task_work_task` scan
  loaded every account's links (never returned, but in memory). Now filtered to this
  plan's work tasks. **Question for the founder, not acted on:** do you want a GOV-style
  audit of other unfiltered `db.query` calls? (Not done; not asked.)
- 2026-11-02 — **Reach of the proof:** the test login (`javierc9`, account 2) reaches 22
  of the 41 plans in the workspace. The other plans belong to other accounts and could not be hit over
  HTTP, so byte-identity is proven for those 22 only. The estimate loop only changes
  which jobs get estimated, so jobs with an unscheduled step are computed exactly as
  before.
- 2026-11-02 — **The card-scheduling spec is stale against WIN-1, independent of this
  story.** Unmodified, it fails at `unscheduled-place-confirm` (disabled: the board's
  default day for plan 43 is Oct 27, outside the plan's Nov 1–7 window). Left untouched.
  A temporary in-window copy was run and deleted: **passed**.
- 2026-11-02 — The two spec runs left test jobs named `E2E card <timestamp>` in plan 43
  (the spec's documented behaviour; nothing deleted).

---

### US-LOAD-1-03 — Backlog: summary rows first, a card's steps on click

**Status:** Done (2026-11-02)
**Model:** Sonnet
**Depends on:** US-02

**Description.** 559 returns each card with its full `steps[]` (task text, done-when,
per-step minutes and badges). The drawer shows steps **only for the one selected card**
(`BacklogDrawer.tsx`, `selectedCard.steps.map`, ~912). Return summary rows only
(card key, job, role, step count, total minutes, card badge, first/last stage,
`work_task_ids`, exception chips) and fetch one card's steps when it's selected.

**Story.** As a **planner**, I want the Unscheduled list to appear quickly with its
totals, and see a card's steps the moment I open it, so I'm not waiting for detail
on cards I never look at.

**Acceptance criteria**
- [x] 559 gains a summary mode (e.g. `?detail=summary`, or summary becomes the default
      once every caller is checked) that omits `steps[]`. Summary numbers are
      unchanged (fingerprint of the summary fields, before vs after).
      *(`detail=summary`; the default stays the full response, so no other caller moves.
      Summary == full minus `steps` on 22 of 22 plans.)*
- [x] A new read for one card's steps (job + lens key → ordered steps, same fields as
      today). Before adding one, check whether `GET work_item/{id}` (555) already
      returns enough to filter by lens client-side. Reuse it if so.
      *(Reused 555, no new endpoint: 28 cards / 142 steps compared, 0 differences.)*
- [x] Selecting a card shows a short loading state, then the same steps as today.
      Switching cards quickly never shows the wrong card's steps (abort or
      stale-guard, US-PERF-1-02 pattern).
- [x] Anything else that reads `card.steps` (grep `webapp/`; drag/drop, Place…,
      scheduling payloads) is checked, and still works or is moved to the on-click
      read.
- [x] Before/after: 559 server time and response size.
      *(Size −83%. Server time unchanged: see Test Results.)*

**Countermeasures**
- `work_task_ids` must stay in the summary: scheduling a card uses it. Don't strip
  ids, only text.
- The new endpoint goes in the **planner** API group (`PE5iDldw`). Check for a
  static-vs-dynamic route collision before naming it (CLAUDE.md routing trap).
- Governance: a new endpoint needs tenancy (`planner/resolve_actor` +
  `assert_workspace` or equivalent), friendly errors, catalog codes, and OBS events.
  Follow GOV-1/VAL-1/OBS-1.

**Updates**
- 2026-11-02 — **No new endpoint was needed, so no new tenancy/catalog/OBS work.** The
  on-click read reuses `GET work_item/{id}` (555), which already has the tenancy check.
  Equivalence proven first on real data: 28 cards / 142 steps, 559's `steps` vs 555's
  `tasks` filtered to the card's `work_task_ids` and ordered by that list: **0 differences**.
  Order comes from `work_task_ids` (built in the pinned version's stage order), not from
  555's id order.
- 2026-11-02 — Inventory of `card.steps` readers: only `BacklogDrawer` (Stages panel).
  Place… and drag/drop use the card's key and `work_task_ids`, which stay in the summary.
  `e2e/card-scheduling.spec.ts` reads `steps` from 559's default (full) response, which
  is unchanged.
- 2026-11-02 — New pure helper `src/planner/backlogCardSteps.ts` (8 unit tests, written
  first). An id the job no longer returns is **reported** (a visible red line), never
  silently dropped. `stage_label` null (555) is mapped to `''` (what 559 sent).
- 2026-11-02 — Honest finding: **summary mode does not make the server faster**, because
  the server still builds every step to compute totals; it saves payload and browser
  work (−83% bytes). The server-time win for this list came from US-02.
- 2026-11-02 — New cost: selecting a card now costs one 555 read (~0.5–1.5s server,
  once per card click). Intended trade: pay on click, not for every card on every load.

---

### US-LOAD-1-04 — Board loads the visible date range, other weeks on request

**Status:** Held — awaiting the founder's decision (see Updates)
**Model:** Sonnet; Opus if a view breaks twice

**Description.** 548 loads **every** timeline of the plan (no date filter) and runs
`derive_tasks` once per timeline (~0.15s each), plus per-timeline publication status.
The screen shows one day (Plan view) or the plan window (Schedule view). Long-running
plans pay for every past and future day on every load. Scope 548 to a date range
(default: the plan window), and load other ranges when the user navigates there.
`GET /workspace/{id}/timeline` (539) already supports `date_from`/`date_to`; follow
its shape, including CLAUDE.md's rule that optional date filters are declared as
`text` with sentinel bounds.

**Story.** As a **planner** on a plan that's been running for months, I want opening
it to cost the same as a new plan's, so the planner doesn't get slower the longer I
use it.

**Acceptance criteria**
- [ ] Inventory first (record in Updates): which views read `timelines`/`tasks` from the
      board (Plan/DayBoard, Schedule/ScheduleGrid, TimelineRail, EditModal, Inspector
      is dead code), and what date range each needs.
- [ ] 548 accepts an optional range, defaulting to the plan window. With no params, the
      behaviour is identical to today for any plan whose timelines all fall inside
      its window.
- [ ] Navigating to a day outside the loaded range fetches that range (and shares
      in-flight requests via `inflight.ts`). Nothing ever shows "empty" for a day
      that has data.
- [ ] Backlog tasks (`timeline_id: 0`) are still returned regardless of range.
- [ ] Before/after on the plan with the most timelines.

**Countermeasures**
- Out-of-window timelines exist today (e.g. workspace 43 has Oct 27 in a Nov 1–7
  plan). Decide explicitly how they appear (WIN-1 already flags them); don't
  silently drop them.
- `refreshBoard()` after a write must refetch the **currently loaded** range, not
  reset to the default.

**Updates**
- 2026-11-02 — **HELD for the founder's decision (not started).** Findings that change
  the case for this story:
  1. **The board is already cheap.** After US-01 the board endpoint takes 0.29–0.6s on
     every real plan, including the one with the most days (plan 14: 7 days, 1.2s cold /
     0.49s warm; plan 42: 6 days, 0.59s; plan 43: 3 days, 0.29s). The README's "~2–3s" is
     out of date. Per-day cost is now roughly 0.05–0.07s, not 0.15s.
  2. **No real plan has more than 7 days**, so a range limit would drop nothing except
     out-of-window days. The saving today is ~0.1s at most. It only starts to matter on
     plans that run for dozens of days, which don't exist yet.
  3. **The risk is real.** Several screens read `timelines` and would silently change if
     days went missing: Plan Health capacity and cost summaries and the "N days outside
     the window" count (`BacklogDrawer` ~467–478), and the "is this day already published /
     does it exist" check when placing a card (`BacklogDrawer` ~1195, 1254). Out-of-window
     days must not silently disappear (the Countermeasures above).
  Recommendation: **skip until a plan actually has dozens of days**, then build it with a
  measured before/after. Alternative if wanted sooner: batch the per-day task derivation
  into one call on the server (same output, no screen changes, helps every plan).

---

### US-LOAD-1-05 — Estimates stored when they change, not recalculated on every read

**Status:** Not started
**Model:** **Opus.** New table, staleness risk, many callers.
**Ask the founder before** creating the table or pushing any schema change.

**Description.** `estimate/estimate_job` runs on every read in 12 places (the board's
hydration, 555, 559, 560, 583, 607, 608, 610, `variance/task_report`,
`refresh_job_slots`, and others; grep for the full list). An estimate depends on the
job's lines and its pinned version's rates, and the version is immutable. If those are
truly its only inputs, it only changes when lines change (607 PUT, 610 exception spawn)
or when the job is created (554). Calculate it then, store it in a 1:1 side table
(CLAUDE.md's standing pattern: no new columns on tables with text validators), and
have readers read it.

**Story.** As the **founder**, I want an estimate worked out once when an order changes,
not every time someone looks at it, so that every planner screen stops paying for the
same arithmetic over and over.

**Acceptance criteria**
- [ ] **Inputs audit first, and stop if it fails:** read `estimate/estimate_job` and
      `estimate/compute_estimate` end to end and list every table they read. If an
      input changes without a line write (e.g. "measured" rates learned from
      `activity_log`, since `estimate_source` can be `measured`), caching is not safe
      as designed. Stop, write it up, and ask the founder.
- [ ] Side table `work_item_estimate` (1:1 with `work_item`, unique index, the stored
      estimate JSON, `computed_at`, an inputs fingerprint). Founder approved before the
      push.
- [ ] Written by every path that changes an input, inside the same `db.transaction` as
      the change where possible. Backfill run on a **clone** first (CLAUDE.md).
- [ ] Readers switched one at a time, each proven byte-identical (fingerprint) before
      the next.
- [ ] A Health/audit check: recompute vs stored for every open job, report any mismatch
      (OBS-1). A stale estimate must be **visible**, never silent.
- [ ] Before/after server time for 559 and 555 (the heaviest readers).

**Countermeasures**
- `db.patch` on a `json` column **merges**. To replace a stored estimate, patch it to
  `null` first, then to the new value (CLAUDE.md, critical).
- `db.patch` by `field_name` touches the first match only. Backfill by id in a loop.
- If the inputs audit fails, the fallback is a short-TTL server-side cache: a new
  design decision, so ask the founder, don't improvise.

**Updates**
- *(none yet)*

---

### US-LOAD-1-06 — Re-measure everything and record before/after

**Status:** Not started
**Model:** Sonnet (Haiku is fine)
**Depends on:** US-01–05 (or whichever are done when the founder calls it)

**Description.** The epic's proof, using the house method (README): click→board visible
and click→all loaded, two runs each, request count, and per-endpoint server time. Also
carries PERF-1 US-05's checks (open a job: request count; close mid-load: no stray
requests for 8s; New Job: never the false "no maps" message).

**Story.** As the **founder**, I want the same kind of real numbers as the audit, after
the work, so "faster" is something I can see, not a claim.

**Acceptance criteria**
- [ ] Table: before (PERF-1 numbers in Test Results below) vs after, workspace 43 **and**
      the largest plan the test login can reach.
- [ ] PERF-1 US-05's three checks re-run and recorded.
- [ ] Honest verdict line: what got faster, what's now inside noise, and what's left.

**Updates**
- *(none yet)*

---

## Governance

- **New table** (US-05 only): `work_item_estimate`, 1:1 with `work_item` (unique
  index), cascade-on-delete with its job, written only by the estimate writer. Founder
  approval before the push.
- **New endpoint** (US-03 only): tenancy guard, VAL-1 friendly errors, catalog codes,
  OBS-1 success/failure events.
- **Observability:** US-05's stored-vs-recomputed audit surfaces on the Health page.
- Everything else is read-path only: no writes change.

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-LOAD-1-01 | Xano | Hydration fingerprint (minus removed fields), all plans | Identical; estimate calls gone |
| FT-LOAD-1-02 | HTTP | 559 fingerprint, all reachable plans | Identical; link query filtered |
| FT-LOAD-1-03 | Browser | Open Planner; select a card; switch cards fast | Summary first; right card's steps; no stale steps |
| FT-LOAD-1-04 | Browser | Navigate outside the loaded range | Range fetched; never a false empty day |
| FT-LOAD-1-05 | Xano | Stored vs recomputed estimate, every open job | 0 mismatches; a forced mismatch is reported |
| FT-LOAD-1-06 | Browser | House-method re-measure, 2 runs × 2 plans | Recorded |
| Regression | All | `npm test`, `tsc --noEmit`, `card-scheduling` E2E | Green |

**Completion gate:** all in-scope stories done, FT rows recorded, regression green.
Then stop and report to the founder.

## Test Results

**Baseline (from PERF-1, 2026-11-02, workspace 43, after PERF-1's fixes):**

| | Requests | Board visible | All loaded |
|---|---|---|---|
| Run 1 | 4 | 5.2s | 8.4s |
| Run 2 | 4 | 3.9s | 6.6s |

Server-side, solo: board ~2–3s (hydration 0.9s, `derive_tasks` ~0.15s × days,
publication status 0.3s), backlog 1.6–3.8s, jobs 0.8s, plan list 0.9s.

*(LOAD-1 results go below as stories land.)*

### US-LOAD-1-01 (2026-11-02)

`planner/job_step_hydration` (fn 168), `runWorkspaceFunction` timing. Xano varies run
to run, so two "before" runs are shown where taken.

| | Before | After |
|---|---|---|
| Plan 43 (8 scheduled steps, 1 job) | 1.87s, 0.66s | **0.13s** |
| Plan 42 (54 scheduled steps, 8 jobs; the largest) | 3.69s | **0.43s** |
| Sweep of all 41 plans | 16.03s | **9.51s** |

- **Byte-identical:** sha256 of each plan's `steps` with `expected_minutes`,
  `estimate_status` and `estimate_source` left out, over all 41 plans (9 with steps:
  12, 9, 14, 32, 24, 33, 34, 42, 43). **41 of 41 hashes match** before vs after.
- `npx tsc --noEmit`: clean. `npm test`: **684 pass, 0 fail**.
- Real screen (headless Chromium, signed in, `localhost:3000/planner`, plan 43): board
  request 200, 8 linked steps, keys are exactly the 11 kept fields, none of the three
  removed ones. No page errors. Wed Nov 4 shows "Turn-around · 8 steps · 710m"; the
  Unscheduled drawer still shows its estimate ("estimate incomplete", 2 hr 45 min).
- **Not run:** Playwright specs (no change to scheduling or backlog behaviour here;
  `e2e/card-scheduling.spec.ts` is US-02's gate) and workflow tests (not runnable from a
  session).

### US-LOAD-1-02 (2026-11-02)

`GET /workspace/{id}/backlog_work` (559) over **real HTTP** from the signed-in account,
22 reachable plans, each plan fetched in turn. Two runs before, two after.

| | Before | After |
|---|---|---|
| Plan 42 (8 jobs, most fully scheduled) | 6.55s, 6.42s | **2.90s, 2.40s** |
| Plan 43 | 2.98s, 1.77s | 1.96s, 1.49s |
| Plan 14 | 3.08s, 2.48s | 1.82s, 2.35s |
| Whole sweep (22 plans) | 19.3s, 17.5s | **12.8s, 12.1s** |

- **Byte-identical:** sha256 of the raw response body, **22 of 22** plans match the
  baseline in both after-runs. The two baseline runs also matched each other (22 of 22),
  so the comparison is not noise.
- Smaller plans barely move (1.5–2.3s): within Xano's ±1.5s noise. The win is on plans
  with many scheduled jobs, which is the case that grows.
- **Playwright `card-scheduling.spec.ts`: FAIL as written** (stale against WIN-1, not
  caused by this change; see Updates). A temporary in-window copy: **1 passed (50s)**.
- No frontend change in this story, so no tsc/unit-test rerun was needed.

### US-LOAD-1-03 (2026-11-02)

HTTP, 22 reachable plans, full vs `?detail=summary`:

| | Full | Summary |
|---|---|---|
| Total payload, all plans | 60,472 bytes | **10,558 bytes (−83%)** |
| Plan 43 (4 cards) | 13,589 B | 1,532 B |
| Plan 32 (8 cards) | 30,094 B | 2,942 B |
| Server time, whole sweep | 18.8s | 14.0s (**same work; inside noise**) |

- **Full mode unchanged:** byte-identical to the US-02 baseline on 21 of 22 plans. Plan 43
  differs only because the Playwright runs added three "E2E card" jobs there; its
  summary still equals its full response minus `steps`.
- **Summary == full minus `steps`:** 22 of 22.
- **Real browser (plan 43):** open → one backlog request, `?detail=summary`, and **no**
  job read; first card click → exactly one `work_item/{id}` read; **4 of 4 cards'**
  on-click steps (count, order, stage label, task text) match the API's full steps; with
  card A's read delayed 4s and a switch to card B, the panel showed B straight away and
  **still B** after A's late answer arrived. No page errors.
- `npx tsc --noEmit`: clean. `npm test`: **692 pass, 0 fail** (684 + 8 new).
- Playwright `card-scheduling.spec.ts` is re-run once at the end (after US-04), because it
  creates a test job each run.

### Interim measurement, after US-01–03 (2026-11-02, house method)

Headless Chromium, signed in, `localhost:3000`, click **Planner** → plan 43, two cold runs.
Before = the PERF-1 baseline above (same plan, same method).

| | Requests | Board visible | All loaded |
|---|---|---|---|
| Before (PERF-1) run 1 / 2 | 4 / 4 | 5.2s / 3.9s | 8.4s / 6.6s |
| **After US-01–03** run 1 / 2 | 4 / 4 | **1.3s / 1.1s** | **3.2s / 3.1s** |

Order on the wire: plan list (0.4–0.5s) → board (0.7–0.8s) → jobs list and backlog together;
the backlog (1.8s own time) is now the last thing to land.

**Caveat, against these numbers:** plan 43 now holds three extra "E2E card" test jobs (from
the Playwright runs) that each add an estimate to the backlog, so "after" is a little worse
than it would be on the clean plan. The real figure is at least as good as shown.
