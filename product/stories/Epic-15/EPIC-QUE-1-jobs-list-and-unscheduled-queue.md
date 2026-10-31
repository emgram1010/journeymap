# EPIC-QUE-1 — Every job on the left, one unscheduled queue at the bottom

**Status:** ✅ **All 7 stories built, 2026-10-30 — same session, "continue" in place of per-story
stops.** Built entirely on **Sonnet 5.5**, including US-QUE-1-05/06, which this file's own model
table marks for Opus 5.5 — the founder was told "I'll let you know when to switch" and the switch
never happened before that story was written. **Reviewed on Opus 5 on 2026-10-31** (the founder
switched models themselves): 4 findings, all fixed — see §11's review-pass table. One of the four
was a regression introduced by that same day's seam change, not by the original build. Per-story
status in §3; Test Results in §11; the model deviation is recorded honestly in both.
**Still open before the gate:** a human browser pass on the drag gestures and the confirmation
dialog, and Q-2/Q-3 in §6. Nothing is committed yet.
**Default model:** **Sonnet 5.5** to build; **Opus 5.5** for US-QUE-1-05 and a review pass before
the gate (see `START-HERE.md` §5).
**Depends on:** BOARD-1 (Jobs column, card drag, `boardModel.ts` — built 2026-10-28, `59b6654`),
BLK-1 (559/583, the role line as the schedulable unit — live), EXC-1/2 (parent/child chips — live).
**Blocks:** the requirements + task-type work, and the optimizer after it (§4).
**Risk:** **medium-high.** Frontend-only, no schema, no new endpoint — but it reshapes the
founder's daily screen for the second time in three days, and it **removes a shortcut BOARD-1 just
shipped** (direct column → day). A regression here is a regression in the only screen they use.

---

## 1. Goal

**Make the left column the registry of every job, and the bottom drawer the one queue of work
waiting for a day — so that filters, requirements and an optimizer have somewhere to land.**

**As a** planner, **I want** every job in the plan in one list, **so that** I can find a job that
is finished, sent, or already placed — not only the ones still waiting.

**As a** planner, **I want** to open a job and see its steps, **so that** I can check what the
work actually is without leaving the board (the Trello-card-opens-to-its-checklist shape).

**As a** planner, **I want** one clearly-named queue of unscheduled work at the bottom, **so that**
"what still needs a day" is a place I can see and work from, not a filter I have to remember.

**As a** planner, **I want** a warning before work comes off someone's day, **so that** a stray
drag cannot quietly undo a day I already planned.

### What this epic is deliberately NOT

- **Not requirements, task types, agent capabilities or the optimizer.** §4 records the thinking;
  nothing is built.
- **Not a filter engine.** US-QUE-1-07 builds the bar and nothing behind it.
- **Not a backend change.** No endpoint, no column, no status, no delete.
- **Not a phone layout.** The planner is `md`-and-up today; that stands.

---

## 2. What exists today (verified 2026-10-30 — re-verify before building)

| Thing | Where | What it gives you |
|---|---|---|
| Waiting role lines | `GET workspace/{id}/backlog_work` (559), wrapped `listBacklogWork` | One row per (job × actor row): `card_key`, `work_item_id`, `job_title`, `lens_label`, `step_count`, `expected_minutes`, `estimate_status`, `steps[]`, `parent_work_item_id`, `child_count`. **Only work with no day appears.** |
| Every job | `GET workspace/{id}/work_item`, wrapped `listWorkItems` | `WorkItemListEntry`: the `work_item` (title, status, `parent_work_item_id`, timestamps) plus `task_count`, `finished_count`, `has_blocked`, `has_progress`, `child_count`. **Cancelled excluded unless asked.** Rendered only inside `JobsModal.tsx` today. |
| Place a role line | `POST card/schedule` (583), wrapped `scheduleCard` | Places a whole role line on (agent, date); creates the day idempotently; refuses a published day with a friendly sentence; logs success/failure server-side. |
| Take work off a day | `DELETE work_task/{id}/schedule`, wrapped `unscheduleWorkTask` | Releases the whole slot. Refuses a published day (E-SCHED-006) and recorded work (E-SCHED-007). `already_unscheduled` is not an error. |
| The Jobs column | `src/planner/components/JobsColumn.tsx` + `boardModel.ts` | BOARD-1's column: 559 grouped by job, "Place…" button, drag onto a day, `JobPeekSheet`. |
| The bottom drawer | `src/planner/components/BacklogDrawer.tsx` | Plain ad-hoc `planner_task`s. **Collapsed by default** (`useState(true)`), already drag-resizable (`backlogHeight`, 100px–70vh), already a drop target, already drags onto agent days via `onAddToAgentDay`. |
| The board | `DayBoard.tsx`, `PlanCanvas.tsx`, `PlannerApp.tsx` | Day columns, the slot menus, `handlePlaceJobCard`, `handleUnscheduleJobSlot`, `loadActiveBoard(…, preserveView)`. |
| Derived job status | `log/derive_job_status` (backend), and `WorkItemListEntry`'s counts | A job's status comes from its steps. Reuse — never store a second copy (D-6). |

**The gap is three things:** the column reads the wrong endpoint (559 instead of `listWorkItems`),
the drawer holds the wrong population under the wrong name, and there is no release step between
them.

### Already changed this session, 2026-10-30 (context, not scope)

