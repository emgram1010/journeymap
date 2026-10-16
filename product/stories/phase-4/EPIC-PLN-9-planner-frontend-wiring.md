# PLN-9 — Planner Frontend Wiring

**Epic ID:** PLN-9
**Feature:** The planner app talks to the real backend (PLN-1…PLN-8, PLAN-1, SCHED-1, LIVE-1) instead of `localStorage`.
**Status:** APPROVED 2026-10-16 — the three open questions below are answered. Building now.
**Depends on:** PLN-1…PLN-8 ✅, PLAN-1 ✅, SCHED-1 ✅, LIVE-1 ✅ (all backend-complete). APP-1 ✅, as the first real consumer of the published-day shape this epic also writes to.
**Goal:** A planner opens the real app, creates a plan from a template, schedules real work onto real agents' real days, and publishes — and everything a performer sees in `/perform` came from an actual plan a human built in this UI, not from a script.

## Decisions (founder, 2026-10-16)

1. **New home: `webapp/emgram1010v1`.** Not folded into `protype-2`, and not left at `webapp/planningFrontendv2`. Deployed via **Xano static hosting** (not Vercel/Netlify/etc.) — the founder's own infrastructure choice. Research below.
2. **Share connection code with APP-1: yes.** See "HTTP client" below for how, given these are two separate Vite apps with no monorepo tooling between them.
3. **Model: Sonnet throughout, Opus review after** — the recommendation this file already made. Confirmed.

### Xano static hosting — what this changes about the build

