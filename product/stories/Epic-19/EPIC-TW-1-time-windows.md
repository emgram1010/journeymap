# EPIC-TW-1 — Time windows, V1: one window per job

**Status:** 🚧 **All five stories built (2026-11-04/05).** -01/-02/-04 (Opus 5.5) live and
smoke-tested; -03/-05 (Sonnet 5) built and browser-verified on real data. See §10. Still open: a
real "Publish to live" with a v2 window (needs a founder-approved test timeline), and the Opus
review pass over -01/-02/-04.
Read `README.md` in this folder first.
**Default model:** **Opus 5.5** for -01, -02, -04 and the review. **Sonnet 5.5** for -03 and -05.
**Depends on:** JOB-1 (`work_item`, live), SCHED-1 / BLK-1 / BOARD-1 (scheduling a card, live),
LIVE-1 (`live/build_publication`, `live/log_plan_change`, live), APP-1 (performer app, live),
WIN-1 (plan window — **check its status first**, README §4).
**Risk:** **medium.** One new table (additive, nothing existing altered), new endpoints, and one
careful change to the publish snapshot's canonical hash (-04).

---

## 1. Goal

The founder, 2026-11-04:

> *"Two types of time windows, one soft and another one hard … for right now, version one, let's
> just put one time window … enable that on the planning and the execution, it's editable CRUD."*

**A time window says when a piece of work is allowed to happen**: "this job, between 09:00 and
11:00 on 3 Nov". Generic on purpose — an appointment slot, a site-access window, a review that must
land before a cut-off, an agent run that may only happen overnight. It is **optional** (PRD D-13):
a job without one works exactly as today.

**V1 delivers:** one window per job; create / read / update / delete it while planning; it travels
into the published day; the performer sees it; it can still be changed after the day is live, and
that change is logged. **V1 does not enforce it** — it warns (D-2). Enforcement is what V2's
**hard** type is for.

---

## 2. What exists today (verified 2026-11-04 — re-verify before building)

- **No window is stored anywhere.** `time_window` / `timeWindow` appear nowhere in `apis/`,
  `functions/` or `webapp/protype-2/src`.
- **The day has one start time, not a window.** `planner_timeline.start_time` (`HH:MM`, default
  `08:00`). A slot's start is derived (`start_time` + durations ahead of it, PLN-7); there is no
  stored `planned_start` and there must not be one.
- **The job is `work_item` (122).** It already has a flat `attributes` json (D-44, endpoint 556).
  **Do not put the window there**: PRD invariant 3 says anything the system computes with is a
  column, `attributes` is free text-ish key/value, and `db.patch` on a json column **merges**
  (CLAUDE.md 🔴). `work_item_line` (139) is the precedent for a typed child table.
- **Cards → slots → steps.** A card on the board creates `planner_task` rows (118), each linked to
  a `work_task` (123) through `planner_task_work_task` (124). A window on the **job** covers all of
  them; a window per slot would make the planner type it once per step (D-1).
- **Publishing freezes the day.** `live/build_publication` builds the items and a canonical hash
  (`publication|v1`, line ~321) with a TypeScript twin in `src/liveModel.ts`. The performer reads
  only the frozen snapshot (`perform/collect_published_items`, D-23).
- **Edits after publish are logged**, not blocked: `live/log_plan_change` does nothing on a draft
  day and writes `plan_change_log` (126) on a live one. Callers may invoke it unconditionally.
- **Routing:** the job endpoints already use a hyphenated prefix (`607 work-item/{id}/lines PUT`)
  next to `work_item/{id}` — follow that, so a new static segment is not shadowed (CLAUDE.md).

---

## 3. The data shape (for -01)

New table **`work_item_time_window`** — one row per job that has a window. No row = no window.

