# EPIC-PUX-4 — Who's free: capacity while placing, a status on every job

**Status:** ✅ Built + browser-verified on real data (Opus 5.5, 2026-11-07). Results §6; deviations at the end.
**Model:** Sonnet 5.5 (frontend only).
**Depends on:** PUX-3 (same week view). Capacity data is live (`daily_capacity_hours`, `dayLoad`).
**Risk:** low.

---

## 1. Goal

**Pain:** "Who's free?" I find out Jav is at 11h 50m of 8h only **after** I've assigned the work. And I
can't tell at a glance which jobs still need scheduling.

**Fix:** show each person's free hours while I'm placing, warn before overloading, and put a status on
every job.

**Win:** fair workloads, no rework, and I can see what's left.

---

## 2. Design

```
Dragging "E2E card …6807" (11h 50m)
        SUN 1        MON 2        TUE 3
Jav     8h free ✓    2h free ⚠    0h free ✗      ← shown only while dragging / in Place…
Rhea    6h free ⚠    8h free ✓    8h free ✓

Jobs column
E2E card …6807    [Scheduled]      Turn-around   [Partly · 3 left]      Repair   [Unscheduled]
```

- **Free hours appear when they matter:** while dragging or in Place…, not cluttering the board all day.
- **Warn, never block:** ✓ fits, ⚠ fits but goes over, ✗ already full. The planner decides.
- **Status labels:** Unscheduled · Partly scheduled (N left) · Scheduled · Live · Done — one word, same
  colours everywhere.

---

## 3. Stories

### US-PUX-4-01 — Free hours while placing
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: Dragging shows each person's free time per day
  Given Jav has 8h capacity and 6h planned on Mon
  When I drag a 3h job over the week
  Then Jav's Mon shows "2h free ⚠" and Rhea's empty Mon shows "8h free ✓"

Scenario: Place… shows the same numbers
  When I open Place… on a job
  Then the person and day choices show free hours next to them

Scenario: Hints disappear when I'm done
  When I drop the job or close Place…
  Then the free-hour hints disappear
```

**Build notes.** Pure `freeMinutes(agent, day, tasks)` in `boardModel.ts` reusing the existing
`dayLoad` logic (one formula, not a second copy), unit-tested.

### US-PUX-4-02 — Warn before overloading
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario: A drop that overloads asks once
  Given Jav's Tue is already full
  When I drop an 11h 50m job on it
  Then I see "This puts Jav at 23h 40m of 8h. Place anyway?" with Place / Cancel

Scenario: A drop that fits never asks
  Given the job fits
  When I drop it
  Then it is placed with no question
```

**Build notes.** Soft confirm only, client-side — capacity is not a server rule today, and making it one
is a separate decision for the founder.

### US-PUX-4-03 — A status on every job
**Status:** ✅ Built (Opus 5.5, 2026-11-07).

```gherkin
Scenario Outline: Status labels
  Given a job whose steps are <state>
  Then its label reads "<label>"
  Examples:
    | state                                   | label                  |
    | none on a day                           | Unscheduled            |
    | 5 of 8 on a day                         | Partly · 3 left        |
    | all on a day, day not published         | Scheduled              |
    | all on published days                   | Live                   |
    | job completed                           | Done                   |

Scenario: Filter to what needs me
  When I filter the Jobs column by "Needs scheduling"
  Then only Unscheduled and Partly jobs remain
```

**Build notes.** Pure `jobPlanStatus(job, linkedSteps, timelines)` in a model file, unit-tested; the
same function feeds PUX-1's panel header.

---

## 4. Governance

No new rule, endpoint or code. Capacity stays advisory.

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| UT-PUX-4-01 | Unit | `freeMinutes` — empty day, partial, over, agent with custom capacity |
| UT-PUX-4-02 | Unit | `jobPlanStatus` — every row of the table above |
| UI-PUX-4-01 | Browser | drag shows free hours; overload confirm; fitting drop silent |
| UI-PUX-4-02 | Browser | labels + "Needs scheduling" filter on real data |
| REG | Suites | `npm test`, `tsc`, build, `card-scheduling.spec.ts` |

## 6. Test results (2026-11-07, Opus 5.5)

**Suites:** `npm test` **783/783** (754 before; +29 new), `tsc` clean, build clean. Playwright specs compile; they skip without `E2E_AUTH_TOKEN` (not run — a skip is not a pass).

| ID | Result |
|---|---|
| UT-PUX-4-01 `capacityFit` / `formatFree` (5 tests: empty, over, full, custom capacity, wording) | ✅ |
| UT-PUX-4-02 `jobPlanStatus` (every row of the table + mixed live/draft + stale counts) | ✅ |
| UT-PUX-4-02b `overloadMessage` | ✅ |
| UI-PUX-4-01 Place… shows "8h free ⚠" for an 11h 50m job on Jav's empty day | ✅ |
| UI-PUX-4-02 Place → "This puts Jav at 11h 50m of 8h. Place anyway?" → Cancel → nothing placed | ✅ |
| UI-PUX-4-03 labels Unscheduled / Scheduled / Done on the real plan; "Needs scheduling" filter leaves only the 3 unscheduled jobs | ✅ |
| Free hours on each column while dragging | ⚠️ built, logic unit-tested; **not browser-verified** (native drag-and-drop) |


## 7. Open question for the founder

- Should the overload warning ever become a hard stop (a server rule)? Default: **no**, advisory only.

## Build notes and deviations (2026-11-07)

- **The overload question covers placing a JOB** (drag from Unscheduled, drop on a new day, Place…).
  Moving an existing slot between days, and plain (non-job) tasks, are not asked about — not in the
  stories' scope.
- An Unscheduled card with no estimate (`expected_minutes` empty) is never asked about: there is no
  number to compare.
- The confirm is an in-app dialog, not the browser's `confirm()`.
