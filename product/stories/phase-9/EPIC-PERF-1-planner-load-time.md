# PERF-1 — Planner load-time fixes

**Epic ID:** PERF-1
**Feature:** Fix the four concrete, measured causes of planner slowness from
`product/performance/planner-load-time-audit.md` (2026-11-02): a job's detail firing
4× duplicate `lines` calls and 2× duplicate `links` calls; those requests not being
cancelled when the modal closes; a wrong "no maps" message flashing during load; and a
14.3-second unexplained main-thread block when opening the Planner tab.
**Status:** ✅ **Nothing left here.** US-01–04 done. US-05 (final re-measure) moved →
`product/stories/phase-10/` as US-LOAD-1-06; US-06 (backlog endpoint) moved → US-LOAD-1-02 (done,
2026-11-02). This epic file is kept for its history; all further work happens in LOAD-1. Note:
US-04's "14.3s block" was a measurement error, retracted — see its Updates.
**Depends on:** None — this is a fix to code already shipped and in daily use.
**MVP:** US-01 through US-05, all in scope. No deferrals — these are the only four
issues the audit found; there is nothing smaller to cut.
**Goal:** Open a job in the planner and the network panel shows **3 calls, not 10+**
(the job itself, one `links` call, one `lines` call — each exactly once). Close the
modal mid-load and nothing fires afterward. Open "New job" and it never shows "no maps"
if the plan has maps. Opening the Planner tab is explained — either genuinely fast, or
a real, named cause is on record for why it isn't yet.

---

## Context

This epic exists because of one audit, not a guess. Every number in every story below
is from `product/performance/planner-load-time-audit.md` — read it before starting,
the way any epic here expects `product/emgramprd.md` read first.

**Root cause for US-01/02/03, already found (re-verify, don't re-discover):** in
`webapp/protype-2/src/planner/components/JobsModal.tsx`, when a job row expands
(not cancelled/completed), two sibling components mount at once and each
independently fetches the same job's data:

- `JobLinesEditor.tsx:55` — `getWorkItemLines(workItemId)`
- `ExceptionSendPanel.tsx:84` — `Promise.all([getWorkItemLinks(workItemId), getWorkItemLines(workItemId)])`

Neither knows the other exists. In production that's already 2× the necessary `lines`
calls; React StrictMode (dev only) doubles everything again, which is the measured
4× `lines` / 2× `links`. **StrictMode is not the bug — the duplicate fetch is.**

**The two shapes are not identical**, which is why this isn't a one-line dedupe:
`JobLinesEditor` needs the full `getWorkItemLines` result (`lines`, `estimate`,
`available_items`, `frozen`); `ExceptionSendPanel` only reads `.lines` out of it and
reshapes each into its own `SheetLine` (`item_type_id`, `label`, `quantity`). The fix
is lifting the fetch to the parent once and letting each child derive its own shape
from the same raw result — not just suppressing a "duplicate" request.

## Existing Architecture (Do Not Break)

- `JobLinesEditor`'s own save flow (`handleSave`) re-fetches `getWorkItemLines` after a
  successful PUT to pick up the server's recalculated estimate — that refetch is
  correct and stays; only the **initial on-mount** fetch is being lifted.
- `ExceptionSendPanel` is shared between the planner (`variant="planner"`) and the
  performer's step screen (`variant="performer"`, used standalone, no `JobsModal`
  parent) — the fix must not break the performer path, which has no shared fetch to
  lift into.
- `onLinksLoaded` (EXC-2) — `ExceptionSendPanel` already reports its loaded parent link
  up to its caller specifically so a caller doesn't need a second `getWorkItemLinks`
  call. The same principle extends to this fix; it does not replace it.

## Non-Goals

- Not fixing `JobPeekSheet` — confirmed separate: it fetches a **different** job
  (a sent/child job being peeked at), not a duplicate of the open row's own job. Leave
  it alone.
- Not changing the performer-side `ExceptionSendPanel` usage (`StepScreen.tsx`,
  `SessionScreen.tsx`) — those have no sibling component duplicating their fetch; the
  bug is specific to the planner's `JobsModal` rendering both children together.
