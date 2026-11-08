# EPIC-PUX-2 — Time windows everywhere you decide

**Status:** ✅ Built + browser-verified on real data (Opus 5.5, 2026-11-07). Results §6; deviations at the end.
**Model:** Sonnet 5.5 (frontend only).
**Depends on:** TW-1 (live), PUX-1 (the panel is where the window is edited).
**Risk:** low. Display and placement hints only; the server rules (TW-1) are unchanged.

---

## 1. Goal

**Pain:** "When can this happen?" I only see a job's window once I've already put it on the wrong day
(the amber "Outside time window" badge).

**Fix:** the window shows on every job, and the right days light up while I place it.

**Win:** I schedule it right the first time instead of fixing it later.

---

## 2. Design

```
Jobs column                 Unscheduled tray                     Board card
┌───────────────────┐      ┌──────────────────────────────┐     ┌──────────────────────┐
│ E2E card …6807     │      │ E2E card …6807  8  ⏰ 7 Nov   │     │ #1 08:00 710m         │
│ ⏰ 7 Nov 10:09–10:30│      │                 10:09–10:30  │     │ E2E card …6807        │
└───────────────────┘      └──────────────────────────────┘     │ ⏰ 7 Nov 10:09–10:30   │ ← always
                                                                 └──────────────────────┘
Placing (drag or Place…):  Sun Mon Tue Wed Thu [Fri ✓] Sat   ← days inside the window highlighted
```

- **One look, everywhere:** the same small "⏰" chip on the Jobs column, Unscheduled rows, board cards and
  the week view. Neutral when fine, amber when broken — never hidden.
- **Placing helps, it doesn't block** (TW-1 V1 is a soft window): highlight fitting days, suggest the
  first one, still allow anything.
- **Sort by urgency:** soonest window first is one click away.

---

## 3. Stories

### US-PUX-2-01 — A window chip on every job
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

**As a** planner, **I want** to see each job's time window wherever the job appears,
**so that** I know its constraint before I act.

```gherkin
Scenario Outline: The chip shows on every surface
  Given job "E2E card 1793637936807" has a window 10:09–10:30 on 7 Nov
  Then <place> shows "7 Nov 10:09–10:30"
  Examples:
    | place                 |
    | its Jobs column entry |
    | its Unscheduled row   |
    | its board card        |
    | its week-view entry   |

Scenario: A job with no window shows nothing new
  Given a job with no window
  Then no chip appears anywhere

Scenario: A broken window turns amber
  Given the job sits on a day outside its window
  Then its chip is amber and reads "Outside window"
```

**Build notes.** One `TimeWindowChip` component fed by the existing `windowsByJob`. Replace the board's
current amber-only badge with it (keep its `data-testid` so existing tests still find it). Text via
`formatWindow` (one formatter, not four).

### US-PUX-2-02 — The right days light up when placing
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

**As a** planner, **I want** days inside a job's window highlighted while I drag or place it,
**so that** I drop it in the right place the first time.

```gherkin
Scenario: Dragging highlights fitting days
  Given the job's window is 7 Nov
  When I drag its card over the week
  Then 7 Nov is highlighted and other days are not

Scenario: Place… suggests a day
  When I open "Place…" on that job
  Then the day field is pre-filled with the first day inside its window that is also inside the plan
  And I can still choose any other day

Scenario: Placing outside the window warns, never blocks
  When I place it on 5 Nov
  Then it is placed and the chip turns amber
```

**Build notes.** Pure `daysInsideWindow(window, planStart, planEnd)` in `timeWindowModel.ts`,
unit-tested; reuse `isPlacementOutsideWindow`.

### US-PUX-2-03 — Sort and filter by window
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: Soonest window first
  When I sort the Jobs column (or Unscheduled) by "Window"
  Then jobs with the earliest window end come first and jobs with no window come last

Scenario: Filter to "has a window this plan"
  When I filter "Window in this plan"
  Then only jobs whose window overlaps the plan's dates remain
```

### US-PUX-2-04 — The performer sees the same chip
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: Same text on the performer's screens
  Given a published step whose job has a window
  Then Today, the job screen and the step screen show the window with the same wording as the planner
```

**Build notes.** TW-1 -05 already shows it on the performer side; this story only makes the wording and
look match (one formatter).

---

## 4. Governance

- No new rule, endpoint or code. Windows stay soft (TW-1 D-2); enforcement is V2's "hard" type.

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| UT-PUX-2-01 | Unit | `daysInsideWindow` — single day, multi-day, crosses midnight, partly outside plan, no window |
| UT-PUX-2-02 | Unit | window sort order (earliest end first, none last) |
| UI-PUX-2-01 | Browser | chip on all four surfaces for job 6807; nothing on a job without a window |
| UI-PUX-2-02 | Browser | drag highlight + Place… pre-fill |
| REG | Suites | `npm test`, `tsc`, build; TW-1's existing tests unchanged |

## 6. Test results (2026-11-07, Opus 5.5)

**Suites:** `npm test` **783/783** (754 before; +29 new), `tsc` clean, build clean. Playwright specs compile; they skip without `E2E_AUTH_TOKEN` (not run — a skip is not a pass).

| ID | Result |
|---|---|
| UT-PUX-2-01 `daysInsideWindow` (3 tests: single, multi-day crossing midnight clipped to plan, outside/none) | ✅ |
| UT-PUX-2-02 `compareByWindow` | ✅ |
| UT-PUX-2-03 `windowChipState` none/fine/outside | ✅ |
| UI-PUX-2-01 chip on Jobs column, board card, Edit Step, Jobs list, week view, job panel | ✅ job 6807 amber "Outside window · 10:09–10:30, 7 Nov"; jobs without a window show nothing |
| UI-PUX-2-02 Place… shows the window chip for the chosen day | ✅ |
| Drag highlight ("This day fits / is outside its window") | ⚠️ built, logic unit-tested; **not browser-verified** — native drag-and-drop can't be driven by the test browser (same limit TW-1 hit) |
| US-PUX-2-04 performer wording | ✅ no change needed — Today/Session/Step screens already use the same `formatWindow` |

## Build notes and deviations (2026-11-07)

- **Drag highlight is on the day board only, not the week view**: the week view doesn't accept job
  drops at all (jobs are placed from the day board or Place…), so highlighting days there would invite a
  drop that can't happen.
- **Place… pre-fills the first day inside the job's window AND the plan**; with no such day it keeps the
  old default (WIN-1).
- Sort/filter by window landed on the Jobs column and the Jobs list (not the Unscheduled tray).
