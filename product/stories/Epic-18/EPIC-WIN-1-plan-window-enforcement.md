# EPIC-WIN-1 — A plan's window actually means something

**Status:** 📋 **Designed 2026-11-01, nothing built.** Four stories. Two change live XanoScript,
one is frontend, one deletes data. Read `README.md` in this folder first — it carries the handoff
context, the models and the reporting rules.
**Default model:** **Opus 5.5** for -01, -03, -04 and the review pass. **Sonnet 5.5** for -02.
**Depends on:** PLN-3 (`planner_workspace.planning_window_start/end` — live), PLN-6 (endpoint 538,
the timeline writer — live), BLK-1/BOARD-1 (the schedule path — live).
**Risk:** **medium-high**, and concentrated: endpoint 538 is the **only** writer of
`planner_timeline` in the entire backend. If -01 goes wrong, no day can be created anywhere in the
product. -04 deletes across four linked tables.

---

## 1. Goal

The founder, 2026-11-01, on the running app:

> *"I created a new map called November 1-7 … Observe that the associated new job that I created
> allowed me to assign it to a user prior to that date range. … It shouldn't allow you to assign
> the job outside of the date range that you set up."*

They are right, and the reason is not a localised bug: **the planning window has never been
enforced anywhere in this product.** Verified 2026-11-01 across the whole stack.

| Layer | What it does with the window today |
|---|---|
| `538` create-timeline | Computes `out_of_window` and **returns it as a flag.** Creates the row regardless. |
| `539` / `540` / `548` reads | Compute the same flag so the UI can draw a badge. Correct — leave alone. |
| Frontend, 6 components | `isDateOutOfWindow` used only for badges and a count ("N timelines out of window"). |
| Place… date picker | A bare `<input type="date">` with **no `min`/`max`**. Every date in history is offerable. |

**Evidence of the cost: 17 of 38 timelines in the database sit outside their own plan's window.**
That is not drift, that is an unenforced rule.

**One terminological correction, worth keeping straight** — the founder said "map", but the date
range lives on the **plan** (`planner_workspace`), not the map. "November 1-7" is plan **43**,
window `2026-11-01 → 2026-11-07`. The map is the definition of the work; the plan is the
commitment window. Do not add a date range to a map.

---

## 2. What exists today (verified 2026-11-01 — re-verify before building)

- **`apis/planner/538_workspace_workspace_id_timeline_POST.xs` is the ONLY writer of
  `planner_timeline`.** Confirmed by grep across `apis/` and `functions/`. Endpoint `583`
  (`card/schedule`) does **not** create days — it calls `planner/assert_timeline` on one that
  already exists. **This single chokepoint is what makes this epic cheap.**
- 538 already computes the test, at its end: `var $out_of_window { value = ($input.planned_date <
  $guard.workspace.planning_window_start || $input.planned_date >
  $guard.workspace.planning_window_end) }`, returned in the response. The comparison is already
  written and already correct; the story is to make it **refuse** instead of report.
- Text dates compare correctly against `date` columns in this engine (CLAUDE.md), and these are
  `YYYY-MM-DD`, so string comparison is also chronological. No date maths needed.
- `planner_workspace` has `planning_window_start` and `planning_window_end` (`date`).
  `planner_timeline` has `planned_date` (`date`) and a unique index on `(agent_id, planned_date)`.
- Frontend: `PlannerApp.tsx`'s `visibleDates` **is** correctly window-bounded and inclusive
  (`getDaysDifference` already adds 1 — checked; do not "fix" it). `ScheduleGrid.tsx` is **not**:
  it starts at `windowStart` then renders a fixed `spanWeeks * 7` days regardless of the window's
  real length.
- `src/planner/utils/dateUtils.ts` already exports `isDateOutOfWindow`. Reuse it; do not write a
  second one.

---

## 3. MVP scope — four stories

### US-WIN-1-01 — The server refuses a day outside the plan's window
**Status:** 📋 Not started. **Model: Opus 5.5.**

**As a** planner,
**I want** the server to refuse a day outside my plan's window,
**so that** a plan called "November 1-7" cannot contain work from October.

```gherkin
Scenario: A day inside the window is created as it always was
  Given a plan whose window is 2026-11-01 to 2026-11-07
  When I create a day for 2026-11-03
  Then it is created
  And nothing about the existing behaviour changes

Scenario: A day before the window is refused
  Given a plan whose window is 2026-11-01 to 2026-11-07
  When I try to create a day for 2026-10-27
  Then the request is refused
  And the message names the day I asked for and the plan's window
  And no timeline row is written

Scenario: A day after the window is refused
  When I try to create a day for 2026-11-20 in that same plan
  Then the request is refused the same way

Scenario: The window's own boundaries are allowed
  When I create a day for 2026-11-01, and another for 2026-11-07
  Then both are created
  Because the window is inclusive of both ends

Scenario: Existing out-of-window days still load
  Given a timeline already exists outside its plan's window
  When any read endpoint returns it
  Then it is returned with its out-of-window flag as before
  And nothing is refused on read
```