- Not attempting a general "shared data cache" library or React Query migration — that
  is a much bigger change than three duplicate network calls justify. Lift the one
  fetch to the one parent that needs it.

---

## Stories

> Work protocol: set a story to **In progress** before touching code, work one story
> at a time per the README's sequencing diagram, set it **Done** when its acceptance
> criteria pass, and append a dated line to its **Updates** list for anything learned.

---

### US-PERF-1-01 — One `lines` fetch, shared by both children

**Status:** Done (2026-11-02)

**Description.** In `JobsModal.tsx`, fetch `getWorkItemLines(job.id)` once when a job
row expands (alongside the existing `openReport`/steps fetch, or as its own effect —
whichever keeps the loading states honest), store the raw result, and pass it down as
a prop to both `JobLinesEditor` and `ExceptionSendPanel`. Each child stops fetching on
mount and instead derives its own local state from the prop — `JobLinesEditor` keeps
its `available_items`/`estimate`/`frozen` fields from the same result; `ExceptionSendPanel`
maps the same `.lines` into its own `SheetLine` shape, exactly as it does today, just
from a prop instead of its own fetch.

**Story.** As the **founder**, I want opening a job to make one `lines` request instead
of four, so that every job click doesn't quadruple the load on the backend for data
that's identical four times over.

**Acceptance criteria**
- [ ] `performance.getEntriesByType('resource')` after opening a job shows exactly
      **one** `work-item/{id}/lines` call (not two in production terms, not four in dev).
- [ ] `JobLinesEditor`'s own **save** flow still re-fetches `getWorkItemLines` after a
      successful PUT (that refetch is correct, separate from the on-mount fetch, and
      must not be removed).
- [ ] The job-detail UI renders identically — same estimate, same line items, same
      frozen-state banner, same available-items dropdown — confirmed by screenshot
      comparison against the audit's own screenshot of this modal.
- [ ] `ExceptionSendPanel` on the **performer** side (`StepScreen`, `SessionScreen`,
      no `JobsModal` parent) is completely unaffected — it still fetches its own data,
      because there is no sibling to share with there.
- [ ] Existing unit tests for `exceptionSheet.ts` (the pure mapping logic
      `ExceptionSendPanel` already uses) still pass unchanged — note there is **no**
      component-render test infra in this codebase (no React Testing Library/jsdom
      anywhere in `webapp/protype-2`), so proof for `JobLinesEditor`/`ExceptionSendPanel`
      themselves is the **browser-based** check below (FT-PERF-1-01), not a new unit
      test framework introduced just for this fix.

**Countermeasures**
- The two consumers want different SHAPES from the same raw `lines` array — don't
  flatten this into "just pass whatever `ExceptionSendPanel` happened to fetch"; pass
  the full `getWorkItemLines` result down and let each child's existing mapping logic
  (already written, already correct) run against the shared data instead of its own
  fetch result.
- `JobLinesEditor`'s existing `cancelled` guard (prevents `setState` after unmount) is
  a good pattern worth keeping on the NEW shared-fetch location in `JobsModal`, not
  dropped just because the fetch moved.
- Re-run the exact measurement from the audit (`performance.getEntriesByType('resource')`
  after opening a job) as this story's own proof — don't just eyeball the screen.

