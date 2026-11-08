# Planner load-time audit

**Date:** 2026-11-02
**Method:** Claude in Chrome, driving the founder's real signed-in browser session against `localhost:3000` (the live Emgram app shell — Intelligent Layer + Planner + Execution in one SPA, `vite` dev server). Timed with the page's own `performance.getEntriesByType('resource')`, not guessed — every number below is a real, browser-recorded timestamp.
**Why this file exists:** the founder reported the planner "takes a while" to load (~3–6s) and that creating a new job has a slow section. This is what actually happens, with numbers.

> **🔴 CORRECTION (same day, PERF-1 US-04): finding #2 below is WRONG.** There is no
> 14.3-second freeze. The "gap" ended exactly when the Planner link was clicked, and
> the click time was never read back — the 14 seconds were the auditor's own pause
> between page load and click, not the app. Re-measured with the click timestamp
> recorded inside the page: the first Planner request fires **~85ms** after the click,
> and the longest main-thread block is **100ms**. The separate screenshot timeout was
> on the port-4173 preview build's sign-in, a different app.
> **The real cause of the slow load** is in section 5 at the bottom: the Xano backend
> works through this account's requests roughly one at a time, so load time ≈ the total
> server work — and the board endpoint was doing work it never used.

---

## Headline findings, ranked by impact

1. **A job's detail modal fires ~10–20 network calls to show ONE job**, most of them exact duplicates of the same two endpoints, within milliseconds of each other.
2. ~~**A silent 14.3-second gap** where nothing happens on the network at all, between the Architectures list loading and the Planner tab's own data starting to fetch.~~ **Retracted — a measurement error; see the correction above and section 5.**
3. **Every initial data fetch on app load runs twice** (auth, architectures, workspace) — doubles backend load for no visible benefit.
4. **The "New job" panel shows a wrong message** ("This plan doesn't use any maps yet") while its own data is still loading, then corrects itself once the fetch finishes.

None of this required guessing — it's the literal sequence of requests the browser made, in order, with their durations.

---

## 1. Opening a job: the big one

Clicking one job card ("Turn-around · Moon bouncer repair") to open its detail modal produced this, measured from the moment of the click:

| Call | Count | Durations (ms) |
|---|---|---|
| `work_item/139` (the job itself) | 1 | 4,501 |
| `work_item/139/activity` | 1 | 789 |
| `work_item/139/links` | **2** | 2,816 / 4,408 |
| `work-item/139/lines` | **4** | 1,839 / 3,021 / 4,790 / 4,402 |
| `workspace/43/map`, `workspace/43/work_item` | 1 each | 396 / 892 |

That's **10 requests, 4 of them the exact same `lines` endpoint**, fired 2–18 milliseconds apart — not retries spread over time, but near-simultaneous duplicate calls. The modal should need at most 3 distinct calls (the job, its links, its lines); it made 7 duplicate ones on top of that.

**It got worse after closing the modal.** After clicking the X and opening a *different* panel ("New job"), two more waves of the *same job's* `links`/`lines` calls fired — 6 more requests, then 6 more again 2.4 seconds later — all for job 139, which was no longer on screen. (Confirmed this wasn't an ongoing poll: an 8-second idle window afterward produced zero network calls. It's a burst of late-arriving duplicate requests catching up, not a persistent leak — but it still means closing a modal doesn't cancel its in-flight work, so switching jobs quickly piles up concurrent requests for data nobody is looking at anymore.)

**Most likely cause:** something that fetches `links`/`lines` is mounted once per step/line row instead of once per job, or an effect with a missing dependency/cleanup re-fires on every re-render, and nothing cancels the previous request when the component unmounts (no `AbortController`). This is a frontend bug, not a backend capacity problem — the backend is just being asked to do the same work 4x.

**Fix shape:** fetch `links` and `lines` once at the job-modal level, pass down as props/context; add `AbortController` cleanup to every data-fetching effect so closing a modal actually stops its requests.

---

## 2. The 14.3-second dead gap

Timeline from the moment the Architectures page's own data arrived to the moment the Planner tab's first request went out:

