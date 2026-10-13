# APP-1 — Performer App

**Epic ID:** APP-1
**Feature:** A simple app where the person doing the work sees today's items and taps Start, Done or Blocked.
**Status:** Planning
**Depends on:** LIVE-1, LOG-1
**Goal:** A logged-in performer sees only the items from timelines **published to live** for them, in order, with planned time, expected duration and status, and can record progress with the fewest taps possible. The MVP requires a connection (offline is a future item).

---

## Context

Performers are the people (later AI agents) who do the scheduled work. They do not build plans and never report variance; the app captures start and end from their taps (LOG-1). Phase-3 `planner_agent` has no login link, so a nullable user link is added.

## Existing Architecture (Do Not Break)

- Phase-3 agents and timelines; LIVE-1 publications; LOG-1 events.
- Auth: existing `user` table and token auth.

## Non-Goals

- No offline mode. No pause button. No photos/signatures/notes beyond an optional short note. No push notifications. No plan editing.

---

## Stories

### US-APP-1-01 — Link a login user to an agent

- The column `planner_agent.user_id` is added by P3A-1 (moved there to remove a circular dependency with LIVE-1). This story adds the planner's agent-form field to set it.

**Acceptance:** one user per agent; an agent without a user cannot receive published work (LIVE-1 blocker).

### US-APP-1-02 — "My work today" API

**File:** `apis/.../perform_today_GET.xs`

- Returns the caller's items from `plan_publication.snapshot` for their agent(s), for a date (default today), ordered by planned start, joined with **live task status**.
- Never reads the live plan. Planner changes after publish do **not** appear (decision D-23).

**Acceptance:** unpublished timelines never appear; moved/removed tasks still show as published.

### US-APP-1-03 — Performer view

**Files:** `webapp/protype-2/src/perform/` (new route `/perform`), `performerView.ts`, `performerView.test.ts`

- Responsive list: planned start, title, expected duration, status. Block items show their stages as one item with sub-steps.
- Detail view: task text, input, output, done-when.

**Acceptance:** works at phone width with large tap targets; empty state when nothing is published.

### US-APP-1-04 — One-tap actions

- Actions available depend on status (`availableActions(status)`): Start; Done (also allowed without Start, D-38); Blocked (pick one of the fixed reasons); Skip; Reopen (for done/skipped).
- Failed diagnostic events while offline are buffered and sent later (OBS-1, US-OBS-1-11); user actions are never queued.
- Optimistic update with rollback on failure; each tap sends a unique `client_event_id`.
- If the connection is down, show a clear "connection required" message and do **not** queue.

**Acceptance:** double taps do not double-record; failures roll back visibly.

### US-APP-1-05 — Access control

- A performer can read and act only on their own published items. Any other task id is denied.

**Acceptance:** cross-user and cross-account access denied.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-APP-1-01 | Unit | `availableActions('not_started')` | Start, Done, Blocked, Skip |
| UT-APP-1-02 | Unit | `availableActions('in_progress')` | Done, Blocked, Skip |
| UT-APP-1-03 | Unit | `availableActions('blocked')` | Unblock, Skip |
| UT-APP-1-04 | Unit | `availableActions('done')` / `'skipped'` | Reopen only |
| UT-APP-1-05 | Unit | `toPerformerItems(snapshot, statuses)` | Ordered by planned start; block sub-steps nested |
| UT-APP-1-06 | Unit | Item removed from the live plan but present in the snapshot | Still returned |
| UT-APP-1-07 | Unit | `newClientEventId()` twice | Different values |
| UT-APP-1-08 | Unit | Optimistic reducer: success and failure | Applies, then reverts on failure |
| FT-APP-1-01 | Functional (`workflow_tests/22_performer_today.xs`) | Published timeline for the user's agent | Items returned in order |
| FT-APP-1-02 | Functional | Draft timeline | Not returned |
| FT-APP-1-03 | Functional | Planner moves a task after publish | Performer response unchanged |
| FT-APP-1-04 | Functional | User B requests user A's task | Denied |
| FT-APP-1-05 | Functional | User with no agent | Empty list |
| FT-APP-1-06 | Functional | Duplicate `client_event_id` | One log row |
| E2E-APP-1-01 | UI | Phone-width viewport: list renders, actions reachable | Pass |
| E2E-APP-1-02 | UI | Start → Done | Status updates; times recorded |
| E2E-APP-1-03 | UI | Blocked | Reason picker shows the fixed four options |
| E2E-APP-1-04 | UI | Network offline | "Connection required" shown; no queued action |
| E2E-APP-1-05 | UI | Double tap Start | One event |

**Completion gate:** all pass.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity:** `planner_agent.user_id → user` (from P3A-1) is nullable, indexed and **unique per plan** (one login per agent in a plan); removing a user's access never deletes history. All reads come from the frozen publication snapshot plus live task status.

**Validation and friendly messages (what a performer sees)**

| Situation | Friendly message | Code |
|---|---|---|
| Nothing published for today | "Nothing is scheduled for you today." (not an error) | — |
| No connection | "No connection. Reconnect to continue. Your last tap was not saved." | `E-APP-001` |
| Tap not saved | "That didn't save. Tap again. Reference: {ref}." | `E-APP-002` |
| Task not yours / not available | "You can't change this step." | `E-APP-003` |
| Session expired | "Please sign in again." | `E-APP-004` |
| Unexpected screen error | "Something went wrong. Reference: {ref}. We've recorded it." | `E-APP-005` |

The app never shows stack traces, technical words or raw error text.

**Events logged** (`feature = APP-1`, through the OBS-1 client helper): `load_today` (`success` with item count; `failure`), `action_tap` (`success`/`failure`), `client_error` (unhandled errors with screen name and Reference). Events are de-duplicated and rate-capped.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-APP-1-G01 | Unit | Error-to-message mapper covers every `E-APP` code | Pass |
| UT-APP-1-G02 | Unit | Client error reporter de-duplication and cap | Pass |
| FT-APP-1-G01 | Functional | Unique `user_id` per agent | Second link rejected |
| FT-APP-1-G02 | Functional | Server returns 500 on load | Friendly state; `failure` event with Reference |
| E2E-APP-1-G01 | UI | Forced 500 on a tap | Friendly message with Reference; no raw error; event logged |
| E2E-APP-1-G02 | UI | Session expiry | "Please sign in again" |
| E2E-APP-1-G03 | UI | Unhandled front-end exception | Friendly screen; `client_error` event |

## Test Results

_Not yet run._