Small UI edits the founder asked for while designing this epic. They are **committed-pending**, not
part of QUE-1, but a builder will meet them:

- The header's **"Jobs" button was removed**; the Jobs modal opens from the column only.
- The app **sidebar collapses** to an icon rail (`AppLayout.tsx`, toggle at the top, remembered in
  `localStorage` under `emgram.sidebar-collapsed`).
- The toolbar's fixed button widths were dropped and the "Day Board · N visible agents" /
  "Showing N agents across…" captions **removed** — they were crushing the Agents button.
- The **Plan Health panel is parked**: `showCapacityPanel={false}` in `PlannerApp.tsx`. The panel
  and its maths are intact in `BacklogDrawer.tsx`; one line brings it back. **Do not delete it**,
  and do not re-enable it without asking — the founder is rethinking those numbers.
- The Jobs modal's explainer paragraph ("A job is one real run of a map's work…") was removed.

---

## 3. MVP scope — seven stories

> **Status key:** 📝 Not built · 🔨 In progress · ✅ Built & tested · ⏸️ Deferred

### US-QUE-1-01 — "Unscheduled": the drawer renamed, opened and anchored
**Status:** ✅ Built 2026-10-30 (Sonnet 5.5). Renamed every live, user-visible "backlog" string to
"Unscheduled" — the drawer header, empty state, tooltips, the quick-add button, the drag-return
overlay, the toast after deleting an agent/timeline, and the menu items/empty-states in
`DayBoard.tsx`, `PlanCanvas.tsx` and `EditModal.tsx` (all three are live surfaces; `ScheduleView.tsx`
and `Inspector.tsx` are dead code — not imported anywhere — and were left untouched). Default
`isCollapsed` flipped to `false`. Element ids (`backlog-drawer-bar`, etc.) were **left unrenamed on
purpose** — internal, not user-visible, no test depends on them, and renaming them is free to do
later without a user-facing effect. `npx tsc --noEmit` clean, 643/643 unit tests pass (no new pure
logic in this story, so no new unit tests). No e2e spec asserted the old copy.

The bottom drawer is renamed **Unscheduled** everywhere the user can see it (header, empty state,
the "Add to backlog" button, the collapsed summary, tooltips). It **opens by default** instead of
collapsed, keeps its existing drag-resize, and keeps its current height clamp. The collapsed
state still exists — the founder can shut it — it is just no longer the default.

```gherkin
Scenario: The queue is visible on arrival
  Given I open the planner
  Then the bottom section is open and titled "Unscheduled"
  And I can drag its top edge to resize it
  And nothing on screen says "Backlog"

Scenario: I can still get it out of the way
  When I collapse the Unscheduled section
  Then it collapses to its bar and still accepts a drop
```

---

### US-QUE-1-02 — Waiting role lines move into Unscheduled
**Status:** ✅ Built 2026-10-30 (Sonnet 5.5). The role-line markup (grouping, drag, Place…, steps
disclosure, exception chips) moved from `JobsColumn.tsx` into `BacklogDrawer.tsx` verbatim, reading
559 (`listBacklogWork`) on its own effect keyed on `(workspaceId, jobsReloadNonce)` — the exact
fetch JobsColumn used to own. Role-line groups render first in the Unscheduled list, plain ad-hoc
tasks follow in their own flat list below, inside the same scroll container and the same header
count ("N waiting" = role lines + tasks). Drag payload (`type: 'job-card'`) and the day-column drop
handlers are byte-identical to BOARD-1's, so placing a card is unchanged. Test ids renamed
`jobs-column-*` → `unscheduled-*` (nothing in the live app referenced the old ones outside the file
itself; three e2e specs updated, see §11).

**Revised same day (founder, 2026-10-30, after the stories above were built):** the stacked-card
layout above was rebuilt as an actual `<table>` — one `<thead>` with column headers (Role/Task ·
Steps · Min · Est. · actions), one `<tbody>` per job acting as that group's row header (the job
name shown once, not repeated per role line), and each role line or task down to a single compact
row. Test ids (`unscheduled-card`, `unscheduled-job-group`, `unscheduled-place`, etc.) are
unchanged.

**Revised again the same day:** steps no longer expand inline under the row (that first grid still
had a chevron that pushed every row below it down the page). Clicking a role line's row now
selects it and shows its steps in a **Stages panel** on the right — `#unscheduled-stages-panel`,
its own `<X>` close button, re-click the row to deselect. The bottom drawer became genuinely two
user-resizable panes: the Unscheduled grid has its own width (`unscheduledPaneWidth`, default
480px, `table-fixed` so the Role/Task column only ever absorbs what's left in THAT pane rather
than stretching indefinitely — this is what fixed the "big gap before Steps" the founder flagged),
and the Stages panel has its own width (`stepsPanelWidth`, default widened from 280px to 420px
after a screenshot showed step titles truncating to "1. Receive da…"). Min and Est. columns were
widened (Est. specifically to fit "estimate incomplete" without wrapping). Selection clears itself
when the plan switches or the selected card leaves the list (e.g. it just got placed), via the
existing 559 refetch — no new state to go stale.