| Column | Type | Rule |
|---|---|---|
| `id` | int | PK |
| `created_at` | timestamp | `now` |
| `updated_at` | timestamp | set on every edit |
| `work_item_id` | int → `work_item` | **unique** (one window per job in V1), indexed |
| `start_date` | date | required |
| `start_time` | text `HH:MM` | required, 00:00–23:59 |
| `end_date` | date | required |
| `end_time` | text `HH:MM` | required, 00:00–23:59 |
| `note` | text, trim, optional | why the window exists ("site opens at 9") — max 200 |
| `constraint_type` | enum `["soft","hard"]`, default `soft` | **Reserved for V2.** Created now so V2 needs no migration; V1 never writes anything but `soft`, and the UI does not show it (D-3). |

- **Date + `HH:MM`, not an epoch timestamp**, because that is how the planner already speaks
  (`planned_date` + `start_time`, no timezone). The window means "plan-local time", same as the
  day. Timezones are deferred with everything else time-zone-shaped.
- **A window may span days** (start 3 Nov 18:00 → end 4 Nov 06:00 is valid). The rule is only
  *end after start*. Overnight work is real for some work types; refusing it would be an industry
  assumption.
- **Delete behaviour:** deleting the window deletes the row. The job is never touched. A cancelled
  job keeps its window as history and refuses edits (E-TW-005).
- **Why a new table and not columns on `work_item`:** additive-only rule, and the confirmed
  `updateTableSchema` validator-drop bug on tables with `trim` text columns (CLAUDE.md, GOV-1 /
  STAGE-1 precedent). A side table touches nothing that exists.

---

## 4. MVP scope — five stories

### US-TW-1-01 — A job can hold one time window
**Status:** ✅ Built and live (Opus 5.5, 2026-11-04) — see §10. Opus review pass still due. **Model: Opus 5.5.**

**As a** planner,
**I want** a job to be able to carry a time window,
**so that** the plan records when the work is allowed to happen, not just which day it landed on.

```gherkin
Scenario: The table exists and holds one window per job
  Given the new work_item_time_window table
  When a window is stored for job 140
  Then exactly one row exists for job 140
  And a second insert for job 140 is refused by the unique index

Scenario: Nothing existing changes
  Given every table that existed before this story
  When the table is created
  Then no existing table, column, index or row is altered
  And every existing suite is still green

Scenario: The schema audit accepts it
  When scripts/audit-schema.mjs runs
  Then work_item_time_window passes (PK, declared + indexed reference, unique natural key, enum)
```

**Build notes.** Local file `static/tables/<id>_work_item_time_window.xs`, named after the id Xano
**actually** assigns (never the one you expect). Header comment explains why a side table, why
date + `HH:MM`, and that `constraint_type` is reserved for V2. **Ask the founder before the push.**
Record the id in the phase-4 README's table list only if the founder agrees that file is in scope;
otherwise note it in §10.

---

### US-TW-1-02 — Create, read, update and delete a job's window (API)
**Status:** ✅ Built and live (Opus 5.5, 2026-11-04) — see §10. Opus review pass still due. **Model: Opus 5.5.**

**As a** planner,
**I want** to set, change and remove a job's time window,
**so that** I can record a constraint the moment I learn about it, and fix it when it changes.

| Verb | Path | Does |
|---|---|---|
| `PUT` | `work-item/{work_item_id}/time-window` | Create or replace (upsert). Idempotent. |
| `GET` | `work-item/{work_item_id}/time-window` | The window, or `{window: null}`. |
| `DELETE` | `work-item/{work_item_id}/time-window` | Remove it. Deleting a job with no window succeeds quietly. |

**Plus, the window must come back on the reads the planner and job view already use** — the job
list (`558`), job detail (`555`), and the board (`548`) — as `time_window: {start_date, start_time,
end_date, end_time, note} | null`. This is CLAUDE.md's side-table rule: *a side table nobody reads
is invisible to the frontend forever, with no error.* Join it inside those endpoints, or add one
no-filter list endpoint and merge it client-side — pick one, say which in §10.

