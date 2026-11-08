# EPIC-SCHED-2 — Manual start-time override

**Status:** ✅ **All four stories built and live (2026-11-05/06, Opus 5.5).** Plan reviewed by Opus
5.5 first — corrections in §11; where this file and §11 disagree, §11 wins. Results in §9. Still open:
a real "Publish to live" of a day carrying an override (performer screen seen with a v3 snapshot),
and the founder's call on D-3.
Read `README.md` in this folder first.
**Default model:** **Opus 5.5** for -01, -02, -04 and the review. **Sonnet 5.5** for -03.
**Depends on:** SCHED-1 (`planner_task`, derivation, live), BOARD-1 (the board, live), LIVE-1
(`live/build_publication`, `live/log_plan_change`, live), APP-1 / EXEC-1 (performer app — EXEC-1
is itself still a draft, check its status first).
**Risk:** **medium-high.** One new table (additive), and a change to a function that four
different readers rely on to agree with each other, one of which is the publish-snapshot hash.

---

## 1. Goal

A planner opens a scheduled job and finds "Planned Start" always shows the computed time
(the day's start + everything scheduled before it) and can't be changed. Real schedules have
exceptions — a job genuinely needs to start later or earlier than where it happens to fall in
the queue, without re-ordering every other job on that person's day.

**V1 delivers:** an optional, per-scheduled-task override of the computed start time. Settable
and clearable by the planner, visible everywhere the computed time is visible today (board,
published snapshot, performer's Today/Step screens). **Performers cannot set it** — they view
only, same as the computed time they already see today.

A task with no override behaves exactly as it does today — nothing existing changes.

---

## 2. What exists today (verified 2026-11-05 — re-verify before building)

- `planner_task` (118) has no start-time column. `seq` + `duration_minutes` on every task on a
  timeline, plus `planner_timeline.start_time` (HH:MM, default `08:00`), are the only inputs.
  The derivation itself (start of day + cumulative durations of everything with a lower `seq`)
  is **PLN-7's rule**, confirmed again by `FT-SCHED-1-10`.
- `EditModal.tsx` (~line 1011) renders "Planned Start" as `disabled readOnly` unconditionally
  for a scheduled task, with copy explaining it's computed. This was a deliberate SCHED-1
  decision, not a bug — this epic is the first time overriding it has been asked for.
- The performer already **sees** the computed time, read-only: `sessionModel.ts` /
  `performerView.ts` → `TodayScreen.tsx`'s `plannedStartLabel`, and presumably `StepScreen.tsx`.
  No new "view" work is needed on the performer side — only "keep showing the right number."
- `plan_change_log.change_type` enum already includes `"moved"` — a live-day override can log
  through the **existing** table, unlike TW-1 (which needed a different log destination because
  its new concept didn't fit the existing enum).
- This is independent of TW-1's `work_item_time_window`. A window is an *allowed range*, soft,
  never enforced in V1. This epic is the *actual* time, always exactly one value once resolved.

---

## 3. The data shape (for -01)

New table **`planner_task_start_override`** — one row per scheduled task that has an override.
No row = no override = exactly today's computed behaviour.

| Column | Type | Rule |
|---|---|---|
| `id` | int | PK |
| `created_at` | timestamp | `now` |
| `updated_at` | timestamp | set on every edit |
| `planner_task_id` | int → `planner_task` | **unique** (one override per slot), indexed |
| `start_time` | text `HH:MM` | required, 00:00–23:59 |
| `reason` | text, trim, optional | why it was overridden — max 200, same shape as TW-1's `note` |
| `updated_by` | int → `user` | |

- **Why a side table, not a column on `planner_task`:** `planner_task` carries `trim` on
  `title`, `notes` and `tweak_reason`. `updateTableSchema` silently drops `validators` from any
  table that has them (confirmed three times now: `user`/`event_log`, `journey_stage`/
  `journey_lens`, and the reasoning `work_item_time_window` already used). A side table touches
  nothing that exists.
- **Not a date, just `HH:MM`:** the override doesn't move the task to a different day, only to
  a different time within the day it's already scheduled on. Moving days is still drag-to-day
  on the board, unchanged.
- **Only a scheduled task can have one.** `planner_task.timeline_id = 0` means backlog — there
  is no "computed time" yet to override (E-SCHED-010).
- **Delete behaviour:** deleting the override deletes the row and reverts to the computed time.
  The task is never touched.

---

## 4. MVP scope — four stories

### US-SCHED-2-01 — A scheduled task can hold one start-time override
**Status:** ✅ Live (pushed on Sonnet 5, reviewed on Opus 5.5, 2026-11-05) — table **142**,
`static/tables/142_planner_task_start_override.xs`. **Model: Opus 5.5.**

**As a** planner,
**I want** a scheduled task to be able to carry a manual start-time override,
**so that** I can say exactly when a job starts without it existing as a column the computed
derivation has to special-case everywhere it runs.

```gherkin
Scenario: The table exists and holds one override per task
  Given the new planner_task_start_override table
  When an override is stored for planner_task 900
  Then exactly one row exists for planner_task 900
  And a second insert for planner_task 900 is refused by the unique index

Scenario: Nothing existing changes
  Given every table that existed before this story
  When the table is created
  Then no existing table, column, index or row is altered
  And every existing suite is still green
```

---

### US-SCHED-2-02 — Set, read and clear the override; one shared "effective start" rule
**Status:** ✅ Live (Opus 5.5, 2026-11-05). `planner/start_minutes` (fn 284), `planner/derive_tasks`
(fn 116) now uses it, PUT 617 / DELETE 618 `planner_task/{id}/start-override`. No GET/list endpoint
was needed — every task read already carries `start_override` via `derive_tasks`. **Model: Opus 5.5.**

**As a** planner,
**I want** an endpoint to set or clear a task's override, and one shared function that resolves
"what time does this task actually start,"
**so that** every reader of that time (board, publish, performer) can call the same rule instead
of each re-deriving it and risking disagreement (LOG-1's duplication lesson, CLAUDE.md).

```gherkin
Scenario: Setting an override on a scheduled task succeeds
  Given planner_task 900 is scheduled on a timeline
  When the planner sets its start to "14:30" with reason "Customer asked for afternoon"
  Then the override is stored
  And the effective start for task 900 is now "14:30", not the computed time

Scenario: A backlog task cannot be overridden
  Given planner_task 901 has timeline_id = 0 (backlog)
  When the planner tries to set a start-time override on it
  Then the request is refused with E-SCHED-010
  And no row is written

Scenario: Bad time format is refused
  When the planner submits "2:30pm" instead of "14:30"
  Then the request is refused with E-SCHED-009
  And the field keeps what was typed (no server round-trip clears it)

Scenario: Clearing an override reverts to the computed time
  Given planner_task 900 has an override of "14:30"
  When the planner clears it
  Then the row is deleted
  And the effective start for task 900 is the computed time again

Scenario: A live-day override is logged, an override before publish is not
  Given a day has NOT yet been published
  When its override changes
  Then nothing is written to plan_change_log
  Given the SAME day has since been published
  When its override changes again
  Then a plan_change_log row is written with change_type "moved"
```

**Build notes.** The shared function (tentatively `scheduling/effective_start`) takes a
`planner_task_id` (or a batch of them, for list endpoints — avoid an N-call loop, same PERF-1
lesson) and returns the override's `start_time` if a row exists, else PLN-7's computed value.
Every other story in this epic calls this function; none re-derives the rule.

---

### US-SCHED-2-03 — Planner can edit it from the job/task view
**Status:** ✅ Built + browser-verified on real data (Opus 5.5, 2026-11-06). "Planned Start" in the step's
edit view is editable on a scheduled step; "Use computed time" clears it; the board card shows a
small **SET** marker. Logic in `planner/startOverrideModel.ts` (pure, tested). **Model: Sonnet 5.5.**

**As a** planner,
**I want** to type a new start time directly where I already see "Planned Start,"
**so that** fixing one job's time doesn't require a separate screen.

```gherkin
Scenario: The field becomes editable for a scheduled task
  Given a task that is scheduled (not backlog)
  When the planner opens its edit view
  Then "Planned Start" is an editable time input, not disabled

Scenario: Saving a new time calls the override endpoint
  Given the planner changes "Planned Start" to "14:30" and saves
  Then PUT .../start-override is called with "14:30"
  And the modal shows the new effective time on success

Scenario: A rejected save keeps what was typed
  Given the server rejects the save (e.g. bad format)
  Then the typed value stays in the field
  And the server's own message is shown as-is

Scenario: A backlog task's field stays exactly as it is today
  Given a task with timeline_id = 0
  Then "Planned Start" stays disabled with its existing caption
  ("Start time is assigned upon landing on a timeline.")
```

---

### US-SCHED-2-04 — Every existing reader shows the effective time
**Status:** ✅ Live (Opus 5.5, 2026-11-06). `live/build_publication` → `publication|v3` (server ↔ TS
hash byte-identical, live), `perform/collect_published_items` passes `start_override` through,
`performerView.ts` and `variance/task_report` both use the shared rule. **Model: Opus 5.5.**

**As a** planner or performer,
**I want** the board, the published day, and the performer's screens to all show the same,
possibly-overridden time,
**so that** nobody sees a stale computed number after an override is set.

```gherkin
Scenario: The board reflects an override
  Given planner_task 900 has an override of "14:30"
  When the board loads that day
  Then the card shows "14:30", not the computed time

Scenario: Publishing freezes the effective time, not the computed one
  Given planner_task 900 has an override when its day is published
  Then the frozen snapshot's planned_start for that item is "14:30"
  And re-serialising the stored snapshot still reproduces the same hash
  (no change to the canonical format for an item with NO override)

Scenario: The performer sees the overridden time
  Given planner_task 900's day has been published with the override in place
  When the performer opens Today
  Then that session's plannedStartLabel reads "14:30"
```

**Build notes.** This is the story most likely to touch `live/build_publication` (127) — the
same hash-sensitive function TW-1 modified. An item with **no** override must serialise byte-
identically to today; only an item that HAS one changes what number goes into the existing
`planned_start` slot. This should not need a new canonical version the way TW-1 needed
`publication|v2` — confirm that assumption with a pinned-hash test before writing the real code.

---

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D-1 | Side table (`planner_task_start_override`), not a column on `planner_task` | `updateTableSchema` validator-drop bug — `planner_task` has `trim` fields. |
| D-2 | Planner edits; performer views only | PRD rule: performers log activity, never set schedule or report variance. Confirmed with the founder 2026-11-05. |
| D-3 | **Pin + flow** (changed by the Opus review): an override pins THAT task's start; every later task on the day flows on from it (start = previous start + previous duration), exactly as today. An override earlier than the previous task's end is allowed (overlap is the planner's call, no block). | The first draft chose "no reflow" on the belief that reflow meant rewriting rows. It doesn't — start times are never stored, they're computed on every read, so flowing costs nothing. And "no reflow" breaks the day's order: pin job 2 at 14:30 and job 3 would still show 09:30, i.e. *before* the job it follows. Reversible in one line per implementation if the founder prefers the other way. |
| D-4 | Live-day override changes log to the **existing** `plan_change_log` (`change_type: "moved"`) | Unlike TW-1, nothing new is needed here — the enum already fits. |
| D-5 | TW-1's "outside time window" badge stays date-only in this epic — not made time-aware | Out of scope; a reasonable follow-up once both features have real usage, not before. |

---

## 6. Error codes (continuing the `SCHED` family — `SCHED-1` used 001–003, 005–008)

| Code | Feature | Meaning |
|---|---|---|
| `E-SCHED-009` | `SCHED-2` | Start time isn't a valid `HH:MM`, 00:00–23:59. |
| `E-SCHED-010` | `SCHED-2` | Task is in the backlog (not yet scheduled) — nothing to override yet. |
| `E-SCHED-011` | `SCHED-2` | Task not found, or belongs to a different account/plan. |

---

## 7. Governance

- **Table constraints:** `planner_task_id` unique (one override per slot); delete = delete row,
  task untouched.
- **Validation:** friendly messages per error code above, server is the source of truth (UI
  pre-checks the same format but the server re-validates, per CLAUDE.md's "UI helps, server
  always validates again").
- **Logging:** draft-day changes are silent (same as every other pre-publish edit); a live-day
  change writes `plan_change_log` (D-4). A write/clear failure is never silent (OBS-1 rule).
- **Tenancy:** every call checks the task's workspace/account, same pattern as every other
  planner endpoint.

---

## 8. Test Plan

| ID | Kind | What it proves |
|---|---|---|
| UT-SCHED-2-01 | Unit | Pure format validator for `HH:MM` (shared by client and server) |
| UT-SCHED-2-02 | Unit | `effective_start` resolution logic: override present → override; absent → computed |
| FT-SCHED-2-01 | Functional | Set override on a scheduled task → effective start changes |
| FT-SCHED-2-02 | Functional | Set override on a backlog task → E-SCHED-010 |
| FT-SCHED-2-03 | Functional | Clear override → reverts to computed |
| FT-SCHED-2-04 | Functional | Live-day override → `plan_change_log` row written, `change_type: "moved"` |
| FT-SCHED-2-05 | Functional | Draft-day override → nothing logged |
| FT-SCHED-2-06 | Functional | Publish snapshot hash unchanged for an item with no override (pinned-hash test) |
| UI-SCHED-2-01 | Browser | Edit the field on a real scheduled job, save, see the board and (if published) the
performer's screen reflect it |

---

## 9. Test Results (2026-11-05/06, Opus 5.5)

**Suites:** `npm test` **754/754** (735 before; +19 new), `tsc --noEmit` clean, `npm run build` clean
(the pre-existing chunk-size warning only).

| ID | Result |
|---|---|
| UT-SCHED-2-G1..G5 (TS, `performerView.test.ts`) | ✅ pass |
| UT-SCHED-2-G1..G5 (server, `planner/start_minutes` via runWorkspaceFunction) | ✅ identical numbers: 480/510/570 · 480/870/930 · 600/630 · 480/540/570 · 480/510 |
| UT-SCHED-2-04a performer view honours a frozen override; old snapshot unchanged | ✅ pass |
| UT-SCHED-2-03-01..08 (`startOverrideModel.test.ts`) | ✅ 8/8 |
| UT-SCHED-2-04-01 v3 canonical twin (5 tests, pinned hash `e80d17c5…`) | ✅ pass; v1/v2 pins unchanged |
| REG derive_tasks, no overrides | ✅ byte-identical to before on a 23:00 day that wraps midnight (23:00/23:45/00:45/02:15), a 1-slot day, and a backlog (null starts) |
| FT-SCHED-2-01a..e set / pin two / update (no new row) | ✅ real HTTP, board shows 08:00 · 10:00* · 14:30* |
| FT-SCHED-2-03a..c clear → later slot flows (10:00 + 285m = 14:45); clear again = no-op | ✅ |
| FT-SCHED-2-02 backlog slot → E-SCHED-010 | ✅ 400 |
| FT-SCHED-2-07 "2:30pm", "24:00" → E-SCHED-009 | ✅ 400 |
| FT-SCHED-2-08 201-char reason → E-SCHED-011 | ✅ 400 |
| FT-SCHED-2-09 another account's slot (set and clear) | ✅ 404, nothing written |
| FT-SCHED-2-04 live day: set + clear → `needs_republish: true`, two `plan_change_log` rows `moved` | ✅ rows 4 and 5, timeline 50 only |
| FT-SCHED-2-05 draft day → nothing in `plan_change_log` | ✅ |
| FT-SCHED-2-06 publish snapshot, no override | ✅ every v3 line = the v2 line + one empty field |
| FT-SCHED-2-06b server ↔ TS v3 hash with two overrides | ✅ `b4751898…` on both sides |
| REG collect_published_items on a v2 snapshot | ✅ unchanged + `start_override: ""` |
| REG variance/task_report (job 138, 8 published steps) | ✅ every number identical to the baseline |
| UI-SCHED-2-01 browser, real job "E2E card 1793637936807" (Nov 1-7, Jav, draft day) | ✅ field editable, set 10:15 → card "10:15 SET"; reopen shows "Set by hand" + "Use computed time"; cleared → back to 08:00; zero console errors |
| Performer screen with a published v3 day | ❌ **not run** — needs a real "Publish to live" of a day with an override (same open item as TW-1). Covered by UT-SCHED-2-04a + the collect_published_items check only |

**Test data:** every override created was removed (table 142 empty at the end). Two `plan_change_log`
rows remain on test timeline 50 (REPUB-1 fixture) — the audit trail is append-only by design.

---

## 10. Notes (original draft)

- Raised during real support use of TW-1 on the Nov 1-7 plan (see README §2) — not a planned
  follow-on, a genuine gap found by using the feature.
- `EditModal.tsx`'s hardcoded `disabled readOnly` on "Planned Start" (not `disabled={isLocked}`
  like its sibling fields) is the one line this epic exists to change.
- Confirm EXEC-1's status before -04's performer-facing work — EXEC-1 is itself still a draft
  (`phase-11`); if it has shipped by the time this is built, -04's performer piece may land in
  EXEC-1's own screens instead of the current `TodayScreen.tsx`/`StepScreen.tsx`.

---

## 11. Opus 5.5 review of the plan (2026-11-05) — corrections that override §1–§10

Founder asked for a review on a stronger model after -01 was pushed. Verified against the code,
not the draft's assumptions.

### What was right
- Side table, not a column (D-1). Table 142 live: unique `planner_task_id` index, FK to
  `planner_task` (118) and `user`, `trim` validators intact. Description was missing after the
  push (header comment not sent) — restored with `updateTableMetadata`, validators re-checked intact.
- Planner edits, performer views (D-2).
- `live/log_plan_change` already accepts `change_type: "moved"` and is safe to call on a draft day
  (it does nothing) — D-4 holds, no TW-1-style workaround.
- Error codes `E-SCHED-009`–`011` are unused anywhere in code or catalog.

### What was wrong, and the fix
1. **"Four readers" was a guess.** There are **three implementations** of the start-time rule:
   `planner/derive_tasks.xs` (all planner endpoints), `perform/performerView.ts` (browser), and
   `variance/task_report.xs`. The board doesn't compute its own; it calls `derive_tasks`.
   `planner/utils/planningLogic.ts::recomputeTimelineTaskTimes` is dead code (never called).
2. **The snapshot has no `planned_start` field.** -04's Gherkin ("the frozen snapshot's
   planned_start is 14:30") was impossible as written. Fix: freeze `start_override` ("HH:MM" or
   "") onto each snapshot item. Because the performer and variance read the frozen item, the
   override must be hash-covered → **`publication|v3`** = the v2 line + `|start_override`.
   TypeScript twin `canonicalizePublicationV3` + a pinned hash on both sides, same as TW-1.
   The draft's "should not need a new canonical version" was wrong.
3. **D-3 was based on a false premise** — see the D-3 row: changed to pin + flow.
4. **Shared rule:** a new pure server function `planner/start_minutes` (start time + ordered
   [{key, minutes, override}] → start minutes per key) used by `derive_tasks` and `task_report`;
   the same rule in `performerView.ts` (that file has no imports by design), pinned to the
   server with shared golden cases.

### Edge cases decided here (V1)
- **Backlog:** an override row on a task that goes back to the backlog is ignored (no start
  while unscheduled) and comes back if the task is placed again. Kept, not deleted — deleting
  silently would lose the planner's input.
- **Moved to another day:** the override travels with the task ("this job starts at 14:30").
  The planner clears it in the same edit view.
- **Task deleted:** the override row is orphaned but harmless (every read joins on live
  tasks). Cleanup is GOV-1-shaped hygiene, not V1.
- **Days that run past midnight:** an override is a time of day on the timeline's own date.
  A 23:00 day with a later task overridden to 01:00 means 01:00 *the same date*, i.e. earlier
  in the day. V1 limitation; documented, not solved.
- **What gets logged on a live day:** only the overridden task (the cause), `before`/`after` =
  `{start_override}`. The tasks that flow after it are not logged one by one — they move
  because of this one change.

### Found while reviewing, NOT in this epic's scope (flag for the founder)
- **A published day's start time is not frozen.** The performer (`collect_published_items`)
  and variance (`task_report`) both read the timeline's `start_time` LIVE, so changing a day's
  start after publishing silently shifts the performer's times and the variance baseline. The
  override work doesn't make this worse, but it is the same class of problem. Separate story.
- `planner/utils/planningLogic.ts::recomputeTimelineTaskTimes` and `Inspector.tsx` /
  `PlanCanvas.tsx` look unused — possible dead code, not touched here.

---

## 12. Build notes and deviations (Opus 5.5, 2026-11-05/06)

- **E-SCHED-011 changed meaning:** "not found / other account" is handled by the existing shared guard
  `planner/assert_task` (404 "Task not found", same as every other slot endpoint), so 011 became
  "reason longer than 200". Catalog entries for 009/010/011 added; GUARD-REG-01 passes.
- **No GET or list endpoint.** The side-table rule ("a side table needs its own list read") is met by
  `derive_tasks` itself — every board/task read returns `start_override` per task.
- **Leaving `reason` out of a PUT clears it** (an omitted optional text arrives as `""`). The UI never
  sends a reason today, so this is harmless; a later reason field must always send the current value.
- **The step's whole edit view is still locked on a published day** (existing rule — reopen first). So
  the live-day path (`needs_republish`, `plan_change_log`) is reachable from the API, proven by
  FT-SCHED-2-04, but not from today's UI.
- **Variance with duplicate `seq` values:** the old rule summed only items with a *lower* seq; the shared
  rule walks the frozen order. They differ only if two items share a seq, which the resequencer
  prevents. Noted, not handled.
- **Files:** `static/tables/142_*`, `functions/planner/start_minutes.xs` (new), `derive_tasks.xs`,
  `live/build_publication.xs`, `perform/collect_published_items.xs`, `variance/task_report.xs`,
  `apis/planner/617_*_PUT.xs`, `618_*_DELETE.xs` (new); frontend `performerView.ts`, `liveModel.ts`,
  `planner/startOverrideModel.ts` (new), `plannerApi.ts`, `plannerAdapter.ts`, `types.ts`,
  `EditModal.tsx`, `PlannerApp.tsx`, `DayBoard.tsx`, `errorCatalog.json`, `package.json` + tests.
- **Review:** built on Opus 5.5 throughout (the founder switched before -02). An independent Opus review
  pass is still worth doing before relying on the live-day path.