**Build notes.**
- Turn the existing `$out_of_window` computation into a **`precondition`**, placed *before* the
  `db.add`, not after. Build the message into a `var` on the line before with `sprintf` — a
  `precondition`'s `error =` takes a plain variable, and its condition must stay on **one line**
  (a multi-line boolean fails to parse).
- **`$out_of_window` then becomes dead in the response** — if creation is refused it can only ever
  be `false`. Remove the field from the response **and** from the frontend's type in
  `plannerApi.ts` (~line 117 and ~130). No shim, no always-false field left behind.
- **Leave 539 / 540 / 548 completely alone.** Their flags describe *existing* rows and the UI
  still needs them for the 17 legacy violations. Enforcement is write-time only (D-2).
- New error code. **Check `src/ops/errorCatalog.ts` for the next free `E-PLAN-*` number** rather
  than assuming; add the code with a friendly sentence naming the window.
- `getAPI` 558… no: `getAPI` **538** and diff it against the local `.xs` first. Then push, then
  smoke-test with a throwaway function against a real plan — one day inside the window, one
  before, one after, and both boundary days.

---

### US-WIN-1-02 — The UI stops offering a day it knows is invalid
**Status:** 📋 Not started. **Model: Sonnet 5.5.**

**As a** planner,
**I want** the date pickers to only offer days in my plan's window,
**so that** I am prevented from making the mistake instead of told off afterwards.

```gherkin
Scenario: The Place… picker cannot reach outside the window
  Given a plan whose window is 2026-11-01 to 2026-11-07
  When I open the Place… form on an unscheduled role line
  Then the date field will not accept a day before 2026-11-01 or after 2026-11-07

Scenario: The Schedule grid shows the window, not a fixed fortnight
  Given a plan whose window is 3 days long
  When I open the Schedule view
  Then I see 3 day columns
  And I do not see columns for days outside the window

Scenario: A legacy out-of-window day is still visible and still flagged
  Given a timeline already exists outside the window
  When I look at the planner
  Then I can still see it
  And it still carries its out-of-window warning
```

**Build notes.** Add `min`/`max` to the `<input type="date">` in `BacklogDrawer.tsx` (~line 707)
from the active plan's window, and to any other day picker that writes a date (check
`EditModal.tsx` and the keyboard-placement form in the same file). In `ScheduleGrid.tsx` (~line
81-85), derive the column count from the window's real length instead of `spanWeeks * 7`, keeping
the existing paging behaviour for windows longer than one page. **Do not remove the
out-of-window badges** — they are the only way the 17 legacy rows are visible. The server is still
the authority (D-5); this story only stops the mistake being offered.

---

### US-WIN-1-03 — A window cannot shrink out from under scheduled work
**Status:** 📋 Not started. **Model: Opus 5.5.**

**As a** planner,
**I want** to be stopped from shrinking a window past work I have already scheduled,
**so that** I cannot strand a day a performer may already have been given.

```gherkin
Scenario: Widening a window is always allowed
  Given a plan with work scheduled inside its window
  When I widen the window
  Then it is accepted

Scenario: Shrinking past scheduled work is refused
  Given a plan whose window is 2026-11-01 to 2026-11-07
  And a day with work scheduled on 2026-11-06
  When I try to change the window end to 2026-11-04
  Then the request is refused
  And the message says how many days would be stranded, and the dates
  And the window is unchanged

Scenario: Shrinking over empty days is allowed
  Given no timeline exists after 2026-11-04
  When I change the window end to 2026-11-04
  Then it is accepted
```

**Build notes.** This is `apis/planner/526_workspace_workspace_id_PATCH.xs`. Count the timelines
that would fall outside the proposed window with `db.query ... return = {type: "count"}` — that
returns a plain int and is the right tool. **Hoist the proposed bounds into `var`s first**: a
`where` clause cannot call filters, and it compiles to SQL. Refuse with a counted message
(D-3). Remember the endpoint may receive only one of the two bounds — an omitted optional
**`date`** input does not exist at all and referencing it throws, so follow CLAUDE.md's rule and
treat optional date filters as text with a sentinel, or read the raw input.