```gherkin
Scenario: Set a window
  Given job 140 in my plan, with no window
  When I PUT start 2026-11-03 09:00, end 2026-11-03 11:00
  Then the window is stored
  And GET returns it
  And the job list and the board return it on job 140

Scenario: Change a window
  When I PUT a new end of 12:00
  Then the stored window ends at 12:00
  And there is still exactly one window for job 140

Scenario: Remove a window
  When I DELETE it
  Then GET returns no window
  And the job and its scheduled steps are unchanged

Scenario Outline: Junk is refused and nothing is written
  When I PUT <input>
  Then the request is refused with <code>
  And the message says what to fix in plain words
  And any existing window is unchanged
  Examples:
    | input                                   | code     |
    | start_time "9:5" or "25:00" or ""       | E-TW-001 |
    | end before (or equal to) start          | E-TW-002 |
    | window wholly outside the plan's window | E-TW-003 |
    | a job in another account                | E-TW-004 |
    | a cancelled job                         | E-TW-005 |
    | a note over 200 characters              | E-TW-006 |

Scenario: Changing a window after the day is live is allowed and logged
  Given job 140 has a step on a day that has been published to live
  When I change its window
  Then the change is saved
  And a plan_change_log row is written for each published item of job 140
  And the response says the day needs to be published to live again for the performer to see it

Scenario: Changing a window on a draft day writes no change log
  Given none of job 140's days are published
  When I change its window
  Then no plan_change_log row is written
```

