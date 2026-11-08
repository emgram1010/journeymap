# EPIC-PUX-1 — One job panel: click a job anywhere, see that job

**Status:** ✅ Built + browser-verified on real data (Opus 5.5, 2026-11-07). Results §6; deviations at the end.
**Model:** Sonnet 5.5 (frontend only). Opus review pass after -02.
**Depends on:** JOB-1, EST-1, EXC-1, TW-1, SCHED-2 (all live).
**Risk:** low–medium. No backend change. Touches the planner's busiest screen.

---

## 1. Goal

**Pain:** "Where's my job?" Clicking a job opens a list of every job and expands mine somewhere in it.
Clicking a step on the board opens "Edit Step", which shows nothing about the job.

**Fix:** one side panel for **one** job, opened from every place a job appears. The board stays visible
behind it.

**Win:** one click, one job, everything about it in one place.

---

## 2. Design

```
┌ Board (still visible) ───────────────┐┌ Job panel (right side) ─────────────────┐
│                                      ││ E2E card 1793637936807        [×]       │
│  Jav  Tue 4 Nov                      ││ Not started · 0 of 8 steps · Scheduled  │
│  ┌─────────────────────────┐         ││ ⏰ Time window 10:09–10:30, 7 Nov  Edit  │
│  │ #1 08:00  E2E card …    │──click──▶│ ─ Where it's scheduled ─                │
│  └─────────────────────────┘         ││  Jav · Tue 4 Nov · 08:00 · 8 steps      │
│                                      ││ ─ Steps ─  (8, status each)             │
│                                      ││ ─ Items ─  (lines editor)               │
│                                      ││ ─ Exceptions ─ ─ History ─              │
└──────────────────────────────────────┘└─────────────────────────────────────────┘
```

- **Side panel, not a pop-up window.** The planner keeps seeing the day they're arranging.
- **Same panel from three places:** a job in the Jobs column, a card on the board, a row in Unscheduled.
- **Order of sections = order of a planner's questions:** what is it → when may it happen → where did I
  put it → what's in it → what went wrong → what happened.
- **"Edit Step" stays for the slot** (start, duration, assignee, ready/needs info, notes) and gains a
  one-line job header + "Open job".
- **The Jobs pop-up becomes a list** (search, New job, click a job → the panel). Nothing in it expands
  any more.

---

## 3. Stories

### US-PUX-1-01 — The job panel
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

**As a** planner, **I want** one panel that shows one job, **so that** I never hunt through a list.

```gherkin
Scenario: Opening a job shows only that job
  Given the plan has 5 jobs
  When I open job "E2E card 1793637936807"
  Then a side panel shows that job's title, status and step count
  And no other job's details are shown
  And the board is still visible beside it

Scenario: The panel holds everything about the job
  When the panel is open
  Then I see, in order: time window, where it's scheduled, steps, items, exceptions, history

Scenario: Closing returns me exactly where I was
  Given I scrolled the board to Jav's day
  When I close the panel (× or Esc)
  Then the board has not moved

Scenario: A cancelled job is read-only
  Given a cancelled job
  When I open it
  Then nothing in the panel is editable and it says "Cancelled"
```

**Build notes.** New `components/JobPanel.tsx`. Move — do not copy — the per-job blocks out of
`JobsModal.tsx` (steps, `TimeWindowEditor`, `JobLinesEditor`, `ExceptionSendPanel`, activity, cancel).
Keep PERF-1's rules: one shared `lines` fetch, abort in-flight requests when the panel closes or
switches job. Hooks above any early return (the bug JobsModal already hit once).

### US-PUX-1-02 — "Where it's scheduled"
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

**As a** planner, **I want** to see which day, person and time each part of the job sits on,
**so that** I know what's done and what's left without opening the board day by day.

```gherkin
Scenario: Scheduled parts are listed
  Given the job's 8 steps are on Jav's Tue 4 Nov at 08:00
  Then the panel shows "Jav · Tue 4 Nov · 08:00 · 8 steps"

Scenario: Unscheduled parts are called out
  Given 3 of the job's steps are still in Unscheduled
  Then the panel shows "3 steps not scheduled" with a "Place…" action

Scenario: Clicking a scheduled line takes me there
  When I click "Jav · Tue 4 Nov"
  Then the board jumps to Tue 4 Nov and highlights that card
```

**Build notes.** Derive from the board payload already in memory (`tasks`, `linked_steps`,
`timelines`) with a pure function in a model file (`jobScheduleModel.ts`), unit-tested. No new request.