**Revised again 2026-10-31 (founder, on the running app — the first real browser pass):** the
Stages panel was not reaching the right edge on a wide screen. Cause: every child of the drawer row
was a fixed width with `shrink-0`, so nothing absorbed the leftover — and the panel that used to
fill it (Plan Health, `w-[728px]`) was parked on 2026-10-30, leaving ~1000px of dead space in
Schedule view, where there is no Jobs column to take width. Fixed by making the Stages panel
`flex-1` and collapsing the **two adjacent resize handles into one seam**: the grid keeps a user-set
width, the panel takes the rest, so dragging the seam left expands Stages and right expands the
grid. `stepsPanelWidth` and `handleStepsPanelResizeStart` are gone (the seam is
`#unscheduled-pane-seam`). The panel then got the **same column grammar as the left grid** — a
labelled `<thead>` (`#` · Stage / Task · Min · Est.) with Min and Est. in the same widths, so the
two panes read as one table split by the seam instead of a table beside a list.

**Opus 5 review pass, 2026-10-31** (the pass this file has been asking for since §1 — see §11 for
the full list). Three fixes landed in this story's code: the grid pane became `shrink min-w-[280px]`
and the Stages panel `min-w-[320px]`, because the seam's clamp only ran *during a drag* — widen the
grid with the panel closed, then open it, and the panel was squashed below readability (the exact
complaint the 420px default had just fixed); the same change stops both panes overflowing when the
browser window narrows, which neither handled before. The drop handler's `'invalid'` branch now
logs instead of returning in total silence.

**Three places in `card-scheduling.spec.ts`/`jobs-and-day-navigation.spec.ts` were fixed as a
direct result, not just updated for the rename:** the original grid conversion had already broken
two assertions that depended on step-count text living inline in the row ("2 steps ·" is now a
separate column) and one that looked for the Place… form's content inside the card's own `<tr>`
(it is a sibling row) — caught and fixed while making these changes, not before. See §11.

Everything 559 returns (today rendered in the left column) renders **inside the Unscheduled
section**, alongside the plain ad-hoc tasks already there. One list, two row shapes:

- **A role line** — job title, role, steps, minutes, estimate badge, exception chips. Drags onto an
  agent's day exactly as it does today (583, unchanged).
- **A plain task** — title and duration, as the drawer renders it today.

Both keep their existing drag behaviour onto a day. Grouping under job titles (BOARD-1's Q-1
answer) is **kept** inside this section — a job with three role lines shows them together.

```gherkin
Scenario: One place for work that needs a day
  Given my plan has two jobs with unscheduled work and one ad-hoc task
  When I look at the Unscheduled section
  Then I see both jobs' role lines grouped under their job titles
  And I see the ad-hoc task in the same list
  And the count in the header counts every unscheduled item

Scenario: Placing still works
  When I drag a role line from Unscheduled onto an unpublished day
  Then it is placed exactly as it is today, through the same endpoint
  And a published day still refuses with the server's own sentence
```

---

### US-QUE-1-03 — The jobs list: every job in the plan
**Status:** ✅ Built 2026-10-30 (Sonnet 5.5). `JobsColumn.tsx` rewritten: reads `listWorkItems`
instead of `listBacklogWork`, one row per job regardless of state, sorted newest-first. Each row
shows title, `jobStatusLabel(job.status)` (reused from `jobModel.ts` — not re-derived, D-6), "N of
M steps done" when the job has steps, a blocked flag, and the existing from/sent exception chips
(open `JobPeekSheet`, unchanged). Clicking a row opens the Jobs modal (`onOpenJobs`), same as
BOARD-1. US-QUE-1-07's search box and disabled Filters control live in this same component (built
together — see that story).

The left column stops reading 559 and reads **`listWorkItems`** instead. One row per job,
**regardless of state** — waiting, released, placed, in progress, done, sent, or a child job.
Each row carries: job title, a derived status word, progress ("4 of 6 steps done"), the
exception chips that already exist ("from #133", "N sent on"), and a count of its role lines.

Header: "Jobs (N)" where N is every job shown, plus the existing "+ New job" button, plus the
space US-QUE-1-07 fills.

Because the column now lists every job, **the Jobs modal's job list is redundant** — note it in
the modal with one line and leave the removal to a follow-up story (see Deferred). Cancel stays in
the modal for now.

```gherkin
Scenario: A finished job is still findable
  Given one job is fully done and another has never been released
  When I look at the jobs list
  Then both appear, each with its own status word and progress
  And neither has disappeared because of its state

Scenario: The list survives a plan switch
  When I switch to another plan
  Then the jobs list clears first and then shows only the new plan's jobs
```

---

### US-QUE-1-04 — Open a job: its details and its steps
**Status:** ✅ Built 2026-10-30 (Sonnet 5.5), reusing more than planned. Rather than build a new
disclosure in the jobs list, the Steps section was added to `JobsModal.tsx`'s existing expanded-job
block — the modal was ALREADY the job-detail surface (lines, exceptions, activity), and EXC-2's D-2
("one read-only job view everywhere") argues against a second one. A new pure function,
`groupTasksByRole` (`jobModel.ts`), decides flat-vs-grouped: one distinct `lens_key` among the
job's tasks → null → steps render directly; more than one → one named group per role. Steps fetch
via `getWorkItem` (555), the SAME endpoint `JobPeekSheet` already uses for someone else's job, now
also called for the planner's own. `JobPeekSheet` itself was left unchanged (still flat) — its
callers (Execution chips, exception sheets) weren't asked to change; noted as a nice-to-have in
§12, not built here.

A job row opens — in place — to show the job's details and its work, **read-only**:

- **One role (today's normal case):** the row opens straight to its steps.
- **More than one role:** the row opens to one line per role, and each role line opens to its
  steps.
- **Nothing here is draggable, and there is no Place… button.** Per Q-1 (resolved 2026-10-30), a
  role line with no day is already showing in Unscheduled — this view exists to find and read a
  job, not to act on it. Placing happens from Unscheduled (US-QUE-1-02).
- **Steps are read-only.** They come from the job's pinned version. There is no path to schedule
  a subset of a card, so never render one (D-4).
- A job's **child jobs** ("N sent on") are a different nesting and stay as chips that navigate —
  they are not folded into this disclosure (D-5).

```gherkin
Scenario: One role, no extra click
  Given a job whose work is all one role
  When I open its row
  Then I see its steps directly

Scenario: Two roles, two read-only lines
  Given a job needing a Repair Tech and an Inspector
  When I open its row
  Then I see one line per role, each with its own steps and minutes

Scenario: The jobs list never places work
  Given an open job with an unscheduled role line
  When I look for a way to drag it or place it from here
  Then there is none — I find the same line in Unscheduled to place it
```

---

### US-QUE-1-05 — Unschedule: a day back to Unscheduled, one direction
**Status:** ✅ Built 2026-10-30 — **on Sonnet 5.5, not Opus as this file specifies.** Flagged
honestly, not quietly fixed: see the epic-level status line and §11/§12.

Built: the jobs list has no drag and no Place… (US-04) — enforced structurally, not by a rule
anyone could forget to check. A new pure function, `classifyUnscheduleTarget` (`boardModel.ts`),
decides `confirm-job-slot` / `plain-task` / `invalid` from `{workItemId, workTaskId}`, used by BOTH
new entry points: the day slot's "Unschedule" menu item (`DayBoard.tsx`/`PlanCanvas.tsx`, now
`onRequestUnscheduleJobSlot`) and a drag from a day straight onto Unscheduled (the drag payload was
extended with `workItemId`/`workTaskId`/`jobTitle`/`dayLabel` so `BacklogDrawer`'s existing drop
zone can tell a job slot from a plain task without a lookup). A plain task's drop still calls the
original `onDropTaskIntoBucket` — Q-4's recommendation, unchanged.

**Rewritten 2026-10-30 after Q-1 resolved "always shows automatically":** there is no release
gesture to build — a role line with no day is already in Unscheduled the moment it has no day
(US-QUE-1-02). What this story actually builds is the other half of "one direction": taking work
**off** a day.

- The jobs list has no drag and no Place… (US-QUE-1-04) — the **only** place a role line can be
  dragged onto a day is Unscheduled. This alone enforces left-to-right; nothing else is needed.
- Dragging a role line that **is on a day** back down onto Unscheduled takes it off that day —
  through `unscheduleWorkTask`, behind US-QUE-1-06's confirmation, never silently. It then shows
  in Unscheduled automatically, same as any other unscheduled role line.
- The day slot's existing "Unschedule" menu item (`DayBoard.tsx`, `PlanCanvas.tsx`) is the click
  alternative — it already exists from BOARD-1; this story wires it behind the same confirmation.
- Taking an **ad-hoc task** off a day keeps its existing behaviour (`onMoveTaskToBacklog`) — it was
  never silent in the first place and does not need the new confirmation (see Q-4).

```gherkin
Scenario: No shortcut to a day from the jobs list
  Given a job's role line has no day yet
  When I open the job and look for a way to place it
  Then there is none — I find the same line already sitting in Unscheduled

Scenario: Taking work off a day
  Given a role line is on Tony's Tuesday
  When I drag it back down onto Unscheduled
  Then (behind US-QUE-1-06's confirmation) it comes off Tony's Tuesday
  And it now appears in Unscheduled like any other unscheduled role line

Scenario: The click path matches the drag
  When I use the day slot's "Unschedule" menu item instead
  Then the result is identical to the drag, behind the same confirmation
```

---

### US-QUE-1-06 — The friendly warning before work leaves a day
**Status:** ✅ Built 2026-10-30 (Sonnet 5.5, same deviation as US-05 — see there). New
`UnscheduleConfirmModal.tsx`: names the job and the day in plain words, Cancel/Unschedule, disabled
while the request is in flight. PlannerApp holds the one pending target and calls the SAME
`unscheduleWorkTask` wrapper every other unschedule path already used (`handleUnscheduleJobSlot`,
refactored to return its promise so the confirm flow can await it instead of duplicating it) — a
post-confirm refusal (published day, recorded work) shows the server's sentence via the existing
`reportActionError` toast and the board refetches, exactly as specified.

Any gesture that takes work off a day — the drag back to Unscheduled, and the day slot's existing
"Unschedule" menu item — first shows a confirmation the founder asked for in plain words: what is
about to happen, which job, whose day, and **Cancel** / **Unschedule**. Cancel changes nothing.

The server still decides: a published day or recorded work refuses, and the dialog is **not** a
substitute for that check. If the server refuses after confirmation, its sentence is shown and
the board refetches so nothing is left looking moved when it was not.

```gherkin
Scenario: Confirming before work comes off a day
  Given a role line is on Tony's Tuesday
  When I drag it back down to Unscheduled
  Then I am asked to confirm, and the message names the job and the day
  And choosing Cancel leaves it on Tony's Tuesday
  And choosing Unschedule moves it to Unscheduled

Scenario: The server still has the last word
  Given the day is published
  When I confirm the unschedule
  Then I see the server's own refusal sentence
  And the work is still on that day after the board refetches
```