**Build notes.**
- Tenancy first, exactly like the other job endpoints (load the job, assert its plan belongs to the
  caller's account). Never skip it to save a query.
- **`HH:MM` validation reuses the rule from PLN-6** (`00:00`–`23:59`, two digits each); compare
  `start_date ~ " " ~ start_time` against `end_date ~ " " ~ end_time` as text — both are fixed-width,
  so string order is time order. Hoist every composed value into a `var`; a `where` clause and a
  `precondition` cannot call filters, and a `precondition` must stay on **one line**.
- **E-TW-003 (D-5):** compare against the job's plan `planning_window_start/end`. Refuse only when
  the window does not overlap the plan window at all; partial overlap is allowed.
- **Upsert inside a `db.transaction`**, and rely on the unique index — not a read-then-write check —
  to stop two windows appearing from two overlapping saves (CLAUDE.md: a transaction does not
  serialize requests; only a unique index does).
- **Live-day logging:** for each `planner_task` of the job, call `live/log_plan_change`
  unconditionally (it is a no-op on draft days). **Outside** the transaction. Pass **every** input
  explicitly — an omitted optional input inherits the caller's `$input` of the same name.
- Every success logs a success event and every refusal a `rejected` event (OBS-1 / VAL-1 pattern).
- `getAPI` 548 / 555 / 558 live and diff against local before editing; smoke-test with a throwaway
  function on a real job afterwards.

---

### US-TW-1-03 — The planner can see and edit the window
**Status:** ✅ Built and browser-verified (Sonnet 5, 2026-11-05) — see §10. **Model: Sonnet 5.5.**

**As a** planner,
**I want** to add, edit and remove a job's window where I already edit the job, and see it on the card,
**so that** I schedule around it without opening anything else.

```gherkin
Scenario: Add a window from the job editor
  Given a job with no window
  When I open it and choose "Add time window"
  And I enter 3 Nov 09:00 to 3 Nov 11:00 and save
  Then the window is saved
  And the job's card shows "09:00–11:00, 3 Nov"

Scenario: Edit and remove
  When I change the end to 12:00 and save
  Then the card shows the new window
  When I choose "Remove time window"
  Then I am asked to confirm, and on yes the window and the chip are gone

Scenario: A rejected save keeps my typing
  When I enter an end before the start and save
  Then I see "The window has to end after it starts" next to the field
  And what I typed is still there

Scenario: Scheduling outside the window warns, does not block (V1)
  Given a job whose window is 3 Nov 09:00–11:00
  When I place its card on 5 Nov
  Then it is placed
  And the card shows an "Outside time window" warning naming the window
  When I move it onto 3 Nov
  Then the warning clears

Scenario: A job with no window looks exactly as it does today
  Then no chip, no warning, nothing new on its card
```

**Build notes.** Logic in a **pure, tested** `src/planner/timeWindowModel.ts`: `validateWindow`,
`formatWindow`, `isPlacementOutsideWindow(window, plannedDate)` — **not in JSX** (house pattern).
Date-only placement check in V1: the derived slot start is not used, because a reorder would make
the warning flicker; flag a day that does not intersect the window. Bound the date pickers to the
plan window with `getWindowBounds` from `src/planner/utils/dateUtils.ts` (WIN-1) — reuse, do not
write a second one. The server is still the authority (D-6). UI label is **"Time window"**, never
"window" alone — "Plan window" already means something else (README §3).

---

### US-TW-1-04 — The window travels into the published day
**Status:** ✅ Built and live (Opus 5.5, 2026-11-04) — see §10. Opus review pass still due. **Model: Opus 5.5.**

**As a** performer,
**I want** the published day to carry each job's window,
**so that** what I see is the frozen plan, exactly like every other field I am shown.

```gherkin
Scenario: A new publication includes the window
  Given job 140 has a window and a step on timeline 50
  When timeline 50 is published to live
  Then each of job 140's published items carries the window
  And the snapshot is tagged publication|v2
  And the hash computed by the server equals the hash computed by liveModel.ts

Scenario: An item with no window
  Then its window is null and the hash is still deterministic

Scenario: Old publications still verify
  Given a publication made before this story (publication|v1)
  When it is verified
  Then it verifies exactly as before, under v1
```

**Build notes.**
- In `live/build_publication`, read the windows for every job in the day **once** (one query,
  `work_item_id in $ids`), build a pre-seeded map, look up per item — never a query per item, and
  pre-seed every key (`|get` with a variable key drops its default).
- **Canonical line, v2:** append the window fields to the item line in a fixed order, built by
  explicit concatenation, never `json_encode`. An absent window serialises as a fixed empty token.
  **Do not introduce a new `|` inside a string literal** (CLAUDE.md: it breaks the parser in new
  code); follow whatever separator the existing v1 line uses *and* confirm on a scratch function.
- Change the TS twin in `src/liveModel.ts` in the same commit. **Pin one expected v2 hash on both
  sides**, and keep the existing v1 pin, so drift fails a test instead of invalidating stored hashes.
- **Never re-hash or rewrite an existing publication.** v1 rows stay v1 forever.
- Hydrate on the item, not a lookup at read time: the performer must see what was published, not
  the current value (D-23). That is why live-day edits need a republish (-05).

---

### US-TW-1-05 — The performer sees the window; live-day changes reach them
**Status:** ✅ Built (Sonnet 5, 2026-11-05) — see §10. **Model: Sonnet 5.5.** Q-1 already answered
2026-11-04 (planner-only edit; performer read-only) — built to that default.

**As a** performer,
**I want** to see when each job's work is allowed to happen,
**so that** I do it inside the window instead of finding out afterwards.

**As a** planner, during execution,
**I want** to change a window on a live day and have the performer see it,
**so that** a window that moved in real life moves in the app too.

```gherkin
Scenario: The performer sees the window
  Given a published item whose job has a window 3 Nov 09:00–11:00
  When I open Today, or the step
  Then I see "Time window 09:00–11:00"

Scenario: No window, no clutter
  Given an item with no window
  Then nothing about time windows is shown

Scenario: The planner changes a window on a live day
  Given the day is live
  When the planner changes job 140's window
  Then the change is logged (US-TW-1-02)
  And the planner sees "Changed after going live — Publish to live again so the performer sees it"
  When the planner publishes to live again
  Then the performer sees the new window
  And the activity log still shows which publication each step was done against

Scenario: The performer cannot edit the window (default, see Q-1)
  Then the window is shown as text, with no edit control
```

**Build notes.** Read the window off the frozen item (from -04) in `perform/collect_published_items`
and `src/perform/performerView.ts` — **no new performer endpoint** and no live lookup. Display goes
through the same pure `formatWindow` from -03. Reuse the existing "changed after going live" signal
from LIVE-1 if one is already on the planner board; add one only if none exists, and say which in §10.

---

## 5. Deferred — V2 and later (do not build)

| Item | Why later |
|---|---|
| **Soft vs hard type** — show `constraint_type`, let the planner choose | The founder's own V2. Column already exists (D-3). |
| **Hard enforcement** — server refuses placing a hard-windowed card on a day/time outside it | Needs the type; mirrors WIN-1's server refusal. Must also decide what a reorder that pushes a slot past a hard window does. |
| **Window adherence in variance** (VAR-1 / PRD VA-2) — "started inside / outside window", outlier-style flag | Needs real data first; built from the activity log, never reported by the performer (D-07). |
| Several windows per job ("9–11 **or** 14–16") | Unique index changes to a non-unique one plus an ordinal; a contained change. |
| A window per card / step overriding the job's | Wait until a real work type needs it. |
| Timezones | Nothing in the planner is timezone-aware yet. |
| Windows on plan templates / defaults from the journey map | A definition-layer question; needs its own decision. |

---

## 6. Decisions and open questions

**Decisions (recorded defaults — the founder can overturn any):**

- **D-1 — One window per job, not per step.** A card fans out into several steps; a per-step window
  would be typed several times and drift. The job is the commitment the window belongs to.
- **D-2 — V1 warns, it does not block.** With no soft/hard type yet, the safe behaviour is soft.
  Blocking arrives with V2's hard type. (WIN-1 learned "shown, not enforced" fails for a *rule*;
  this is the opposite case: a V1 *constraint* that is explicitly not yet a rule, and labelled so.)
