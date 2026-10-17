# APP-2 — Execution Sessions (Mobile)

**Epic ID:** APP-2
**Feature:** The Execution layer becomes a mobile-first, session-based app: a day summary of sessions, each session opened and worked step by step, every status change made by a button that stamps the time.
**Status:** Planning
**Depends on:** APP-1 ✅, LOG-1 ✅, LIVE-1 ✅, PLN-9 ✅ (Execution in the main nav)
**Model:** Sonnet for the build; Opus review after (it touches the status engine's client side).
**Goal:** A person on the move opens the app on a phone, sees today's sessions in order, opens one, works its steps with large one-handed buttons, adds notes, and never types a time.

---

## Context

APP-1 proved the record layer end to end, but its screen is a **flat list of tasks for the day**. People think in **sessions**: one session is one instance of a business flow (one job), and the steps inside it are the work. Today's screen has no grouping, no job name and no notes, so at any real volume the same step names repeat with nothing to tell them apart.

Found in review, 2026-10-17: the data model already matches the session model. The gaps are one missing field set in the API, one missing read, and the screen itself.

| Concept | In the data | On screen today |
|---|---|---|
| Session | a job (`work_item`) with its steps (`work_task`) | not shown |
| Session order | planned start of its first step | not shown |
| Start / end times | stamped server-side on every tap (`activity_log.occurred_at`) | works |
| Status | derived from logged events — never typed | works (inline buttons) |
| Notes | `activity_log` `note` events are accepted | no input, no read-back |
| Where this came from | job → map version → map; step → day → plan | not shown |

## Existing Architecture (Do Not Break)

- **Status is never set directly.** It is the result of an event (`started`, `completed`, `blocked`, `unblocked`, `skipped`, `reopened`). The status engine (LOG-1) stays the only thing that derives it. No status dropdown anywhere.
- **Times come from the server**, not the device clock (`occurred_at`). The client never sends a time.
- **One tap = one row.** `client_event_id` stays unique per tap; double taps must not double-record.
- **The performer reads the frozen publication** (LIVE-1, decision D-23), plus live status. Planner edits after publishing do not change what the performer was told.
- APP-1's endpoints, events and error codes keep working; this epic extends them.

## Non-Goals

- Offline mode (still a future item — the app needs a connection).
- Redesigning the Planner or the journey-map editor for phones. They stay desktop/tablet tools.
- Photos, signatures, barcode scanning, or any capture beyond notes.
- Map-level "what is live on this version" view (separate follow-up).
- The Planner's blank titles for job-derived steps (same root cause, separate story — see "Follow-ups").

## MVP scope

| In scope | Deferred |
|---|---|
| US-APP-2-01 … US-APP-2-09 | Session pause/resume, reorder by the performer, offline queue, attachments |

---

## Stories

### US-APP-2-01 — Session identity in the Execution payload *(back end — the blocker)*

**Files:** `apis/planner/567_perform_today_GET.xs`, `functions/perform/hydrate_statuses.xs`

Every item returned by `perform/today` carries its **provenance**, as one small shape:

```
session: {
  work_item_id, title,                 // "Quote for the Nguyen wedding"
  flow_title, version_no,              // the journey map + pinned version
  plan_id, plan_name                   // the plan it was scheduled in
}
```

Defined once so the Planner and any later screen can return the same shape rather than each inventing its own.

**Acceptance:** every item has a `session`; two jobs from the same flow on the same day are distinguishable; values come from the pinned version, not the live map; no extra query per item (one join per container).

### US-APP-2-02 — Notes read-back *(back end)*

**Files:** `functions/perform/hydrate_statuses.xs` (or a small `work_task/{id}/notes` GET)

Notes can already be written (`event_type = note`). Return them, newest first, with author and server time.

**Acceptance:** a note written from the step screen appears on reload; notes are append-only (never edited or deleted); another account's notes are never returned.

### US-APP-2-03 — Today: the session list

**Files:** `webapp/protype-2/src/perform/` — `TodayScreen.tsx`, `sessionModel.ts` (pure grouping/ordering), tests

- One card per session, ordered by the planned start of its first step.
- Each card: planned start time · job title · flow name · step count · expected total · progress ("1 of 3 done") · session status.
- A day summary at the top: sessions today, done, remaining.
- The next session to work is visually marked.

**Acceptance:** sessions group correctly when several jobs share a day; order matches the plan; empty state when nothing is published.

### US-APP-2-04 — Session screen

**Files:** `SessionScreen.tsx`

- Header: job title, flow name, plan (the provenance).
- Steps in order, each showing time · name · status only.
- The **next step is highlighted**; the others stay visible and tappable (order is a guide, not a lock).
- **Start session** = start of the first step (see decision D-1); **Finish session** once every step is done or skipped (see D-2).

**Acceptance:** starting the session records the first step's start; finishing returns to Today; progress updates without a reload.

### US-APP-2-05 — Step screen

**Files:** `StepScreen.tsx`

Full-screen view of one step:
- Status badge at the top.
- Instructions and "done when", large and readable.
- Expected duration; actual elapsed time once started.
- Notes list plus a note box (US-APP-2-06).
- Action buttons at the bottom (US-APP-2-07).

**Acceptance:** opens from the session screen and returns to it; shows the same text the performer was given at publish time.

### US-APP-2-06 — Notes on a step

- Text box plus Save; posts a `note` event.
- Previous notes listed underneath.
- Keeps the typed text if the save fails.

**Acceptance:** blank notes are rejected in the UI and by the server; over-long notes get a friendly message; the typing survives a failed save.

### US-APP-2-07 — Status by buttons, never typed

Only the buttons that apply to the current status appear:

| Status | Primary | Secondary | Result |
|---|---|---|---|
| Not started | **Start** | Skip | → In progress |
| In progress | **Done** | Blocked | → Done |
| Blocked | **Resume** | Skip | → In progress |
| Done | — | Reopen | → In progress |
| Skipped | — | Reopen | → Not started |

- **Blocked** asks for a reason (waiting on someone · missing information · something went wrong · other) plus an optional note.
- **Done without Start** is allowed and recorded honestly (LOG-1 already supports it).
- **Skip** — reason or not: see decision D-3.

**Acceptance:** the visible buttons always match the status the server returns; a rejected tap leaves the screen in its previous state with a friendly message; double taps record once.

### US-APP-2-08 — Mobile-first layout

Applies to every APP-2 screen:
- Designed at **375 px wide first**; works up to desktop.
- Tap targets at least **44 × 44 px**; primary actions in the **bottom third** of the screen (one-handed).
- Text at least 16 px for instructions; no hover-only interactions.
- No horizontal scrolling at phone width.

**Acceptance:** Playwright run at 375 × 812 and 390 × 844 shows no horizontal scroll, all primary buttons inside the bottom third, all targets ≥ 44 px.

### US-APP-2-09 — Navigation on a phone

Found in review: the sidebar hides below 768 px (correct for the performer), which leaves **no navigation at all** on a phone.

- On a phone, Execution is the home screen.
- A compact menu (bottom bar or menu button) reaches the other two layers.
- Desktop keeps the existing sidebar unchanged.

**Acceptance:** at 375 px every layer is reachable in two taps; at ≥ 768 px the sidebar is unchanged.

---

## Decisions needed (recommended defaults in bold)

| # | Question | Recommendation |
|---|---|---|
| D-1 | Is "Start session" its own event, or the first step's start? | **The first step's start.** One less tap; nothing to drift out of sync. Add a separate event only if "began the job" must differ from "began the first step". |
| D-2 | Can a session be finished with steps still open? | **No — every step must be done or skipped.** Otherwise "finished" means nothing in the variance data. |
| D-3 | Does Skip ask for a reason? | **Yes, optional.** Same short list as Blocked. Needs a small back-end change: `reason_code` is currently only read for `blocked`. |
| D-4 | Strict step order? | **No.** Highlight the next step; allow any order. |

---

## Test Plan

| Area | Covers |
|---|---|
| Unit (`npm test`) | `sessionModel` grouping and ordering (several jobs, one day; ties); next-step selection; status → visible buttons mapping for all five statuses; progress maths |
| Functional (real authenticated HTTP) | `session` shape present and correct; two same-flow jobs distinguishable; values from pinned version; notes write + read-back; cross-account notes and sessions denied; skip reason (if D-3 accepted) |
| UI (Playwright, phone viewports) | Today → Session → Step → actions → back; note survives failed save; Blocked reason prompt; Done-without-Start; double tap records once; layout checks from US-APP-2-08; phone navigation from US-APP-2-09 |
| Regression | `npm test`, existing Playwright specs, APP-1's functional cases, `workflow_tests/1–12` (driven via `runWorkspaceFunction` where the file can't be run) |