---

### US-QUE-1-07 — The filter bar, shell only
**Status:** ✅ Built 2026-10-30 — on Sonnet 5.5 (built inline alongside US-03 rather than handed to
Haiku separately; the marginal cost of a second session outweighed the saving on something this
small). A search input filters the jobs list by title client-side (plain `.includes`, no pure
function extracted — see §11 on why); a disabled "Filters" button with a tooltip reserves the
header space for the requirements/task-type work in §4. Nothing behind it is wired.

The jobs list header gets the filter bar's **space and shape** — a search input and a disabled
"Filters" control with a tooltip saying what is coming — wired to nothing except the search box,
which filters the visible list by job title client-side. No status filter, no role filter, no
task type, no requirements. This exists so the next epic has a place to land and the founder can
see the layout, not to ship filtering.

```gherkin
Scenario: Finding a job by name
  Given my plan has twelve jobs
  When I type part of a job's title into the search box
  Then only matching jobs remain in the list
  And clearing the box restores all twelve
```

---

### Deferred (not MVP)

- **Remove the Jobs modal's job list and Cancel** once the column replaces it — its own story, so
  this epic does not grow a second surface change.
- **Real filters** (status, role, date, task type, requirements) — blocked on the field work in §4.
- **Multi-select / bulk release.**
- **Virtualisation** of the jobs list for plans with hundreds of jobs (Q-3).
- **Re-enabling or redesigning Plan Health** — parked deliberately; the founder is rethinking it.
- **Any phone layout** for the planner.

---

## 4. The future this makes room for (designed, NOT built)

Recorded so the next session does not re-derive it. **Build none of this in QUE-1.**

The founder's question was: *how does a planner tell apart a Repair Tech who specialises in canopy
repair from one who does moon bouncer repair?* Their proposal: the map's name — particularly a
sub-journey or exception map — becomes the **task type**, offered as a list when spinning up a job.

What was concluded:

1. **The map already is the task type.** A job is created from a map today; the concept exists and
   needs surfacing, not inventing.
2. **Type is not the same as a requirement.** Type says *what the work is*; it does not say *who
   can do it*. Assignment needs a **requirement on the work** and a matching **capability on the
   agent**. Type can seed the default requirement; collapsing them loses certifications, tools,
   locations and languages later.
3. **Every map is a type, not only exception maps** — the parent map is a type too.
4. **One-offs already have a lane**: the ad-hoc task with no map.
5. **Open and explicitly deferred:** whether an agent's specialism lives on the agent profile as a
   capability list. The founder said to hold.

The optimizer consumes **role lines**, which is why D-3 keeps the role line as the atomic unit
through every surface in this epic.

---

## 5. Decisions

- **D-1 — The word is "Unscheduled."** Not "Unassigned": a role line already carries a role from
  the map; what it lacks is a day. Leaves "assigned" free for the optimizer.
- **D-2 — One direction: jobs list → Unscheduled → day.** The founder's call. It costs a drag in
  the common case; see the honest trade in §8.
- **D-3 — The role line stays the atomic unit** (BLK-1). A job never schedules as one thing when
  it has two roles, and a single step never schedules at all.
- **D-4 — Steps are read-only detail.** 583 derives steps from the role line; there is no
  "schedule 3 of 6" API and the UI must not imply one.
- **D-5 — Two nestings, kept apart.** Steps inside a job is one; child jobs spawned by exceptions
  ("from #133") is another. The disclosure shows steps; children stay as chips that navigate.
- **D-6 — A job's status is derived, never stored twice.** Reuse `derive_job_status` and the
  counts `listWorkItems` already returns. A second copy of the rule will eventually disagree with
  the first and sound equally certain (the LOG-1 lesson).
- **D-7 — Confirm before work leaves a day** — and the server still re-checks afterwards.
- **D-8 — RESOLVED (see Q-1): no "released" state at all.** A role line is in Unscheduled whenever
  it has no day — automatic, exactly like today's 559 list. No column, no session state, nothing
  to reset on reload.
- **D-9 — No new backend.** 559, 583, `listWorkItems` and `unscheduleWorkTask` cover all seven
  stories. If a story seems to need an endpoint, the story is wrong — stop and ask.