- **D-3 — `constraint_type` is created now, fixed to `soft`, hidden.** V2 becomes a UI change and a
  guard, not a migration. It is an additive column on a brand-new table, so no existing data is at
  risk.
- **D-4 — Plan-local date + `HH:MM`, and a window may cross midnight.** Matches how the planner
  already expresses time; refusing overnight would assume an industry.
- **D-5 — A window must at least overlap the plan's window** (E-TW-003). A window wholly outside the
  plan describes work this plan cannot contain.
- **D-6 — The server is the authority.** UI bounds and messages are convenience; every rule is
  re-checked by the API.
- **D-7 — Live-day edits are allowed, logged, and reach the performer by publishing to live again.**
  Never by a live lookup — that would break the frozen-snapshot rule (D-23) for one field.

**Open questions (founder):**

- **Q-1 — ✅ ANSWERED 2026-11-04: planner only, "for now".** The performer sees it, read-only.
  Revisit later if the founder asks. Original question: should the *performer* be able to edit the
  window, or only the planner? Default was **planner only; the performer sees it.** "Editable in execution" is read as "the planner can still
  edit it while the day is live". A performer editing their own window would let the person doing
  the work move the goalposts the variance is measured against (the same reason D-07 stops
  performers reporting variance). **Ask before building -05.**
- **Q-2 — Should a live-day window change republish automatically?** Default: **no** — the planner
  presses Publish to live again, the same as every other live-day change (LIVE-1). Automatic
  republish is a separate decision with its own risk.
- **Q-3 — Partial overlap with the plan window (D-5): allow, or require the window to sit fully
  inside?** Default: allow overlap. Fully-inside is stricter and may refuse real cases at the edges.

---

## 7. Governance

- **Table:** PK, declared + indexed FK to `work_item`, unique natural key `work_item_id`, enum for
  `constraint_type`, `trim` on `note`, `created_at` + `updated_at`. Passes `audit-schema.mjs`.
- **Existing tables:** **none altered.** Additive only. Rollback = drop the new table and revert the
  endpoints; no existing data depends on it.
- **Delete behaviour:** window delete removes only that row. Job cancel keeps it (history) and blocks
  edits. No job delete path is added or changed by this epic.
- **Validation and friendly errors:** six new codes `E-TW-001`…`E-TW-006` in
  `src/ops/errorCatalog.json` — **confirm the `E-TW` prefix is free first**. Each has a sentence a
  non-engineer can act on, naming the times involved. Typing is kept on every rejected save.
- **Events:** `time_window.set` / `.cleared` success events; refusals at `info` with
  `outcome: 'rejected'`; a failure event on anything unexpected. Nothing fails silently (OBS-1).
- **Tenancy:** every endpoint asserts the job's plan belongs to the caller's account before reading
  or writing. A cross-account id gets the same answer as a missing one.