**Completion gate:** all of the above pass, plus a real phone-width session worked end to end against live data.

## Governance (data integrity, validation, observability)

**Data integrity:** reads stay on the frozen publication plus live status. Notes are append-only `activity_log` rows — never updated, never deleted. No new tables.

**Validation and friendly messages**

| Case | Message |
|---|---|
| Empty note | "Write something before saving." |
| Note too long | "Notes can be up to 1,000 characters." |
| Blocked without a reason | "Choose why this is blocked." |
| Finish with open steps (D-2) | "Finish or skip the remaining steps first." |
| Stale screen (status changed elsewhere) | "This step changed since you opened it. Showing the latest." |

New error codes go in the catalog with the `E-APP` prefix; existing APP-1 codes are reused where they fit.

**Events logged** (`feature = APP-2`, via the OBS-1 client helper): `open_session`, `start_session`, `finish_session`, `note_save` (`success`/`failure`), `action_tap` (`success`/`failure`), `client_error`. De-duplicated and rate-capped like APP-1.

## Follow-ups (not in this epic)

- **Planner blank titles** for job-derived steps — reuse US-APP-2-01's provenance shape on the board endpoint.
- **Map-level "live on this version"** view in the Intelligent Layer.
- Nav label: "Intelligent Layer" opens the journey maps; consider renaming.

## Test Results

*(empty — to be filled when built)*