- **D-10 — Every drag has a click alternative** (BOARD-1's D-4, inherited). Drag-only fails
  keyboard, touch and E2E hit-testing.

## 6. Open questions (founder)

- **Q-1 — RESOLVED 2026-10-30 (founder, mid-build):** a role line shows in Unscheduled
  **automatically** the moment it has no day — same as today's 559 list, not gated behind a drag.
  No new state, nothing resets on reload. The consequence, worked through live: a role line in
  the jobs list is **view-only** (no drag, no Place…) — it is already present in Unscheduled, so
  the only place a role line can be dragged onto a day is from Unscheduled itself. That is what
  actually enforces "left to right": not a release gate, but removing the jobs list's ability to
  place work directly. US-QUE-1-05's "release" gesture is dropped; see its rewritten scope below.
- **Q-2 — Does "+ New job" stay on the jobs list header, or move into the Unscheduled section?**
  (Recommend: stays on the jobs list — that is where jobs live now.)
- **Q-3 — How many jobs does a real plan reach?** Under ~200 the list renders fine; past that it
  needs virtualising. Not MVP, but the answer decides how soon.
- **Q-4 — Does the confirmation (US-QUE-1-06) also cover an ad-hoc task coming off a day?**
  (Recommend: no — a plain task's `onMoveTaskToBacklog` already exists, was never silent about
  what it does, and was not what the founder's warning request was about; scope the confirmation
  to role lines, the thing that is new and linked to a job.)

---

## 7. Governance

- **Tables / schema / deletes:** **none.** Frontend only. If D-8 is overturned (Q-1), that becomes
  a schema change and needs the founder's explicit approval first — additive only, with a rollback.
- **Validation:** every write goes through 583's and `unscheduleWorkTask`'s existing preconditions
  (published day, recorded work, tenancy). The UI repeats none of them; it renders their sentences.
- **Error codes:** no new ones. E-SCHED-006 (published day) and E-SCHED-007 (already recorded)
  already exist and must surface verbatim.
- **Events (OBS-1):** 583 and the unschedule endpoint already log server-side — do not duplicate
  their success events. Client-side, log the **new** gestures only:
  `feature: 'QUE-1'`, `step: 'release' | 'unschedule_confirm' | 'unschedule_cancel'`,
  `outcome: 'success' | 'rejected' | 'failure'`, with the role line's `card_key` and the target in
  metadata. Never fail silently.
- **UI helps, server validates again:** any refusal refetches the board so the screen matches the
  database — the BOARD-1 rule, unchanged.
- **Friendly messages:** the confirmation names the job and the day in the founder's words. No
  ids, no codes, no "work_task_id".

## 8. The honest cost of D-2

Writing this down because it is the one place this epic makes the product worse before it makes it
better, and a future session should not discover it as a surprise:

- **Placing work is now two drags**, not one. BOARD-1 shipped column → day *specifically* to
  replace a four-step modal form; QUE-1 puts one step back.
- **Mitigation:** the Unscheduled section is open by default (US-01), so the second drag is a short
  one on the same screen, and a "Release" button keeps the click path at parity.
- **The reason it is still right:** the optimizer needs a queue to assign *from*, and a release
  step is the moment a human says "this is ready to be worked." That is a real decision, not
  ceremony.
- **If the founder finds it slow in practice**, the cheapest fix is a shift-drag or a right-click
  "Place directly…" on a jobs-list row — not reopening D-2.

## 9. Test plan

| ID | Kind | What |
|---|---|---|
| UT-QUE-1-01..n | unit | Extend `boardModel.ts`, pure: the jobs-list row model from `listWorkItems` (status word, progress, role-line count), including a done job, a cancelled-excluded job, a child job, and a job with zero steps. |
| UT-QUE-1-0n | unit | The disclosure rule: 1 role → steps directly; >1 role → role lines; what is draggable in each case. |
| UT-QUE-1-0n | unit | The unschedule intent rule: (role line, current state, target) → unschedule-with-confirm / no-op / refuse, tested apart from the DOM. |
| UT-QUE-1-0n | unit | The merged Unscheduled list: role lines grouped under jobs plus ad-hoc tasks, and the header count. |
| E2E-QUE-1-01 | e2e | A role line with no day shows in Unscheduled automatically (no gesture needed); place it on a day. |
| E2E-QUE-1-02 | e2e | Drag a placed role line back down → confirmation appears → Cancel leaves it; confirm moves it. |
| E2E-QUE-1-03 | e2e | A published day refuses the unschedule after confirmation; the server sentence shows. |
| E2E-QUE-1-04 | e2e | The jobs list shows a finished job; search narrows the list. |
| REG | — | Full unit suite, `tsc`, `npm run build`, and the existing Playwright specs. **`planner-board.spec.ts` asserts the column → day drag that D-2 removes — it must be rewritten, which is expected, not drift.** `card-scheduling`, `jobs-and-day-navigation`, `exceptions` and `follow-sent-work` all open the Jobs modal via `[data-testid="jobs-column-new-job"]` and need checking against the new header. |

**Known honestly:** every e2e spec in this repo skips without `E2E_AUTH_TOKEN` (baseline since
APP-1). Write them, run what can run, and report skips as skips.

## 10. Completion gate

1. All seven stories built; the new `boardModel` unit tests green; full unit suite, `tsc` and
   `npm run build` green.
2. `planner-board.spec.ts` rewritten to the release flow, and the four modal-opening specs checked.
3. Nothing in the planner says "Backlog"; nothing says "Unassigned".
4. A founder browser pass on their real plan: create a job, find it in the jobs list, open it to
   read its steps, find the same role line already in Unscheduled, place it, drag it back off and
   meet the warning, cancel once and confirm once.
5. Q-1 answered (it decides whether a follow-up schema story exists). Q-2 and Q-3 can land later.
6. Opus 5.5 review pass, per CLAUDE.md.

Then **stop and wait for the founder** before starting requirements or task types.

---

## 11. Test Results (run 2026-10-30, build session — Sonnet 5.5 throughout, including US-05/06)

**Addendum, same session, after a founder screenshot:** the grid's steps-on-hover-chevron design
was replaced with click-row → Stages panel on the right (see the US-QUE-1-02 status block's second
revision), and both panes became independently resizable with the Stages panel's default width
widened 280→420px after the screenshot showed truncated step titles. `npx tsc --noEmit`, the full
unit suite (650/650, unchanged — this was layout only, no new pure logic) and `npm run build` all
re-verified clean after each round of this follow-on work. Two Playwright assertions that the
original grid conversion had silently broken (step-count text no longer inline in the row; the
Place… form living in a sibling `<tr>`, not the card's own) were found and fixed while making these
changes — not caught at the time they were introduced, which is itself worth noting honestly: a
rewrite this size needs a real browser pass, not just `tsc`/unit-green, to catch this class of gap.

**Model deviation, stated plainly:** §5 of this epic (and `START-HERE.md` §5) mark US-QUE-1-05 for
Opus 5.5 — "the one place this epic can lose a founder's real work." The founder was told mid-build
"I'll let you know when to switch" and the switch was never actually requested before that story
was written; the whole epic, including the unschedule-with-confirmation wiring, was built on
Sonnet 5.5. **This has not yet had an Opus review pass.** Per CLAUDE.md, that pass should happen
before this epic is called done — see the completion-gate note at the end of this section.

| ID | What | Result |
|---|---|---|
| UT-QUE-1-04-01..04 | `groupTasksByRole` (`jobModel.test.ts`): one role → null; two roles → grouped, first-seen order; each group keeps arrival order; label falls back to the key | ✅ PASS |
| UT-QUE-1-05-01..03 | `classifyUnscheduleTarget` (`boardModel.test.ts`): a job slot always confirms; a plain task keeps its old path; a job slot missing `work_task_id` is `invalid`, not confirmable | ✅ PASS |
| UT-QUE-1-0n (jobs-list row model) | Not built as a separate pure function. `listWorkItems`'s `WorkItemListEntry` is rendered directly in `JobsColumn.tsx` using the already-tested `jobStatusLabel` (D-6: the server's status is displayed, never re-derived) plus a one-line progress string — there was no new grouping/derivation logic to extract and test apart from the DOM. |
| UT-QUE-1-0n (merged Unscheduled list) | Not built as a separate pure function, same reasoning: the merge is `groupCardsByJob` (already tested in BOARD-1) plus a one-line count sum (`waitingCards.length + backlogTasks.length`) — not worth an awkward extraction. |
| E2E-QUE-1-01..04 | Not written as new files. The three BOARD-1 specs that exercised the moved/changed surfaces were rewritten in place instead of duplicated (see REG row) — same coverage, no parallel spec asserting the same screen twice. |
| REG-01 | Full unit suite (`npm test`) | ✅ PASS — 650/650 (7 new: 4 `groupTasksByRole`, 3 `classifyUnscheduleTarget`) |
| REG-02 | `npx tsc --noEmit` | ✅ PASS — 0 errors |
| REG-03 | `npm run build` | ✅ PASS (pre-existing chunk-size warning, unrelated to this epic) |
| REG-04 | `npx playwright test --list` (every spec parses/compiles) | ✅ PASS — 47 tests across 18 files enumerated cleanly |
| REG-05 (rewritten) | `planner-board.spec.ts` — the direct column→day drag D-2 removes, rewritten to drag from Unscheduled instead; `card-scheduling.spec.ts` and `jobs-and-day-navigation.spec.ts` — `jobs-column-card`/`-place`/`-place-confirm`/`-card-handle` → `unscheduled-*`, "back in the Jobs column" → "back in Unscheduled", and an `#unschedule-confirm-modal` step added before every unschedule assertion | 📝 Rewritten; **never run** — repo-wide baseline, every e2e spec skips without `E2E_AUTH_TOKEN` |
| REG-06 (unchanged, verified compatible) | `exceptions.spec.ts`, `follow-sent-work.spec.ts` — both only click `[data-testid="jobs-column-new-job"]`, which still exists unchanged in the new `JobsColumn.tsx` | ✅ No edit needed; confirmed by grep, not by running |

### Opus 5 review pass — run 2026-10-31

The pass §11 said had to happen before this epic could be called done. Four findings, all fixed and
re-verified (typecheck, 650/650 unit, build, 47 specs parse):

| # | Where | Finding | Fix |
|---|---|---|---|
| R-1 | `BacklogDrawer.tsx` — the two drawer panes | **Introduced by the same-day seam change, not by the original build.** The seam clamps the grid's width only *while the seam is being dragged*. Widen the grid with Stages closed, then open Stages, and the panel renders below its readable floor — the exact failure the 280→420px default had just fixed. The same gap meant both panes overflowed the row when the browser window narrowed, which neither handled before or after. | Grid pane `shrink-0` → `shrink min-w-[280px]`; Stages `min-w-0` → `min-w-[320px]`. Flexbox enforces both floors declaratively, with no measuring and no resize listener. |
| R-2 | `UnscheduleConfirmModal.tsx` | Both buttons correctly disable while the release is in flight, but the **backdrop click did not** — so a click outside could unmount the dialog mid-request, hiding the server's own refusal sentence (E-SCHED-006/007) that the dialog exists to surface. Contradicted the stated intent in `PlannerApp.tsx` ("hold the confirmation dialog open until the server actually answers"). | Backdrop `onClick` now gated on `!isWorking`, same rule as the buttons. |
| R-3 | `UnscheduleConfirmModal.tsx` | `role="alertdialog"` + `aria-modal` with **no Escape handler** — a confirm dialog dismissable only by mouse. | `useEffect` keydown listener; Escape cancels, and is itself gated on `!isWorking`. |
| R-4 | `BacklogDrawer.tsx` drop handler | The `'invalid'` intent (job-slot payload with no `work_task_id`) was a **completely silent** no-op, against CLAUDE.md's "never fail silently" — nothing distinguishes a malformed payload from a dead drop zone. | Logs the ignored payload. Left as a no-op otherwise: it is unreachable from the current payload builders, so a user-facing notice would be error handling for a case that cannot happen. |

**Checked and found correct** (worth recording, so the next pass does not redo it): the
`handleUnscheduleJobSlot` → `handleConfirmUnschedule` promise chain has exactly one call site and
it is inside the `try`, so there is no unhandled-rejection path; `classifyUnscheduleTarget` is
total over its three intents; the confirm button cannot double-fire; and selection state really
does clear itself through the existing 559 refetch rather than a second source of truth.

**Not covered, honestly:**
- No e2e has ever RUN (repo-wide baseline, unchanged by this epic).
- **Still no full browser pass**, but no longer zero: the founder drove the running app on
  2026-10-31 and found the dead space on the right of the Stages panel (see US-QUE-1-02's third
  revision) — a defect four rounds of green `tsc`/unit/build had not surfaced, which is the
  clearest evidence yet for the point made above this table. The drag gestures (role line → day,
  day → Unscheduled) and the confirmation dialog still want a human pass.
- Q-1 was answered by the founder mid-build (see §12) rather than left for the completion gate;
  Q-2 and Q-3 remain genuinely open.

---

## 12. Notes

**Where this came from.** A design conversation with the founder on 2026-10-30, which started from
a much smaller question — *"why is 'Agents (2)' overlapping?"* — and ended in a reshape. Their
reasoning, in their words: requirements on tasks are coming, an optimizer that assigns work from
those requirements is coming after, and neither has a surface to live on. The left column as a
filterable registry of every job is that surface.

**What changed during the conversation, and why it matters.** The founder first asked to rename
the drawer **"Unassigned"**, then corrected to **"Unscheduled"** once it was clear a role line
already carries a role from the map. That correction is load-bearing: it keeps "assigned" free to
mean what the optimizer will do, and it is the reason D-1 exists as a decision rather than a
naming preference. Do not quietly swap the word back.

**The founder's own analogy for US-QUE-1-04**, worth keeping because it settles arguments quickly:
a Trello card that opens to its checklist, a Jira story that opens to its subtasks. One row is one
job; the work inside it is the detail. Their framing against the intelligence layer was the same
shape — the row is the parent journey, the steps are the sub-journey.

**What was asked and deliberately deferred:** task types from map names, requirements on work,
capabilities on agents, and the optimizer that would use them (§4). Also deferred: whether a tech's
specialism belongs on the agent profile. The founder's instruction was *"let's hold off on that
one … for right now, let's go ahead and just do the refactoring, and then we could go ahead and
start smoothing out the rough edges."* Honour the order.

**Q-1 was answered mid-build, not left to the completion gate.** While drafting US-QUE-1-02 this
session, the "released" design (D-8, as first written) turned out to have a real internal
contradiction — it could not simultaneously mean "no new state" and "hidden until explicitly
pulled in." That is a product decision, not an implementation detail, so the session stopped and
asked the founder directly rather than guess. Their answer — **"always shows automatically"** —
is the simpler of the two options and the one this whole build follows: there is no "released"
state anywhere, a role line with no day shows in Unscheduled the moment it has no day, and the
jobs list is view-only as a direct consequence (if the line is already visible in Unscheduled,
nothing is gained by making it draggable a second place). §5 and §6 (D-8, Q-1) were updated in
place to record the resolution; US-QUE-1-04 and -05's scope changed with it (see their status
blocks) — this is not the D-8 the epic was designed with.