### US-PUX-1-03 — Open the panel from everywhere
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

**As a** planner, **I want** the same panel whichever job I click, **so that** there is one way to do it.

```gherkin
Scenario Outline: Every job surface opens the panel
  When I click the job in <place>
  Then the job panel opens for that job
  Examples:
    | place                    |
    | the Jobs column          |
    | a card on the board      |
    | a row in Unscheduled     |
    | the Jobs list            |
```

**Build notes.** One `openJob(workItemId)` in `PlannerApp`; replace `jobsFocusId`. A board card's
**title** opens the job; its ⋮ menu keeps "Edit step".

### US-PUX-1-04 — "Edit Step" says which job it belongs to
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

**As a** planner, **I want** the step editor to show the job's time window and a way into the job,
**so that** I'm never stuck on a screen that hides the job.

```gherkin
Scenario: Job header in Edit Step
  Given a step of a job with a time window
  When I open Edit Step
  Then the top shows the job title, its time window, and "Open job"

Scenario: Open job from Edit Step
  When I click "Open job"
  Then Edit Step closes (asking first if I have unsaved changes) and the job panel opens
```

### US-PUX-1-05 — The Jobs pop-up becomes a plain list
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: The list no longer expands rows
  When I open Jobs
  Then I see search, "New job", and one line per job
  And clicking a line opens the job panel, not an expanded row
```

---

## 4. Governance

- No new table, endpoint, validation rule or error code. Every edit inside the panel goes through the
  endpoint it already uses, with its existing codes, logging and "keep your typing" behaviour.
- One success/failure event per panel open is **not** added (reads are not logged today; keep it so).

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| UT-PUX-1-01 | Unit | `jobScheduleModel`: groups a job's slots by day/agent; counts unscheduled steps |
| UT-PUX-1-02 | Unit | cancelled / completed job → read-only flags |
| UI-PUX-1-01 | Browser | open from all four places; same panel each time |
| UI-PUX-1-02 | Browser | "Where it's scheduled" jumps the board to the right day |
| UI-PUX-1-03 | Browser | network tab: one `lines` call per open, aborted on close (PERF-1 must not regress) |
| REG | Suites | `npm test`, `tsc`, build, existing e2e specs that open the Jobs modal |

## 6. Test results (2026-11-07, Opus 5.5)

**Suites:** `npm test` **783/783** (754 before; +29 new), `tsc` clean, build clean. Playwright specs compile; they skip without `E2E_AUTH_TOKEN` (not run — a skip is not a pass).

| ID | Result |
|---|---|
| UT-PUX-1-01 (`jobScheduleModel` placements, 4 tests) | ✅ |
| UT-PUX-1-02 (`jobPlanStatus`, 3 tests — read-only via Cancelled/Done kinds) | ✅ |
| UT-PUX-1-03 (`formatDayShort`) | ✅ |
| UI-PUX-1-01 open from Jobs column, board card title, Unscheduled name, Jobs list, week-view name | ✅ same panel each time, job 6807 on the real Nov 1–7 plan |
| UI-PUX-1-02 "Jav · Tue 27 Oct · 08:00 · 8 steps" → board jumps to Oct 27, column ringed | ✅ |
| UI-PUX-1-03 one `lines` request per open (PERF-1) | ✅ exactly 1; zero console errors |
| US-PUX-1-04 Edit Step header: window chip + "Open job" | ✅ opens the panel |
| US-PUX-1-05 Jobs list: no expanding rows; click → panel, list closes | ✅ |


## 7. Notes

- Mobile/narrow screens: the panel becomes full-width. Not designed further in this epic.

## Build notes and deviations (2026-11-07)

- **Sent-work chips open the related job in the same panel** (planner side), instead of the read-only
  JobPeekSheet (EXC-2 D-2). One job screen everywhere was the point of this epic; the performer's chips
  still open JobPeekSheet. `follow-sent-work.spec.ts` and `exceptions.spec.ts` updated to match.
- **"N steps not scheduled" points to Unscheduled** ("use Place… there") instead of its own Place
  button — Place… already lives on the Unscheduled row with the job's fit hints; a second copy in the
  panel would be two write paths.
- The panel got a "Try again" on a failed load (`job-panel-retry`), replacing the peek sheet's retry.
- `JobsColumn` no longer renders its own JobPeekSheet; BacklogDrawer keeps it only as a fallback when no
  `onOpenJob` is passed.