| Event | Time (ms, page-relative) |
|---|---|
| `journey_architecture` responses arrive | 5,830 / 5,944 |
| *(nothing on the network for 14.3 seconds)* | — |
| `workspace` (Planner's first call) starts | 20,246 |

Nothing fetched in that window — this is pure client-side time: parsing, a heavy synchronous render, or something blocking the main thread. It lines up with a separate symptom hit during this audit: right after signing in, the tab was unresponsive long enough that a screenshot command (`CDP Page.captureScreenshot`) **timed out at 30 seconds**. That's not "slow network," that's the JS thread stuck.

**Fix shape:** this needs a CPU profile (React DevTools Profiler or Chrome's Performance panel) to find the actual hot function — not guessable from network timing alone. Worth checking first: anything that builds a large in-memory structure on route change (e.g., indexing every job/task client-side), and whether React StrictMode's double-invoke (see below) is compounding an already-expensive computation by running it twice.

---

## 3. Duplicate fetches on every initial load

| Call | Fired at (ms) | Durations |
|---|---|---|
| `auth/me` | 3,218 / 3,221 | 398 / 522 |
| `journey_architecture` | 3,970 / 3,972 | 1,860 / 1,973 |
| `workspace` (Planner) | 20,246 / 20,247 | 767 / 1,249 |
| `work_item`, `backlog_work` | 24,272–24,280 | 1,135–5,131 (each called twice) |

Every single one of these is called exactly twice, within 1–8ms of itself. This is the textbook signature of **React 18 StrictMode double-invoking effects in development** — it intentionally re-runs mount effects once to surface missing cleanup, and `vite --port=3000` is a dev server, so StrictMode is almost certainly on.

**This specific symptom will NOT appear in a production build** (StrictMode's double-invoke is dev-only). But two things are still worth knowing:
- If the founder's day-to-day usage is this dev server (not a built/previewed app), this is real, present-day wasted load on the Xano backend — twice the requests, which also means twice the chance of hitting a slow one.
- It doesn't explain the job-modal's 4x duplicate `lines` calls above — StrictMode only doubles (2x), and that section saw 4x and later 6x+6x waves. That part is a real bug independent of dev mode.

**Fix shape:** nothing to fix for StrictMode itself (it's working as intended, catching real cleanup bugs — including the one in §1). If day-to-day use is the dev server rather than a built app, consider running the built/previewed version (`npm run preview`) for anything resembling a real workflow — it won't double-fire and will generally be faster, since Vite dev mode serves ~123 separate unbundled module files instead of a handful of built chunks.

---

## 4. "New job" shows a wrong message while loading

Opening the New Job panel briefly displayed: *"This plan doesn't use any maps yet. Add one in Workspace Settings → Maps in this plan first — a job has to follow a published map."* This plan **does** have maps and jobs already — the message was shown while the `workspace/43/map` call (1.3s) was still in flight, before the real answer came back. It's a loading-state bug, not a data bug: the UI decided what to say before it had the data to say it with.

**Fix shape:** gate that message behind a real "still loading" check, not just "list is currently empty" (empty-while-loading and empty-because-there-really-is-nothing look identical today).

---

## What this does NOT establish

- No CPU profile was taken — the 14.3s gap's root cause is a strong hypothesis (main-thread block), not a diagnosed one. That needs a session with React DevTools Profiler attached.
- This was one cold run on one plan (workspace 43, job 139) with a handful of jobs. Numbers will vary with plan size; the *pattern* (duplicate calls, the gap) is what to fix regardless of exact milliseconds.
- Not tested: the Execution module, Reports, or Intelligent Layer's own map editor — this audit was scoped to Planner per the founder's request.

## Suggested next step

Fix §1 first (the duplicate `links`/`lines` calls) — it's the most clearly a bug, the most expensive in request count, and the most likely to be a quick, local fix (add request de-duplication or lift the fetch up one level) versus §2, which needs real profiling before anyone can safely touch it.

---

## 5. What actually makes the planner slow (PERF-1 US-04, re-measured)

### The load is one-at-a-time server work, not a browser problem

Opening Planner makes 4 requests: the plan list, the board, the jobs list, and the
Unscheduled backlog. Timed directly against Xano from the signed-in page:

| Request(s) | Each alone | All at once (wall time) |
|---|---|---|
| board + backlog | 3.2s, 2.3s | **5.8s** — the sum, not the max |
| board + backlog + jobs | 3.2s, 2.3s, 0.8s | **7.5s** |

The backend works through this account's requests roughly serially. **So starting
requests earlier or in parallel cannot make the planner faster** — this was tried and
measured (it made the board appear *later*, because it then shared the queue with the
lists), and reverted. Load time ≈ the total server work. Only two things help:
**fewer requests**, and **cheaper requests**.

### What was fixed

- **Fewer requests.** React StrictMode (dev mode, i.e. `localhost:3000`) mounts every
  component twice, so the plan list, jobs list and backlog were each requested twice —
  and on a one-at-a-time backend, every duplicate is real queued seconds. Identical GETs
  already in flight now share one call (`src/perform/inflight.ts`). Planner open went
  from 6–7 requests to **4**. Nothing is cached, so no stale-data risk.
- **Cheaper board.** Half the board's server time (1.5s of ~3s) was one function,
  `planner/job_step_hydration`, running the item-estimate calculation for **every job
  in the plan** although it only ever shows **scheduled** steps. The board got ~0.35s
  slower with every job added, scheduled or not. It now estimates only jobs with a step
  on a day. Output proven **byte-identical** on all 14 plans with jobs.

| Plan | Hydration before | After |
|---|---|---|
| 38 (nothing scheduled) | 3.21s | **0.21s** |
| 43 (8 scheduled steps) | 1.50s | **0.90s** |
| All 14 plans, one sweep | 37.5s | **15.5s** |

### Click → Planner fully loaded (workspace 43, a small plan)

| | Board visible | Everything loaded |
|---|---|---|
| Before | 5.0s | 8.4s |
| After (two runs) | 5.2s / 3.9s | 8.4s / 6.6s |

Honest reading: on this 2-job plan the gain is inside Xano's own run-to-run noise
(±1.5s). The fixes stop the planner from getting *slower as the plan grows*; they don't
make a small plan dramatically faster.

### What's left, in order of expected payoff

1. **The backlog endpoint (559, ~1.6–3.8s)** has the same "estimate every job" waste,
   **and** loads the *entire* schedule-link table — every account's rows — with no
   filter, so it slows down as the whole customer base grows. Recorded as US-PERF-1-06.
2. **The board's remaining ~2s**: `derive_tasks` runs once per day on the plan
   (~0.15s each) — fine for a week, linear in days shown.
3. **Run the built app, not the dev server, for real use.** `npm run build` +
   `npm run preview` serves a handful of bundled files instead of ~123 separate modules,
   and has no StrictMode double-mounting at all.
4. **The Architectures page** (journey-map client, `xano.ts`) still double-fetches
   `auth/me` and `journey_architecture` in dev — same in-flight sharing would apply to
   that client too.