---

### US-WIN-1-04 — Remove the days that already break the rule
**Status:** 📋 Not started. **Model: Opus 5.5.**

**As the** founder,
**I want** the existing out-of-window rows gone,
**so that** the data stops reporting a plan that was never real.

The founder authorised this in advance, 2026-11-01: *"If you see any jobs that break this
constraint, go ahead and remove it. All the data that we have right now is just a bunch of test
data anyways. Just make sure that you remove it to where you don't cause any orphan data or jobs
or whatever else that destabilizes the database."* That is a **scoped** approval — it does not
extend to anything below.

```gherkin
Scenario: A draft out-of-window day is removed cleanly
  Given a draft timeline outside its plan's window
  And it has no publication and no recorded activity
  When it is removed
  Then its scheduled slots and their job-step links go with it
  And the job itself and its steps remain, unscheduled
  And no row anywhere points at something that no longer exists

Scenario: A published out-of-window day is left alone
  Given timeline 18 is outside its window AND published
  When the cleanup runs
  Then it is skipped
  And the reason is recorded in this file

Scenario: The cleanup proves itself
  When the cleanup has run
  Then the violating rows are re-counted by querying the database
  And the count is zero apart from the documented exception
```

**The 17 rows, as read on 2026-11-01.** Re-query before acting; this list is a snapshot.

| Plan | Window | Timeline ids (all `draft` unless noted) |
|---|---|---|
| 1 (acct 3) | 10-14 → 10-14 | 1 (10-20) |
| 4 (acct 6) | 10-14 → 10-15 | 3, 4, 5 (10-20/21/20), 8 (11-30), 9 (10-26), 10 (10-27), 14 (11-11), 16 (11-12) |
| 5 (acct 6) | 10-14 → 10-27 | 11 (12-01), 12 (12-02), 13 (12-03) |
| 9 (acct 6) | 10-19 → 11-01 | **18 (10-15) — PUBLISHED. DO NOT DELETE.** |
| 24 (acct 2) | 10-18 → 10-31 | 28 (10-13) |
| 32 (acct 2) | 10-20 → 11-02 | 31 (10-13) |
| 34 (acct 2, archived) | 10-26 → 11-08 | 39 (2027-01-15) |
| 43 (acct 2) | 11-01 → 11-07 | **46 (10-27) — the one the founder reported** |

**16 to delete. 1 to skip.**

**Build notes — the delete order matters.**
1. **Pre-check every candidate and skip it if any of these is true:** it has a `plan_publication`
   row (table 125), any `activity_log` row against its job (127), or `status == "published"`.
   Record every skip in §10. Timeline 18 is the one known case; do not assume it is the only one.
2. Delete **children first**, or you orphan them: `planner_task_work_task` (124) for each
   `planner_task` → the `planner_task` rows (118) → the `planner_timeline` row (117). Also check
   `plan_change_log` (126) for rows pointing at the timeline.
3. **`db.del` by `field_name` deletes only the FIRST match.** Query the rows and loop, deleting
   each by `id`, inside a `db.transaction`. This is the single easiest way to half-apply this
   cleanup and believe it worked.
4. **Leave jobs and work_tasks alone.** Removing a scheduled slot returns the work to Unscheduled;
   that is the intended end state, not a loss. The founder said "remove the jobs" — what they
   actually want is the *bad scheduling* gone, and the 8 steps of job 138 are fine once unplaced.
5. **Verify by re-querying and counting.** Do not trust the function's own tally — a cleanup in
   this project once reported success and changed nothing (CLAUDE.md's `db.patch`-on-`json`
   incident). Count before, count after, state both.

---

## 4. Decisions

- **D-1 — The window is a hard constraint on writes, not a warning.** It was advisory everywhere
  and 45% of timelines violate it; that is the evidence advisory does not work.
- **D-2 — Enforce on write only. Never validate on read.** 17 rows already violate it and one is
  published. A read-side check would hide real history and break the Health page and variance.
- **D-3 — Shrinking a window past scheduled work is REFUSED.** The previous session recommended
  this and the founder replied "sounds good" without addressing it directly, so it is the recorded
  default rather than a confirmed decision — see README §8. Reasoning: refusing is the only option
  that cannot silently strand a day a performer may already hold.
- **D-4 — The cleanup approval is scoped to out-of-window timelines and their scheduling rows.**
  It does not authorise deleting jobs, work_tasks, publications, activity log rows, plans, or
  anything in another epic. Anything beyond the table in US-WIN-1-04 needs a fresh ask.
- **D-5 — The server stays the authority.** The UI bounds in -02 are a convenience. Do not remove
  the server check because the picker now prevents it; the API is callable directly.