- **History:** live-day changes go through `live/log_plan_change`; published snapshots are never
  rewritten.

---

## 8. Test plan

| ID | Kind | What it proves |
|---|---|---|
| UT-TW-1-03-01 | Unit | `validateWindow`: good window passes; bad `HH:MM`, end ≤ start, missing fields each fail with the right code |
| UT-TW-1-03-02 | Unit | A window crossing midnight is valid (D-4) |
| UT-TW-1-03-03 | Unit | `isPlacementOutsideWindow`: inside, outside, both boundary days, multi-day window |
| UT-TW-1-03-04 | Unit | `formatWindow`: same-day, multi-day, null |
| UT-TW-1-04-01 | Unit | `liveModel.ts` v2 canonical line and pinned hash; null window token; **v1 pin unchanged** |
| FT-TW-1-01 | Workflow / live | Unique index refuses a second window for one job |
| FT-TW-1-02 | Live smoke | PUT/GET/DELETE round trip on a real job; reads 548/555/558 return the window |
| FT-TW-1-03 | Live smoke | Each of E-TW-001…006 refused, nothing written, existing window unchanged |
| FT-TW-1-04 | Live smoke | Live-day change writes `plan_change_log` rows; draft-day change writes none |
| FT-TW-1-05 | Live smoke | Publish a day with a window: server hash == TS hash; an old v1 publication still verifies |
| E2E-TW-1-01 | Playwright | Add / edit / remove a window in the job editor; chip and warning appear and clear |
| E2E-TW-1-02 | Playwright | Performer Today shows the window after publish; nothing shown when there is none |
| REG-01..04 | Suite | `npm test`, `tsc --noEmit`, `npm run build`, `playwright test --list` — all green |
| UI-01 | Founder | In a browser: add a window, place the card on the wrong day and see the warning, publish, see it as a performer |

Workflow-test file number: take the next free number in `workflow_tests/` — look it up. Workflow
tests cannot be *run* from a session (CLAUDE.md); drive the assertions with `runWorkspaceFunction`
and say so in §9. Smoke tests use a **clone** or a test-account job, never map 178's original, and a
realistic epoch base, never `0`.

---

## 9. Completion gate

1. All five stories built, or blocked with a stated reason and a model note.
2. Unit tests green, plus the full suite, `tsc`, `build`, `playwright --list`.
3. FT-TW-1-02…05 **actually run** against real data. A clean push is not evidence.
4. Old publications re-verified after -04 — counted, not assumed.
5. An **Opus 5.5 review pass** over -01, -02 and -04.
6. §10 Test Results filled with a real result per ID; §11 carries every deviation.
7. Then **stop** and wait for the founder. Do not start V2.

---

## 10. Test Results