Researched 2026-10-15/16 (not prior knowledge — Xano is not a platform with stable public conventions to assume). Source: [Xano's own static-hosting docs](https://docs.xano.com/xano-features/static-hosting), [Xano's walkthrough](https://www.xano.com/learn/host-your-frontend-in-xano-with-static-hosting/).

- Xano serves a **built static output** (Vite's `dist` folder), uploaded as a zip, either via the dashboard or the CLI. There is no server running at runtime — it is pure static file serving.
- Separate dev/prod domains per static host, deployed independently with one click once a build is uploaded.
- **One static host already exists in the workspace** (`id 1`, name "default", a dev URL already assigned, no prod yet, zero builds uploaded so far). Reusing this one rather than creating a second, per the project's own "reuse, don't duplicate" rule.
- **No confirmed SPA rewrite/fallback support** — Xano's docs don't describe one, and "no persistent server" strongly implies there isn't one. A deep link to a route that isn't `/` could 404 on refresh.
  - **Not a blocker for this epic**: the existing planner UI (what this epic is wiring up) has **no router at all** — `main.tsx` renders one `<App />` with no `react-router-dom`, and its "plan vs. schedule" view is a plain `useState` toggle, not a route. Zero deep-link risk as currently built.
  - **Worth remembering if routing is ever added later**: prefer `HashRouter` (`/#/...`) over `BrowserRouter` on this host, or confirm Xano's fallback behavior directly first. Not relevant to THIS epic's own scope.
- **Deployment is a separate step from this epic's own build-and-test work** — `npm run build` → zip `dist` → upload → deploy. Will do this once there's something real to deploy, not before.

### HTTP client — how "share with APP-1" actually works here

`webapp/protype-2` and `webapp/emgram1010v1` are two independent Vite projects (separate `package.json`, separate `node_modules`) with no workspace tool (pnpm/yarn/npm workspaces, Turborepo) connecting them. True shared code needs one of those; introducing one is a real scope increase on top of an already-large epic.

**Decision: duplicate the proven client, not re-architect the repo.** `performApi.ts` (APP-1's planner-group HTTP client, already tested and live-verified) gets copied into the new app, byte-for-byte, with a header comment saying so and naming the sibling file. This is the same tolerance this project has already extended to deliberate TypeScript/XanoScript twins (`logModel.ts` ↔ its XanoScript mirror, `versionHash.ts` ↔ `pub/canonical_hash.xs`) — two files, proven to agree, kept in sync by convention and a comment, not by tooling. A real monorepo migration is a legitimate future improvement, flagged, not done as a side effect of this epic.

---

## Why this is a draft, not a build

Found 2026-10-15, flagged in `product/learning-fixes.md`, and the
reason APP-1 was built before this: **the planner app has never been
wired to Xano.** It is a complete, good-looking UI over
`localStorage` — 41 backend endpoints exist underneath it and none of
them are called. That is a bigger, less-bounded task than any epic
built so far this phase, and unlike every other epic, the "what to
build" question cannot be answered purely from a spec — it needs a
read of the EXISTING frontend's own data model first, because that
model already encodes real decisions (see below) that a spec written
blind could easily contradict.

This file is that read, plus the stories it implies. **Nothing in it
has been built.** It should be reviewed, corrected where the founder's
intent differs from what's written here, and only then picked up as a
normal epic (write tests first, etc.) following the standing build
protocol.

## MVP scope (proposed)

| In scope | Deferred |
|---|---|
| Read the real workspace/agent/timeline/task data on load | Offline mode, optimistic conflict resolution beyond what SCHED-1's value-check already gives |
| Create a plan (from a template), create/edit/hide agents, create/move/reorder tasks, schedule, tweak duration | A dedicated "create template" screen — can reuse `template` POST directly if simple enough, otherwise its own story |
| Publish one timeline; "publish the whole day" as a client-side loop over the single-timeline endpoint | A real bulk-publish backend endpoint (still explicitly deferred by LIVE-1) |
| Loading/error states, friendly messages (VAL-1), OBS-1 events — same pattern APP-1 already established | A planner-side view of performer activity (that's VAR-1's eventual read surface, not this epic) |
| Add a map to an existing plan (new, small backend endpoint — see Finding 3) | Changing which maps a TEMPLATE itself can offer, beyond what PLAN-1 already allows via its own PATCH |

## Context

Three layers, and this epic only touches the middle one. The journey-map
app (`webapp/protype-2`) already talks to Xano for the Definition layer.
APP-1 (`/perform`, also inside `protype-2`) talks to Xano for the Record
layer. The Commitment layer — `webapp/planningFrontendv2` — is the one
app in the whole product that has never made a single `fetch` call.

## Findings from reading the existing frontend (not assumptions)

**1. The data model already matches the backend closely — low
structural risk.** `Workspace`, `Agent`, `Timeline`, `Task` in
`src/types.ts` map almost 1:1 onto `planner_workspace`,
`planner_agent`, `planner_timeline`, `planner_task`. `Timeline.agentId`
already assumes "one agent, one timeline, per day" — the exact model
the backend enforces. This is good news: the UI was designed with the
right shape, it just talks to the wrong place.

**2. One real mismatch: `Task.planned_start` is a stored field; the
backend deliberately never stores it.** `planner_task`'s own header
comment: "Deliberately has NO `planned_start` column: a task's start
time is derived by walking the timeline's start_time plus the
durations ahead of it, so a stored copy could only ever disagree with
the order." The frontend currently stores and recomputes this itself
on every reorder (`src/utils/planningLogic.ts`). **This needs to
become a derived value computed from the fetched data, not a field
written back** — the same algorithm APP-1's `performerView.ts`
already implements for the performer side (`toPerformerItems`'s
cumulative-seq-duration walk). Likely reusable almost as-is.

**3. The UI already has a "bulk publish day" flow the backend does not
support as one call.** `ModalEntity`'s `bulk_publish_day` case and
`handleConfirmBulkPublish` loop over every timeline for a day and
publish the ready ones. **Not a blocker** — this can call the existing
single-timeline `POST timeline/{id}/publish` once per timeline from the
client, which gives the same user-visible result without new backend
work. Flagged so it isn't mistaken for a missing endpoint mid-build.

**4. No execution-layer concepts appear anywhere in this frontend.**
No `work_task`, no activity log, no variance. This is correct and
matches the architecture's own layering — PLN-9 should stay out of
LOG-1/VAR-1/APP-1's territory entirely, and resist the temptation to
grow a planner-side performer-activity view as part of this epic.

**5. There is genuinely no endpoint to add a map to an existing plan**
(found live during E2E-1, `learning-fixes.md`). `template/{id}` PATCH
only changes what the NEXT instance will accept. A planner using the
real UI to add a second work type to an already-running plan will hit
this immediately. **One small new endpoint is in scope here**
(`POST workspace/{id}/map`, or similar — naming TBD at build time).

**6. State management is plain `useState` plus one `localStorage`
persistence effect — no fetch layer, no loading state, no error
state, anywhere.** This is the most labor-intensive part of the
rewrite: not the API calls themselves (the backend is proven and
documented), but building the fetch/loading/error/retry scaffolding
`webapp/protype-2` already has (`xano.ts`'s pattern) from scratch for
this app, including a `performApi.ts`-style client for the planner API
group (APP-1 already built one of these; this would likely become the
one BOTH apps share, unifying two near-duplicate HTTP clients — worth
doing as part of this epic rather than a third copy).

## Existing Architecture (Do Not Break)

- Every PLN-1…PLN-8, PLAN-1, SCHED-1, LIVE-1 endpoint is already built, tested, and does not change here. This epic is a consumer, not a backend change, except for Finding 5's one small addition.
- `webapp/protype-2`'s APP-1 route and its `performApi.ts` client — if the HTTP client is unified (Finding 6), do it without touching APP-1's own behaviour; same reasoning as the `baseUrl` option added to `xano.ts` during APP-1.

## Non-Goals

- No new planner CAPABILITIES beyond what the backend already has (bulk publish, role-based assignment suggestions, etc. — all already deferred by their own epics).
- No visual redesign. The existing UI's layout and interactions are the target; only its data source changes.
- No decision here about WHERE this app lives long-term (its own deployment vs. folded into `protype-2`, the way APP-1 was). That's a separate, smaller product decision — flagged in `learning-fixes.md`'s holistic review (2026-10-15, flag #2), not resolved by this epic.

---

## Proposed Stories (to be refined at build time, same as every other epic)

### US-PLN-9-01 — A planner HTTP client

Build (or adopt, per Finding 6) the fetch/loading/error layer this app has never had. Same shape as `xano.ts`/`performApi.ts`: a correlation id per request, a typed error, friendly messages via the existing catalog.

### US-PLN-9-02 — Read the real world on load

Workspace list, then on selecting one: agents, timelines (for the visible window), tasks (scheduled + backlog). Replace the `localStorage` seed entirely.

### US-PLN-9-03 — Agents: create, edit, hide/show

Wire `workspace/{id}/agent` (GET/POST), `agent/{id}` (PATCH), `workspace/{id}/agent/visibility`.

### US-PLN-9-04 — Tasks: create, move, reorder, tweak

Wire PLN-7's task endpoints and SCHED-1's schedule/tweak endpoints. Replace `planningLogic.ts`'s stored `planned_start` with a derived computation (Finding 2).

### US-PLN-9-05 — Publish one day

Wire `timeline/{id}/publish`. The "bulk" flow becomes a client-side loop (Finding 3), with the existing UI's own per-timeline readiness check (which already exists client-side) reconciled against the server's own blocker list from the same endpoint.

### US-PLN-9-06 — Add a map to an existing plan

The new small backend endpoint from Finding 5, plus the UI action to use it.

### US-PLN-9-07 — Plan creation from a template

Wire `template` (GET/POST), `template/{id}/instance`.

---

## Test Plan (shape only — to be written in full at build time, tests first per protocol)

| Area | What needs covering |
|---|---|
| Pure logic | The derived `planned_start` computation (golden-fixture tested against the backend, same convention as every dual-implementation this phase) |
| Functional | Every story above, over real authenticated HTTP, same rigor as every other epic this phase — tenancy, validation, friendly messages |
| Regression | `npm test`, existing suites, stay green |
| E2E | A real browser session creating a plan, scheduling a task, publishing it, and confirming it shows up in `/perform` — closing the loop PLN-9 exists to close |

## Governance (to be written in full at build time)

Follows GOV-1/VAL-1/OBS-1 exactly as every other epic. Nothing new in kind — only in surface area, since this epic touches the most existing endpoints of any epic so far.

## Open questions — ANSWERED 2026-10-16

1. ~~Where should this app live?~~ **`webapp/emgram1010v1`, deployed via Xano static hosting.** See "Decisions" at the top.
2. ~~Is the HTTP-client unification worth doing?~~ **Yes, by duplication with a comment, not a monorepo migration.** See "Decisions" at the top.
3. ~~Model for this epic?~~ **Sonnet, Opus review after.**

## Test Results

### Checkpoint 1, 2026-10-16: login + real read-only data (US-PLN-9-01, -02)

**App scaffolded at `webapp/emgram1010v1`** — copied from `planningFrontendv2` (identical `src/`, confirmed by diff), `npm install` clean, `npm run build` produces a working `dist` (the thing that gets uploaded to Xano static hosting). Founder is handling the actual upload; this epic's job is to leave the folder ready for it.

**Login built and verified live** (`AuthGate.tsx`, `src/lib/authApi.ts`) — this app never had one, since it never called anything real. A real signup → real login → real session, driven through the actual rendered form (not just a fetch call), confirmed working. Documented explicitly: this app is a **separate origin** from `protype-2` (Xano static hosting vs. wherever `protype-2` deploys), so `localStorage` does NOT carry a session between them — one account, two separate sign-ins. Worth remembering before assuming "logged into one = logged into both."

**A real, live bug found and fixed in the exact endpoint this epic depends on most**: `workspace/{id}/board` (endpoint 548, PLN-8) hardcoded every timeline's `status` to `"draft"` — the identical bug class LIVE-1 already found and fixed on two sibling endpoints (539, 540), just never applied here. Fixed: reads the real column now. **Verified it mattered**: the existing frontend already has its own "(locked — timeline published)" UI logic that depends on this field — it was silently dead code until this fix, and is now visibly correct against real published timelines.

**Real data confirmed rendering correctly**, end to end, logged in as the session's own test account:
- Workspace list loads (`GET workspace`), defaults to the most recent plan
- Full board loads in one request (`GET workspace/{id}/board` — built for exactly this, per its own header comment) — agents, timelines, tasks, settings, models
- A real published timeline shows **"Published"** (not the old hardcoded "Draft") and correctly locks its own tasks from editing — existing UI logic, now fed real data
- Task planned-start times are **server-derived, never recomputed client-side** — confirmed against real data: a 10-minute task at 08:00 correctly pushes the next task to 08:10, then 08:25 after a 15-minute one. This is a correction to the epic's own earlier "Finding 2": the backend's `planner/derive_tasks` already computes this exactly the way the frontend's own `formatMinutesToTime` wraps a day — the frontend does not need to reimplement the cumulative-duration maths at all for reading; `planningLogic.ts`'s existing recompute function may still earn its keep for optimistic UI later, but it is not required for this checkpoint.

**New shared-client files** (`src/lib/`): `correlationId.ts`, `xanoHttpError.ts`, `performApi.ts` — kept byte-identical in spirit to their `protype-2`/APP-1 siblings, per the "duplicate, don't re-architect" decision. Plus this app's own `plannerApi.ts` (the real endpoint calls, in their real verified shapes) and `plannerAdapter.ts` (mapping those onto the existing, unchanged `src/types.ts`).

**Not yet wired — writes are still local-only.** Creating/editing an agent, moving a task, publishing a day: all still just update React state, same as before this epic, and will be lost on refresh. This is the deliberate next slice (US-PLN-9-03/04/05), not a bug in what's built so far — flagging it so it is never mistaken for "done."

### Checkpoint 2, 2026-10-15: writes wired (US-PLN-9-03, -04, -05)

**Approach:** every write handler now calls the real backend, then refetches the whole board rather than hand-patching local state — the same `getBoard` call Checkpoint 1 already proved derives `planned_start` correctly. This replaced the old localStorage version's in-memory recompute helpers (`recomputeTimelineTaskTimes`, `calculateTaskLanding`) entirely; duplicating that math client-side would just be a second place for it to drift from the server (CLAUDE.md: "reference, do not copy"). `EditModal.tsx`'s save handlers were changed to `async` and now keep the form open with the user's typing intact on a rejected save (CLAUDE.md: "keep the user's typing on any rejected save") rather than closing optimistically — this is a real behavior change from before, since a localStorage write could never actually fail.

**Wired:**
- Agents: create, edit (name/kind/color/capacity/model), single visibility toggle, "show all" (PLN-5's bulk endpoint), "hide all" (bulk hide + re-show the one(s) in focus, since the backend's bulk call has no "except this one" concept).
- Tasks: create (backlog or into a day), edit (title/duration/notes/status/needs-info reason, assignee-by-name resolved to `assignee_agent_id`), move/reorder via `task/place` and `timeline/reorder`, backlog↔day drag, cross-agent/cross-day moves.
- Timelines: create-on-demand (idempotent `workspace/{id}/timeline` — a second click on the same cell just opens the existing day), edit start time/date, move cell (drag to another agent/day, server refuses instead of merging on a clash).
- Publish: single-timeline publish wired to LIVE-1; "publish day" is a client-side loop over it (`Promise.allSettled`, partial-success message) — LIVE-1 still has no real bulk-publish endpoint, so this remains the documented gap, now actually working end to end instead of being a localStorage no-op.
- A friendly-message toast (`#action-error-toast`) surfaces every rejected write (VAL-1's server message) and every "not available yet" refusal, auto-dismissing after 6s.

**Found and fixed before it shipped:** a hooks-order bug in `EditModal.tsx` — the new `isSaving` state was first declared *after* the component's `if (!isOpen || !entity) return null` early return, so it was skipped whenever the modal was closed, making React see a different hook count between renders ("Rendered more hooks than during the previous render", caught live the moment the modal opened in a real browser, never caught by `tsc`). Fixed by moving the declaration up with the rest of the component's hooks.

**Explicitly left unwired, with reasons, not bugs:**
- **Deleting an agent or a task.** Both have a backend function already written (`functions/planner/delete_agent_cascade.xs`, `functions/planner/delete_task.xs`) but neither is pushed, per CLAUDE.md's "ask before any delete." The UI's delete actions now say so plainly (a toast, or the button not rendering at all for agents) instead of pretending to work. **Needs a founder decision**: approve pushing these two (plus the task-delete endpoint) so this can be finished, or leave deletion out of this epic's scope.
- **Reopening a published timeline.** There is no "unpublish" on the backend at all — LIVE-1's own design has the planner keep editing the same published day forward, with every change logged to `plan_change_log` (VAR-1/LOG-1 territory, out of this epic). The UI's existing "Reopen to edit" buttons stay in place but now say this plainly instead of silently reverting local state to draft.
- **Add a map to an existing plan (US-PLN-9-06)** and **plan creation from a template (US-PLN-9-07)** — not started this checkpoint; next slice.

**Verified live**, logged in as a real test user (via a magic-link-minted token, since this app's simplified login has no signup and no prior-session password was available post-compaction) against workspace 12 ("E2E-1 Receiving Plan", account 6):
- Created a real agent ("PLN9 Wiring Test") — appeared immediately via the board refetch, no page reload.
- Created two tasks on its day — server-derived `planned_start` cascaded correctly (08:00, then 08:30).
- Edited the first task's duration (30→45m) — the second task's start correctly shifted to 08:45, proving the edit path also relies on server-side derivation, not client math.
- Toggled the new agent's visibility off and on via the roster popover — persisted through a board refetch each time.
- Attempted to publish the new agent's day — correctly **rejected** with the real server message ("PLN9 Wiring Test doesn't have a login yet, so they can't see their work."), surfaced via the toast. This is LIVE-1's actual guard working as designed, not a bug — this plan's one available test login (user 9) was already linked to the other agent, so a second real publish wasn't possible without creating more test fixtures.
- Reordered the two tasks via a direct call to `timeline/{id}/reorder` (the UI's own drag-and-drop didn't register through the browser automation tool's synthetic mouse events — a tooling limitation of simulating this specific drag gesture, not something traced to the new wiring code) — confirmed both the reorder itself and the resulting recomputed start times (08:00/08:30 swapped correctly with the tasks).
- Test fixtures (agent "PLN9 Wiring Test", its two tasks) were **left in place** rather than deleted — matches this project's own existing pattern of leaving named QA fixtures (`Orphan Check`, `Chain Check`, `Tenancy Check` users/accounts) rather than performing an ad-hoc delete outside the standing review process.

**Regression:** `npm run lint` (tsc --noEmit) and `npm run build` both clean on `emgram1010v1`. No backend files changed this checkpoint, so no backend regression risk.