- **D-6 — Both window ends are inclusive.** `2026-11-01` and `2026-11-07` are both valid days of
  a `11-01 → 11-07` plan. The existing comparison already treats them that way.

---

## 5. Open questions (founder)

- **Q-1 — Should an existing out-of-window day be *movable* into the window, or only deletable?**
  Not needed for this epic (the cleanup deletes them), but it is the natural follow-up and nobody
  has asked. Do not build it.
- **Q-2 — Should the plan's window be editable at all once a day inside it has been published?**
  D-3 only guards against stranding. A stricter rule may be wanted later.

---

## 6. Governance

- **No schema change. No new table, no new column.** Two preconditions, one response field
  removed, UI bounds, and a scoped delete.
- **Error codes:** two new ones needed (out-of-window day; shrink would strand work). Take the
  next free `E-PLAN-*` numbers from `src/ops/errorCatalog.ts` — **look them up, do not guess** —
  and give each a sentence a non-engineer can act on, naming the dates involved.
- **Events:** the refusals are rejections, not failures. Log them at `info` with
  `outcome: 'rejected'`, the way `handleJobCardDropRefused` already does for a refused drop.
- **Deletes:** only those in US-WIN-1-04's table, inside a `db.transaction`, children first,
  verified by re-query. Nothing else.
- **Tenancy:** untouched. Every endpoint here already runs `planner/assert_workspace`; do not
  weaken or bypass it while adding the window check.

---

## 7. Test plan

| ID | Kind | What it proves |
|---|---|---|
| UT-WIN-1-01-01 | Unit | A date inside the window passes; both boundary dates pass |
| UT-WIN-1-01-02 | Unit | A date before the start, and one after the end, both fail |
| UT-WIN-1-02-01 | Unit | The day-column list for a 3-day window is 3 days, not 7 |
| UT-WIN-1-03-01 | Unit | Counting days that a proposed window would strand |
| LIVE-01 | Live smoke (`runWorkspaceFunction`) | 538 refuses before/after and accepts inside + both boundaries, **on a real plan** |
| LIVE-02 | Live smoke | 526 refuses a stranding shrink, allows a widen, allows a shrink over empty days |
| LIVE-03 | Live verify | Out-of-window timeline count re-queried after cleanup: 1 remaining (the documented published one) |
| REG-01..04 | Suite | `npm test` (661 at handoff + new), `tsc --noEmit`, `npm run build`, `playwright test --list` (47 files) |
| UI-01 | Founder | On plan 43: the picker refuses October, the grid shows 7 columns, and the bad day is gone |

Pure date logic goes in a tested function in `src/planner/utils/` or `boardModel.ts`, not in JSX.
**Every e2e spec skips without `E2E_AUTH_TOKEN` — report them as unrun.**

---

## 8. Completion gate

1. All four stories built, or explicitly blocked with a stated reason and a model note.
2. New unit tests green, plus the full suite, `tsc`, `build`, and `playwright --list`.
3. **LIVE-01, LIVE-02 and LIVE-03 actually run** against real data. A clean push is not evidence.
4. The cleanup verified by counting rows before and after, with the skip documented.
5. An **Opus 5.5 review pass** over -01, -03 and -04.
6. §9 filled in with a real result per ID, and §10 carrying every deviation.
7. Then **stop**. Do not start Epic-15 §4 (requirements / task types / optimizer).

---

## 9. Test Results

**Nothing built, nothing run.** Fill this in as you go, not at the end. One row per §7 ID, with
"not run" where that is the truth.

---

## 10. Notes

- **The founder's exact framing, kept because it is clearer than the spec's:** a plan named
  "November 1-7" that contains October work is a plan whose name lies. That is the bug, not the
  missing validation.
- **Why this was never caught:** every layer *computed* the window and then only drew a badge
  with it. Six frontend call sites and one backend flag, all cosmetic. There was never a decision
  to allow out-of-window days — there was just never a decision to refuse them. Worth remembering
  the next time a rule is "shown" rather than enforced.
- **The cheapest part of this epic is the most valuable:** 538 being the sole writer of
  `planner_timeline` means one precondition closes every path. That was verified by grep, not
  assumed — re-verify it, because a second writer added later would silently reopen the hole.
- **One more unenforced-rule smell to leave alone for now:** `ScheduleGrid` renders a fixed
  fortnight regardless of window length, which is how a day outside the window became *clickable*
  in the first place. -02 fixes the symptom. If you find other places that render days from
  anything other than the plan's window, note them here rather than widening this epic.