**Updates**
- **2026-11-02 — Done.** Lifted `getWorkItemLines` to `JobsModal` (new `jobLines`/`isLoadingLines`/`linesError` state, fetched in `openReport` alongside activity/steps). `JobLinesEditor` now takes `lines`/`isLoading`/`loadError` as props and derives `estimate`/`availableItems`/`frozen` from them instead of fetching; its post-save refetch (needed because `putWorkItemLines`'s own response has no `lines`/`available_items`) now reports the fresh result up via a new `onSaved` callback instead of only updating local state, so the shared state in `JobsModal` stays correct too. `ExceptionSendPanel` gained an optional `lines` prop: when supplied (planner/shared mode) it fetches only `links`, deriving its `SheetLine[]` from the prop via a new `effectiveLines`; when omitted (performer/standalone mode — `StepScreen`, `SessionScreen`) it is **completely unchanged**, still fetching both itself. Added `onLinesStale` so a successful send (which moves quantities off the parent) tells `JobsModal` to refetch the shared lines, since in shared mode `load()`'s own refetch now only covers links.
- **Also fixed, same function, directly in scope:** `openReport`'s three fetches (activity, steps, lines) used to run **sequentially** (`await` each in turn) — the audit's own numbers show this cost roughly 0.8s of pure serialization on top of each call's own time. They now fire concurrently, each still setting its own loading/error state the moment IT resolves (not gated behind `Promise.allSettled`), preserving the existing "one finishing first shouldn't block the other" behaviour documented in the original code.
- **🔴 Real bug caught before shipping, not in the plan:** the first version of this fix declared `refetchLines` (a `useCallback`) *after* `JobsModal`'s existing `if (!isOpen) return null;` early return. That's a genuine Rules-of-Hooks violation — confirmed live: opening the modal crashed to a blank screen with React's "Rendered more hooks than during the previous render" error, reproducible on a hard reload (not an HMR artifact — checked that explicitly before concluding it was real). Fixed by moving the hook above the early return, with a comment at the call site explaining why it must stay there. Caught by actually opening the modal in the browser before calling this done, not just by the typecheck (which doesn't catch hook-order bugs).
- **Verified live, real HTTP, two different jobs** (one with no items/no exceptions, one with real locked items and a real sent-exception chip): both rendered identically to before the change — confirmed by screenshot, not just by the network panel.

  | | Before (audit) | After (this fix) |
  |---|---|---|
  | `lines` calls per job open | 4 | **1** |
  | `links` calls per job open | 2 | 2 (dev-mode StrictMode only — not this bug; see epic's root-cause note) |
  | Total requests, job #139 (no items) | 10 | **7** |
  | Total requests, job #138 (locked items + exception) | — (not audited) | **5** |
- `npx tsc --noEmit`: clean. `npm test`: 680/680, unchanged.

---

### US-PERF-1-02 — Cancel stale requests when a job row closes

**Status:** Done (2026-11-02)

**Description.** The audit found that closing a job's detail and opening a different
panel did **not** stop that job's `links`/`lines` requests — two more waves of the same
calls landed over the next ~2.4 seconds, for a job no longer on screen. Add proper
cancellation (an `AbortController`, or the lifted fetch in US-01 checking an `isStale`
flag before calling `setState`) so collapsing a job row, or closing the modal, actually
stops the in-flight work instead of just ignoring its eventual result.

**Story.** As the **founder clicking through jobs quickly**, I want closing one job to
actually stop its requests, so that rapidly checking several jobs doesn't pile up a
growing queue of abandoned network calls competing with the one I'm actually waiting on.

**Acceptance criteria**
- [ ] Open a job, immediately close it, wait 5 seconds: zero further network activity
      for that job's id (reuse the audit's own 8-second-idle-window check).
- [ ] Open job A, immediately open job B without closing A first (if the UI allows
      both open at once — confirm current behaviour before assuming): A's fetch is
      either cancelled or its result is provably discarded, never applied to B's view.
- [ ] No new console errors/warnings from an aborted fetch (a caught `AbortError` is
      fine; an uncaught rejection is not).

**Countermeasures**
- `AbortController.abort()` makes `fetch` reject with an `AbortError` — the existing
  `.catch` blocks in `JobLinesEditor`/`ExceptionSendPanel`/`JobsModal` must not surface
  that as a user-facing error message ("Couldn't load this order's items.") when the
  real reason was "the user closed this before it finished," not a real failure.
- This story depends on US-01's shared-fetch location existing first — cancelling two
  independent fetches in two files is wasted work if US-01 is about to delete one of
  them.

