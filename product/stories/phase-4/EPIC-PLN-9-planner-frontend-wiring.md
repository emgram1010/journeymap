# PLN-9 — Planner Frontend Wiring

**Epic ID:** PLN-9
**Feature:** The planner app (`webapp/planningFrontendv2`) talks to the real backend (PLN-1…PLN-8, PLAN-1, SCHED-1, LIVE-1) instead of `localStorage`.
**Status:** DRAFT — scoped, not built. Written up for review before any code changes, per the founder's own build protocol. Not yet a numbered step in `README.md`'s build order; add it there once approved.
**Depends on:** PLN-1…PLN-8 ✅, PLAN-1 ✅, SCHED-1 ✅, LIVE-1 ✅ (all backend-complete). APP-1 ✅, as the first real consumer of the published-day shape this epic also writes to.
**Goal:** A planner opens the real app, creates a plan from a template, schedules real work onto real agents' real days, and publishes — and everything a performer sees in `/perform` came from an actual plan a human built in this UI, not from a script.

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

## Open questions for the founder

1. **Where should this app live?** Folded into `protype-2` next to APP-1 (one deployable, like the session's own precedent), or kept as its own app with its own URL? Affects auth wiring (shared login vs. separate) and is cheap to decide now, expensive to change later (`learning-fixes.md` flag #2).
2. **Is the HTTP-client unification (Finding 6) worth doing as part of this epic**, or should PLN-9 build its own third client to avoid touching APP-1's code at all? Recommended: unify, since it removes a maintenance seam, but it is a real scope increase.
3. **Model for this epic**: given its size (the biggest single wiring task in the project) and that it touches the most existing, already-proven endpoints, this looks like a Sonnet build with an Opus review pass after, same pattern as PUB-1/LOG-1 — but it is closer to "a lot of surface area" than "a lot of risk", so Sonnet throughout is also defensible. Founder's call once the story count is final.

## Test Results

_Not started. This file is a scoping document, not a build record._