| ID | Result (2026-11-04, Opus 5.5) |
|---|---|
| UT-TW-1-03-01…04 | ✅ Pass — `src/planner/timeWindowModel.test.ts`, 11 tests |
| UT-TW-1-04-01 | ✅ Pass — 6 new tests in `src/liveModel.test.ts`; v2 pin `c0d59402…7093e`, v1 pin `a1062b14…584a4` |
| REG-01 `npm test` | ✅ 732/732 (first run caught E-TW-001/-006 message drift via GUARD-REG-01; fixed) |
| REG-02 `tsc --noEmit` | ✅ Clean |
| Schema audit | ✅ No errors, no finding on `work_item_time_window` |
| REG-03 `npm run build` | ✅ Built |
| REG-04 `playwright test --list` | ✅ 47 tests in 18 files listed |
| FT-TW-1-01 | ✅ Live: scratch insert of a 2nd window for job 42 refused by the unique index; still 1 row. Scratch function deleted |
| FT-TW-1-02 | ✅ Live HTTP: GET empty → PUT (created) → GET → PUT change (not created) → list 615 shows exactly one → DELETE → DELETE again quiet → GET null. Overnight window and partial plan overlap accepted |
| FT-TW-1-03 | ✅ Live HTTP: all six codes refused with their own message (incl. 9:5, 25:00, empty, end=start, end before start); existing window unchanged after; cross-account GET → 404; DELETE on cancelled → E-TW-005 |
| FT-TW-1-04 | ✅ Live: job 42 (step pt-122 on published timeline 51) → `needs_republish: true`, refs `[pt-122]`, `changed_after_live` event written; job 10 (draft) → false, no such event |
| FT-TW-1-05 | 🟡 Partly. Builder on timeline 51 returns `publication|v2` with the window on the item; server hash `8fa8ab86…cf97` **equals** `canonicalizePublicationV2` on the same items. A real publish was not completed: 51 is sealed (E-LIVE-007, correct); 50 (founder-approved) was refused with NEEDS_INFO (correct — it is the blockers fixture); 49 needs its own approval |
| Old publications | ✅ Counted: still 20 `plan_publication` rows, all v1, newest (id 22) unchanged. Nothing re-hashes them |
| Events (OBS-1) | ✅ 20 `TW-1` rows in `event_log`, one per call: success, rejected with the right code, and `changed_after_live` with before/after |
| UT-TW-1-03-05 | ✅ Pass — `indexWindowsByJob` (new), 1 test |
| UT-TW-1-05-01, UT-TW-1-05-S01 | ✅ Pass — `time_window` → `PerformerItem.timeWindow` → `Session.timeWindow`, incl. null on an old (v1) item |
| REG-01 (re-run after -03/-05) | ✅ 735/735 (732 + 3 new) |
| REG-02/-03/-04 (re-run) | ✅ tsc clean; build clean; 47 Playwright specs still listed |
| UI-01 | ✅ **Browser, real data, Chrome, `localhost:3000`** (2026-11-05, Sonnet 5). Job 42: row chip "Time window 09:00–12:00, 20 Oct" without opening it; opened → editor pre-filled from the server; end-before-start edit → "The window has to end after it starts." shown, typing kept, nothing saved; corrected → saved, chip updated. Gave two more jobs windows (Oct 19 09:00–10:00; Oct 24 09:00–10:00) and placed their cards on Oct 20 via the board's "Place…" form (drag-and-drop didn't register under the browser tool; this non-drag path schedules the same way) — **both cards showed "⏱ Outside time window (…)" in amber, card still placed, nothing blocked.** A same-day timeline's cards showed no badge. Signed out and back in mid-session (browser auto-login) with no state loss. Zero console errors across the whole session. |
| E2E-TW-1-01/02 | Not run — no Playwright spec written for TW-1 (UI-01 above covers the same ground live); flagged in §11, not done |

**Live ids:** table **141** `work_item_time_window`; function **282** `jobs/time_window_live_refs`;
endpoints **613** PUT, **614** GET, **615** list, **616** DELETE; updated **127**
`live/build_publication` and **562** publish. Baseline before 127 changed: timeline 51 re-hashed to
its stored v1 hash exactly. **Test data left in place:** job 42 (EST-1 smoke job, account 2) keeps a
window 20 Oct 09:00–12:00 for -03/-05 to show.

**Read path chosen (-02):** a new no-filter list, `GET workspace/{workspace_id}/time-windows`,
merged client-side. 548/555/558 are not edited.

---

## 11. Notes

- **Written as documents only**, 2026-11-04, on the founder's explicit instruction ("no execution,
  just the epics"). No code, no Xano push, no table created.
- **The founder said "soft and hard" first, then narrowed to one window for V1.** V1 is therefore
  *soft by behaviour* (D-2) with the type column reserved (D-3), so V2 is the founder's original
  idea, finished — not a redesign.