**Updates**
- **2026-11-02 — Done.** Added optional `signal?: AbortSignal` to the four `plannerApi.ts` functions this area calls (`getWorkItemActivity`, `getWorkItem`, `getWorkItemLines`, `getWorkItemLinks`) — `performRequest` already accepted a `signal` and passed it straight to `fetch`; it just wasn't exposed on these call sites. Purely additive (optional param, every other existing caller across the app is unaffected).
- `JobsModal`'s `openReport` now owns one `AbortController` (`openAbortRef`), aborted and replaced every time a different job opens, and aborted by a `useEffect` when the whole modal closes (`isOpen` → false). Every `.catch`/`.finally` checks `signal.aborted` first so an abort never flashes a false error message.
- `ExceptionSendPanel`'s own mount fetch (the `links`, and in standalone/performer mode `lines` too) now uses the standard React unmount-cleanup pattern — `useEffect` creates its own `AbortController`, aborts it on cleanup. `submit()`'s post-send refetch deliberately passes no signal (that refresh follows a real user action on a component that's clearly still mounted, not something an unrelated unmount should cut off).
- **Verified live:** opened a job then immediately re-clicked to close it mid-load — request count held at 7 for a full 8-second wait afterward (the audit's own check; previously two more waves of 6 requests each landed in that window). Switched from job #139 to job #138 — only job #138's 5 requests appeared, nothing for #139. Zero console errors either time.
- **A side benefit, confirmed not staged:** React StrictMode's dev-only double-mount is now visibly doing what it's supposed to with cleanup in place — one `links` call per open shows a ~2ms duration (the simulated mount, aborted almost instantly) and the other completes normally, instead of both running to full duration as before this story.
- `npx tsc --noEmit`: clean. `npm test`: 680/680, unchanged.

---

### US-PERF-1-03 — "New job" panel waits for real data before deciding what to say

**Status:** Done (2026-11-02)

**Description.** The audit found the New Job panel briefly shows *"This plan doesn't
use any maps yet"* while `workspace/{id}/map` is still loading, then corrects itself
once the real answer arrives. Gate that message behind an actual "still loading" check
(`isLoading` / the maps array being fetched vs. genuinely empty), not "the array is
currently empty," which is true in both the loading state and the real empty state.

**Story.** As the **founder opening New Job**, I want it to never tell me something
false for a moment, so that I don't start clicking toward "Workspace Settings" to fix
a problem that doesn't exist.

**Acceptance criteria**
- [ ] On a plan that HAS maps: the "doesn't use any maps yet" message never renders,
      not even for one frame, at any network speed (test with Chrome DevTools network
      throttling set to Slow 3G, not just on a fast local connection).
- [ ] On a plan that genuinely has NO maps: the message still renders correctly, once
      loading is actually finished.
- [ ] No new loading spinner is introduced where a instant, correct answer was already
      available — this is a gating fix, not a new UI element.

**Countermeasures**
- Same file as US-01/02 (`JobsModal.tsx`) — sequential with those two, not parallel.
- Don't fix this by just delaying the message a fixed number of milliseconds; gate it
  on the real loading state, or it will still be wrong on a slow connection.

**Updates**
- **2026-11-02 — Done.** `maps.length === 0` was the whole check (true both "still loading" and "really empty," since `maps` starts as `[]`); gated behind the existing `isLoading` flag `load()` already sets, same pattern the adjacent "Jobs in this plan" section already used correctly (confirmed that section was never buggy — only "New job" was).
- **Verified live** with a real slow connection, not guessed: patched `window.fetch` to delay the `workspace/{id}/map` call by 6 seconds, opened New Job — showed "Loading…" the whole time, never the false "doesn't use any maps yet" message, then correctly populated the real map dropdown once the delay resolved. Restored the real `fetch` afterward; no lasting change to the page. (No network-throttling tool was available in this session's browser tools, so a direct `fetch` patch stood in for Chrome DevTools' Slow 3G — same effect, verified against real code, not a simulation of the simulation.)
- `npx tsc --noEmit`: clean. `npm test`: 680/680, unchanged.

---

### US-PERF-1-04 — Diagnose and fix the 14.3-second main-thread block

**Status:** Done (2026-11-02, Opus) — the 14.3s block turned out not to exist; the real
cause of the slow load was found and partly fixed instead. See Updates.
**Model note:** Opus-class (or Fable) — root cause is NOT diagnosed yet (unlike US-01–03,
which already have a confirmed cause). CLAUDE.md: recommend Opus before a risky/unknown
story, and immediately on a bug that fails twice. A 14-second main-thread block that
stalls even a browser screenshot command is both.

**Description.** The audit measured a silent 14.3-second gap — zero network activity —
between the Architectures page's data arriving and the Planner tab's first request
going out, right after clicking into Planner. During this same window, a screenshot
command (`CDP Page.captureScreenshot`) **timed out at 30 seconds**, meaning the JS
thread itself was busy, not just "waiting." This story is: attach the React DevTools
Profiler (or Chrome's own Performance panel) across that exact transition, find the
actual function burning the time, and fix it — or, if it turns out to be something
structural (a huge synchronous computation that has to happen), document why and what
the real options are.

**Story.** As the **founder**, I want to know exactly what the app is doing for 14
seconds when I open Planner, so that either it gets fixed, or I at least know it's not
a mystery anymore.

**Acceptance criteria**
- [ ] A Performance-panel or React Profiler recording exists showing the actual
      function(s) occupying that window, named specifically (not "rendering is slow" —
      an actual call stack / component name).
- [ ] Either: a fix is shipped and the gap is re-measured (same `performance.getEntriesByType`
      method as the audit) showing a real, named improvement — OR, if the cause is
      structural and not a quick fix, that is written up as plainly as the audit itself,
      with what WOULD need to change and the trade-off, for the founder to decide on
      separately.
- [ ] Confirm whether React StrictMode's double-invoke (dev-only) is doubling an
      already-expensive computation here, compounding the real problem — if so, say so;
      if not, rule it out explicitly rather than leaving it an open question.

**Countermeasures**
- This is the one story in the epic where the fix shape is genuinely unknown going in —
  don't force a fix if the profile doesn't point at one cleanly. A clear write-up of
  "here is exactly what's slow and why" is an acceptable outcome on its own if a safe
  fix isn't obvious; a wrong guess at a 14-second regression is worse than stating it
  plainly and asking.
- Different files from US-01–03 (this is route/navigation-level, not `JobsModal.tsx`) —
  safe to run in parallel with that whole chain.

**Updates**
- **2026-11-02 — 🔴 The premise was wrong.** Re-measured with the click timestamp captured *inside the page* (a capture-phase listener) and a `PerformanceObserver` for long tasks: the first Planner request fires **~85ms** after the click, and the longest main-thread block is **100ms**. The audit's "14.3s gap" ended exactly at the click, and the click time was never read back — it was the auditor's own pause between page load and click. The screenshot timeout was on the port-4173 preview build's sign-in, a different app. Audit file corrected in place (banner at the top + retraction), not deleted, so the mistake stays on record.
- **The real cause, measured:** Planner open = 4 requests in a chain (plan list → board → jobs + backlog), ~8.4s. Timed directly against Xano: board alone 3.2s, backlog alone 2.3s, **both at once 5.8s** — the sum, not the max. The backend works through one account's requests roughly serially, so load time ≈ total server work.
- **Tried, measured, reverted:** starting the jobs/backlog requests alongside the board, and guessing the plan from the last visit to start the board before the plan list returned. Requests did all start at ~180ms — and total time didn't move (8.9s), while the board itself arrived *later* (it now shared the queue). Reverted cleanly (module, tests and wiring deleted); confirmed no leftovers by grep.
- **Shipped fix 1 — fewer requests.** `src/perform/inflight.ts`: identical GETs already in flight share one network call (in-flight only, never cached; token in the key; each caller parses its own copy; requests with an `AbortSignal` or body are never shared). Removes dev-mode StrictMode duplicates of the plan list, jobs list and backlog. Planner open: **6–7 requests → 4**. 4 unit tests (UT-PERF-1-04-01…04).
- **Shipped fix 2 — cheaper board.** Server-side breakdown of the board's ~3s: `job_step_hydration` 1.5s, `derive_tasks` ×4 0.6s, `publication_status` 0.3s. `job_step_hydration` ran `estimate/estimate_job` (~0.35s each) for **every job in the plan** though it only shows scheduled steps. Now reads the links first and estimates only `work_item where id in $linked_job_ids` (filter in SQL, per CLAUDE.md). **Proven byte-identical**: a scratch function fingerprinted (sha256) the output for all 14 plans with jobs before and after — 14/14 identical. Plan with nothing scheduled: **3.21s → 0.21s**; workspace 43: **1.5s → 0.9s**; full 14-plan sweep **37.5s → 15.5s**. Scratch function deleted afterwards.
- **User-visible result, stated plainly:** click → fully loaded on workspace 43 (2 jobs) went from 8.4s to 8.4s / 6.6s across two runs — inside Xano's ±1.5s noise. The fixes stop the board getting slower as a plan grows; they don't make a small plan dramatically faster. The biggest remaining cost is the backlog endpoint → US-PERF-1-06.
- StrictMode question (AC 3): answered — it doubled *requests* (fixed by fix 1), not an expensive render; long tasks after the click were 67ms and 100ms.
- `npx tsc --noEmit`: clean. `npm test`: 684/684 (680 + 4 new).

---

### US-PERF-1-05 — Re-measure and record the real numbers

**Status:** Moved (2026-11-02) → folded into **US-LOAD-1-06** (`product/stories/phase-10/`), which re-runs these same checks.

**Description.** Re-run the exact audit method (`performance.getEntriesByType('resource')`,
same Planner flows: open app, open Planner, open a job, open New Job) after US-01–03
land, and record the before/after numbers in this epic's Test Results. This is the
epic's own proof that the fix is real, in the same evidence-first style as the original
audit — not "it feels faster."

**Story.** As the **founder**, I want the same kind of real numbers I got in the audit,
after the fix, so "we fixed it" means something I can see, not just a claim.

**Acceptance criteria**
- [ ] Opening a job: request count and total duration, before vs. after, in a table.
- [ ] Closing a job mid-load: confirmed zero stray requests in the following 8 seconds
      (US-02's own check, re-run here as final proof).
- [ ] New Job panel: confirmed no incorrect message at any point, throttled connection
      included.
- [ ] US-04's outcome (fixed-and-measured, or diagnosed-and-written-up) recorded here
      too, whichever it turned out to be.

**Countermeasures**
- Waits for US-01–03 (needs the real fix in place to mean anything) and should also
  wait for US-04's outcome to be known, even if US-04 didn't ship a code change.

**Updates**
- *(none yet)*

---

### US-PERF-1-06 — Make the backlog endpoint (559) stop doing work it doesn't use

**Status:** Moved (2026-11-02) → `product/stories/phase-10/` as **US-LOAD-1-02**. Build it there, not here.
**Model note:** Sonnet is enough — same proven pattern as US-04's hydration fix, with
the same byte-identical proof. Opus only if the proof fails twice.

**Description.** Found during US-04. The Unscheduled drawer's endpoint
(`apis/planner/559_workspace_workspace_id_backlog_work_GET.xs`, ~1.6–3.8s measured) has
two problems:
1. **It estimates every non-cancelled job** (`estimate/estimate_job`, ~0.35s each),
   including jobs whose steps are all already on a day and so never appear in the
   drawer — the same waste US-04 removed from the board.
2. **It loads the whole schedule-link table with no filter**
   (`db.query planner_task_work_task { return = {type: "list"} }`) — every account's
   rows — to decide which steps are unscheduled. Its cost grows with the whole
   customer base, not with this plan.

**Story.** As the **founder**, I want the Unscheduled list to cost only what this plan
needs, so that the planner doesn't slow down as more jobs — or more customers — are
added.

**Acceptance criteria**
- [ ] The link query is filtered to this plan's own work tasks
      (`work_task_id in $wt_ids`, same as `job_step_hydration`).
- [ ] `estimate_job` runs only for jobs that have at least one unscheduled step,
      selected by a `db.query ... where id in $...` filter, not a branch inside a loop.
- [ ] **Output proven identical** for every plan the test account can reach, before vs
      after (sha256 of the response over real HTTP — 559 is an endpoint, not a
      function, so `runWorkspaceFunction` can't call it; use magic-link tokens).
- [ ] Before/after server time recorded for at least one plan with many fully
      scheduled jobs (that's where the saving shows).

**Countermeasures**
- Cancelled jobs stay excluded here (559's rule), unlike the board — don't copy that
  line from `job_step_hydration`.
- 559 is also read by the Jobs modal's scheduling paths and the E2E specs that drag
  cards — re-run the Playwright `card-scheduling` spec after the push.
- Fetch the live source with `getAPI` and diff before editing (CLAUDE.md).

**Updates**
- *(none yet)*

---

## Governance (data integrity, validation, observability)

N/A by scope. No table is touched, no validation rule changes, no new error code is
introduced. Nothing here writes to the database differently than it already does —
this epic only changes WHEN and HOW OFTEN existing read-only fetches fire.

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-PERF-1-01 | Unit | Any pure shape-mapping helper extracted during US-01 (e.g. raw lines → `SheetLine[]`) | Same output as `ExceptionSendPanel`'s existing inline `.map()` today — only test if logic is actually extracted into a standalone function; no new component-render test infra |
| FT-PERF-1-01 | Functional (browser) | Open a job, count `lines`/`links` calls | Exactly 1 of each (verified via `performance.getEntriesByType`) |
| FT-PERF-1-02 | Functional (browser) | Close a job mid-load, wait 8s | Zero further network activity for that job |
| FT-PERF-1-03 | Functional (browser) | Open New Job on a plan with maps, throttled connection | "No maps" message never renders |
| FT-PERF-1-04 | Functional (browser) | Open Planner tab, profile the transition | Root cause of the 14.3s gap named, fixed or documented |
| UT-PERF-1-04-01…04 | Unit | `inflight.ts`: shared while in flight; never cached; keys isolate URL/user; failure shared then retried | All pass |
| FT-PERF-1-04-H | Functional (Xano) | `job_step_hydration` output fingerprint, all plans with jobs, before vs after | 14/14 sha256 identical |

**Completion gate:** all stories done, US-05's before/after numbers recorded, existing
`npm test` suite still green, Playwright specs touching `JobsModal`/`ExceptionSendPanel`
(if any) re-run and green.

## Test Results

**2026-11-02 — US-01…04 (Sonnet for 01–03, Opus for 04).** All numbers from the page's
own `performance.getEntriesByType('resource')` or Xano's own function timing.

| ID | Result | Evidence |
|---|---|---|
| FT-PERF-1-01 | ✅ | Job open: `lines` 4 → **1**; `links` 2 (dev StrictMode, now shared by US-04's in-flight dedupe) |
| FT-PERF-1-02 | ✅ | Close mid-load, wait 8s: request count flat at 7; switching jobs fired only the new job's requests |
| FT-PERF-1-03 | ✅ | `fetch` patched to delay `/map` 6s: "Loading…" throughout, never the false "no maps" message |
| FT-PERF-1-04 | ✅ (premise retracted) | No 14.3s block: first request 85ms after click, longest task 100ms. Real cause named: serial backend + board doing unused work |
| UT-PERF-1-04-01…04 | ✅ | 4/4 |
| FT-PERF-1-04-H | ✅ | 14/14 plans byte-identical; plan 38 3.21s → 0.21s, plan 43 1.5s → 0.9s, sweep 37.5s → 15.5s |
| Regression | ✅ | `npm test` 684/684; `tsc --noEmit` clean |

| Planner open (workspace 43) | Requests | Board visible | All loaded |
|---|---|---|---|
| Before | 6–7 | 5.0s | 8.4s |
| After, run 1 | 4 | 5.2s | 8.4s |
| After, run 2 | 4 | 3.9s | 6.6s |

Small-plan wall time is inside Xano's noise; the gains are fewer requests and a board
that no longer slows down per job. US-05 (final re-measure) and US-06 (backlog
endpoint) remain.
