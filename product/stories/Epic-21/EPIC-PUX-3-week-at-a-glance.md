# EPIC-PUX-3 — Week at a glance: right day, nothing hidden, names not counts

**Status:** ✅ Built + browser-verified on real data (Opus 5.5, 2026-11-07). Results §6; deviations at the end.
**Model:** Sonnet 5.5 (frontend only).
**Depends on:** WIN-1 (plan window, live). Independent of PUX-1/-2 — can run in parallel.
**Risk:** low.

---

## 1. Goal

**Pain:** "Is my week right?" The Nov 1–7 plan opens on **Oct 27**. Job 6807 sits on Oct 27, so the week
view never shows it. The week view says "1 task", not which task. Cards repeat the job title twice.

**Fix:** open on the plan's first day, flag anything outside the plan, show job names in the week view,
one clean title per card.

**Win:** one glance tells me the week is complete.

---

## 2. Design

```
Plan: Nov 1–7                                   ⚠ 1 job is scheduled outside this plan  [Show]
        SUN 1      MON 2      TUE 3      WED 4               THU 5 …
Jav     —          —          —          08:00 E2E card …6807
                                         11h 50m / 8h ⚠
```

- **Open where the plan is:** today if today is inside the plan, else the plan's first day.
- **Never hide work:** a banner counts work on days outside the plan, with one click to go there.
- **Names, not counts:** each week-view cell lists its jobs (time + short name), with "+2 more" when full.
- **One title per card:** job title once; step name only when it adds something.

---

## 3. Stories

### US-PUX-3-01 — Open on the right day
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: Today is inside the plan
  Given the plan is Nov 1–7 and today is Nov 4
  When I open the plan
  Then the board shows Nov 4

Scenario: Today is outside the plan
  Given today is Nov 9
  When I open the Nov 1–7 plan
  Then the board shows Nov 1

Scenario: No hard-coded dates
  Then no code path sets the board day to a fixed date like 2026-10-13
```

**Build notes.** `PlannerApp.tsx` sets `activeDay` from the first timeline (~line 160, ~258) and has
several `'2026-10-13'` fallbacks (~1071–1137). Replace with one pure `initialBoardDay(today, planStart,
planEnd)` in a model file, unit-tested. "Today" from the device is fine here (planner side only — the
performer's "server decides the day" rule does not apply to choosing a view).

### US-PUX-3-02 — Work outside the plan is flagged, not hidden
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: A banner counts outside-plan work
  Given job 6807 is on Oct 27 and the plan is Nov 1–7
  Then a banner says "1 job is scheduled outside this plan's dates"

Scenario: One click to see it
  When I click "Show"
  Then the board jumps to Oct 27 and highlights the card

Scenario: Nothing outside, no banner
  Given every timeline is inside the plan
  Then no banner shows
```

**Build notes.** Uses the existing `isDateOutOfWindow`. WIN-1 already blocks *new* days outside the
plan; this surfaces the ones that exist.

### US-PUX-3-03 — The week view shows job names
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: Cells list their jobs
  Given Jav's Nov 4 has 1 job at 08:00
  Then the week cell shows "08:00 E2E card …6807" instead of "1 task"

Scenario: Busy cells stay readable
  Given a cell has 6 jobs
  Then it shows the first 3 and "+3 more"

Scenario: Clicking a name opens the job
  When I click a job name in the week view
  Then the job panel opens (PUX-1), or the day opens if PUX-1 is not built yet
```

### US-PUX-3-04 — One title per card
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: A whole-job card shows its title once
  Given a card whose title and step label are the same text
  Then the card shows it once

Scenario: A single-step card still names the step
  Given a card for one step "Triage" of job "Turn-around"
  Then it reads "Turn-around" and, below it, "Triage"
```

**Build notes.** The duplication comes from `linkedCardTitle` + the card's provenance line rendering the
same string. Fix in the adapter/model with a test, not by hiding a line in the component.

---

## 4. Governance

No new rule, endpoint or code.

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| UT-PUX-3-01 | Unit | `initialBoardDay` — today inside, before, after the plan; plan with no window |
| UT-PUX-3-02 | Unit | outside-plan count from timelines |
| UT-PUX-3-03 | Unit | card title de-duplication |
| UI-PUX-3-01 | Browser | Nov 1–7 plan opens on Nov 1 (or today); banner shows job 6807; Show jumps to Oct 27 |
| UI-PUX-3-02 | Browser | week view shows names; "+N more" |
| REG | Suites | `npm test`, `tsc`, build, `card-scheduling.spec.ts` |

## 6. Test results (2026-11-07, Opus 5.5)

**Suites:** `npm test` **783/783** (754 before; +29 new), `tsc` clean, build clean. Playwright specs compile; they skip without `E2E_AUTH_TOKEN` (not run — a skip is not a pass).

| ID | Result |
|---|---|
| UT-PUX-3-01 `initialBoardDay` (3 tests) | ✅ |
| UT-PUX-3-02 `workOutsidePlan` (2 tests — an empty outside day is not flagged) | ✅ |
| UT-PUX-3-03 `cardSubtitle` de-duplication (3 tests) | ✅ |
| UT-PUX-3-04 `cellPreview` (2 tests) | ✅ |
| UI-PUX-3-01 Nov 1–7 plan opens on today (Nov 7, inside the plan) instead of Oct 27; banner "Work on 1 day outside this plan's dates — Tue 27 Oct · 1 item — Show"; Show jumps to Oct 27 | ✅ |
| UI-PUX-3-02 week view lists "08:00 Turn-around · 8 steps" instead of "1 task"; click opens the job | ✅ |
| Card shows its title once (job 6807 card) | ✅ |

## Build notes and deviations (2026-11-07)

- The hard-coded `'2026-10-13'` dates left in `PlannerApp.tsx` belong to `handleSelectScenario` — the
  Component Sheet's demo-data loader, not the real board path. Left alone. The `'2026-10-12'/'25'`
  fallbacks for a plan with no dates are also untouched (every real plan has dates since WIN-1).
- The banner also shows in the week view (it sits above both).