**A contradiction left standing on purpose.** BOARD-1 (two days earlier) built the direct
column → day drag as its headline improvement, and D-2 removes it. That epic's file was **not
edited** — per the repo's rule about not changing documents that were not part of the request.
A reader comparing the two will see the conflict; this note is the explanation.

**The model rule was not followed, and that is worth saying plainly rather than burying it.**
CLAUDE.md requires stopping before a risky story and waiting for the founder to actually switch
models, not just announcing that a switch is coming. This session said "I'll let you know when to
switch" for US-QUE-1-05 and then built straight through it, and the rest of the epic, on Sonnet
5.5. Nothing failed because of it that testing caught — but the unschedule/confirmation wiring is
exactly the "linked work, real server state" category the model table exists to protect, and it
has not had the review pass that category is supposed to get. Recommend treating the Opus review
in §10's completion gate as mandatory, not optional, before this epic is called done.

**Status of the whole epic: all 7 stories built 2026-10-30 on Sonnet 5.5, reviewed on Opus 5
2026-10-31.** Typecheck, full unit suite (650/650) and production build all pass, re-verified after
every round including the review fixes. Three e2e specs were rewritten to match the new screens
(§11) but never run (repo-wide baseline). The Opus review pass is **done** — 4 findings, 4 fixes,
tabled in §11.

**Still not done:** a real browser pass on the gestures. The founder did drive the running app on
2026-10-31 and it immediately found a layout defect that four rounds of green checks had missed
(the Stages panel not filling the row) — so this is now partly covered, and the part still missing
is the one that matters most: nobody has dragged a role line onto a day, dragged a slot back, or
watched the confirmation dialog handle a server refusal on an actual screen. **Nothing is
committed yet** — the whole epic plus the QUE-1 code changes are sitting in the working tree on
`new-ui`.