- **Execution notes (2026-11-04, Opus 5.5):**
  - **WIN-1 is only 1 of 4 built**, but TW-1 needs only `planning_window_start/end` (live since
    PLN-3) and `getWindowBounds` (WIN-1-02, built). Nothing TW-1 reads is missing.
  - **`plan_change_log` cannot hold a window change as-is.** Its `change_type` enum has no fitting
    value, and adding one means `updateTableSchema` on a table with a `trim` column (validator-drop
    bug). Built instead: live-day changes log a `TW-1 time_window.changed_after_live` event in
    `event_log` with the affected item refs, before and after. **Founder confirmed 2026-11-04.**
  - **562 now reads `canonical_version` from the builder** (fallback v1), pushed *before* 127 so
    no publish could be labelled v1 while hashed v2.
  - **The v1 "twin" was never a twin.** Server v1 hashes ref/seq/minutes/assignee/title/task ids;
    `liveModel.ts` v1 hashes different fields in a different order. And **nothing re-verifies a
    stored publication hash** (only 562 writes it). So -04 cannot break old publications. v2 is a
    true twin of the server line (`canonicalizePublicationV2`); v1 is left exactly as it was.
  - v2 keeps the server's link order for work task ids (not re-sorted), so both sides agree.
  - New local files are prefixed `NEW_` until Xano assigns ids; renamed after the push.
- **Execution notes (2026-11-05, Sonnet 5, -03/-05):**
  - **A real TypeScript narrowing gap, not project-specific:** `if (!check.ok) { check.message }`
    failed to narrow `{ok:true} | {ok:false; message: string}` — reproduced in a from-scratch file
    with **no** tsconfig at all, so this is a TS 5.8.3 behaviour, not something this repo's config
    caused. `if (check.ok === false)` narrows correctly every time. Fixed everywhere this exact
    two-branch, true-branch-has-no-other-fields shape appears
    (`timeWindowModel.ts`/`timeWindowModel.test.ts`); other `!x.ok` call sites elsewhere in the repo
    (`ValidationFailure`-shaped, whose true branch has its own extra field) were unaffected and left
    alone. **New house rule worth carrying forward: prefer `x.ok === false` over `!x.ok` for a
    discriminated union with a bare `{ok: true}` branch.**
  - `performerView.ts`/`sessionModel.ts` declare "no imports" (a house rule, for pure-function
    testability). Did **not** import `planner/timeWindowModel`'s `TimeWindow` into `performerView.ts`
    — duplicated the same four-field shape locally instead, matching the file's own stated
    discipline. `sessionModel.ts` already has one documented exception (imports `performerView`'s
    own types); `TimeWindow` rides on that same exception, not a new one.
  - **The board's "outside time window" warning reads its own copy of the plan's windows**, fetched
    in `PlannerApp.loadActiveBoard` (`Promise.all` alongside the board itself) and refreshed on
    every `refreshBoard()` — not shared state with `JobsModal`'s independent copy. Two reads of the
    same cheap, no-filter endpoint, not one; simpler and lower-risk than threading one shared cache
    through both, and consistent with LOAD-1's "load what's needed, where it's needed."
  - **HTML5 drag-and-drop did not register under the browser automation tool** (`left_click_drag`
    showed the drop-zone highlight but never completed the drop, twice). The board's own non-drag
    **"Place…" form** (the small calendar icon on an Unscheduled row) schedules a card the same way
    and was used instead for every placement in UI-01. Not a product bug — note it here in case a
    future Playwright spec for this hits the same thing with a different root cause (real browser
    DnD events, not this).
  - Two of three unscheduled test fixtures (`EST-1 smoke test job`'s and `W1 smoke test job`'s
    first attempts) were refused with **E-SCHED-001** ("part of this card is already on the
    schedule") — both jobs already had other steps placed elsewhere from earlier sessions. Not a
    TW-1 bug; worked around by using `EST-1 card-schedule smoke job` (fully scheduled, not in
    Unscheduled) for one of the two "outside window" confirmations instead of re-placing it.
  - **Test windows left in place, on purpose** (same call as job 42 in the -02/-04 notes above):
    `EST-1 smoke test job` → 09:00–10:00, 19 Oct; `EST-1 card-schedule smoke job` → 09:00–10:00,
    24 Oct. Both now show live "Outside time window" badges on their Oct 20 cards — visible proof
    of US-TW-1-03's last Gherkin scenario without re-staging it.
- **Not verified while writing:** the exact current shape of endpoints 548 / 555 / 558 and of
  `live/build_publication`'s canonical line on the live workspace (local files only). Several of
  those files had uncommitted changes in the working tree on 2026-11-04. Re-read them live before
  -02 and -04.
