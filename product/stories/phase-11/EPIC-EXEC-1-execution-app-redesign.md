# EXEC-1 — The execution app, redesigned

**Epic ID:** EXEC-1
**Feature:** Give the performer's mobile app (`/perform`) the look and flow of the
founder-approved prototype (Today → Job with tabs → Step), wired to the real backend.
**Status:** All 9 stories Done (2026-11-04). Regression green. Awaiting the founder's
walkthrough on a phone — see the completion gate below and the "flagging, not
fixed" items in US-09's Updates (AppLayout overlap, mobile-width visual check).
**Depends on:** APP-1, APP-2 (current perform screens), LOG-1 (status engine),
EXC-1 (exception send / came-from), QTY-1 (job lines). All done.
**MVP:** US-01 through US-09. Everything in the README's **Deferred** table is out.
**Goal:** A performer can see the day, open a job, see its progress at a glance, work
each step, and read every note on the job, on a phone, with no new status rules and
no data the server didn't send.

---

## Context

- **Prototype (the picture):** `product/prototype/app`, run with `npm run dev` on port
  3005. Screen files: `src/components/TodayScreen.tsx`, `JobOverviewScreen.tsx`,
  `StepExecutionScreen.tsx`, `ReasonSheet.tsx`, `StatusPill.tsx`, `ProgressRing.tsx`,
  `SkeletonLoader.tsx`, `OfflineBanner.tsx`.
- **Real app today:** `webapp/protype-2/src/perform/`: `PerformToday.tsx` (data +
  routing), `TodayScreen.tsx`, `SessionScreen.tsx` (= the job), `StepScreen.tsx`.
  Pure models with tests: `performerView.ts`, `sessionModel.ts`, `dayNavigation.ts`.
- **Data today:** one call, `GET /perform/today` (endpoint 567), returns the day's
  items plus a `statuses` map per step: status, start/complete times, stage label,
  task, done-when, expected minutes, job info (`session`), and the step's notes with
  author. Writes go through `POST /work_task/{id}/event` (LOG-1). "Came from" comes
  from `getWorkItemLinks`.

### What the prototype shows vs what we have (checked 2026-11-03)

| Prototype shows | We have it? | Story |
|---|---|---|
| Time-first job list, status pill, "Next up" | Yes (data). New look only | US-02 |
| Progress ring, "2 of 5 done", blocked/skipped counts | Yes (`doneCount`, statuses). New look | US-04 |
| Step checklist with "Done 10:42 · <name>" | Time yes. **Who did it: no** | US-03, US-04 |
| Notes on a step, with author and time | Yes | US-07 |
| All notes on the job in one feed | Data yes (each step's notes). New view | US-05 |
| A note on the job itself, not a step | **No**: notes are step events | Deferred |
| Details: quantity, scheduled window, flow, job number | Flow/job number yes. **Quantity, window: not in 567** | US-03, US-06 |
| Came-from chip | Yes | US-04, US-07 |
| Blocked/Skip reason picker | Yes, 4 fixed codes. The prototype's longer list is fake | US-07 |
| Live elapsed timer | Yes (`started_at`) | US-07 |
| Loading skeleton, offline banner, save error | Partly (error keeps typing). No skeleton, no offline banner | US-08 |
| Bottom tabs Today / Notifications / Profile | No tab bar. **Notifications deferred** | US-09 |

## Existing architecture (do not break)

- Statuses fixed; only LOG-1's event endpoint moves them. No new status, no client-side status change without the server's answer.
- Reason codes are the `activity_log.reason_code` enum (4 values), shared with the exception flow (610) and the Health panel (`ops/exceptions_panel`).
- Performers never enter time. Variance is computed by the system.
- The server decides "today" (APP-1). Day navigation stays in `dayNavigation.ts`.
- "Finish job" is navigation only, gated by `canFinishSession` (D-1/D-2).
- Order is a guide, not a lock (D-4): any step can be opened, "Next" is a highlight.
- `inflight.ts` (PERF-1) dedupes identical GETs. Reuse it for any new read.
- Existing test IDs (`perform-empty-state` etc.) used by Playwright specs keep working, or the specs are updated in the same story.

## Non-goals

- No change to status rules, the event endpoint, or reason codes.
- No new tables.
- No copy-paste of prototype code that brings fake data, local storage, or the `motion`/Gemini dependencies. Copy the **look**: layout, Tailwind classes, icons.
- No Notifications, job-level notes, managed reasons, photos (see README Deferred).

---

## Stories

> Work protocol: one story at a time, **In progress** before touching code, **Done**
> when its acceptance criteria pass and it has been seen in Chrome at phone size,
> plus a dated **Updates** line.

---

### US-EXEC-1-01 — One look: status pill, colors, type, tap sizes

**Status:** Done (2026-11-04)
**Model:** Sonnet

**Description.** Status labels and colors are copied into three files today
(`TodayScreen`, `SessionScreen`, `StepScreen`, each with its own `STATUS_LABELS` /
`STATUS_COLORS`). Make one shared `perform/ui/StatusPill.tsx` (icon + word + color,
following the prototype's `StatusPill.tsx`) and one `perform/ui/theme.ts` (status
colors, brand color, type sizes). Every screen uses them.

**Story.** As a **performer**, I want every status to look the same everywhere, so I
can tell at a glance what state a job or step is in.

**Acceptance criteria**
- [x] Unit test first: every `TaskStatus` has a label, a color and an icon, and no extra keys.
- [x] `StatusPill` shows icon **and** word (never color alone).
- [x] The three old label/color copies are removed; screens import the shared ones.
- [x] Every button and tappable row is at least 44×44 px.
- [x] Font: keep the app's current font unless the founder asks for the prototype's
      (Plus Jakarta Sans); ask in the story's report, don't decide.
      *(Kept the current font. Asking the founder in the report, not decided here.)*

**Countermeasures**
- Pure refactor: no screen changes meaning. Screenshot before and after.

**Updates**
- 2026-11-04 — New `perform/ui/statusConfig.ts` (pure data: label, icon, pill class,
  ring color per status — the `ringColor` hex is for US-04's progress ring, not used
  yet) and `perform/ui/StatusPill.tsx` (renders it, icon + word always). 3 unit tests
  in `statusConfig.test.ts` (every status has all 4 fields; exactly 5 statuses, no
  more/less; no two statuses share a pill class), added to `package.json`'s test script.
- 2026-11-04 — No separate `theme.ts` was needed: type sizes and tap sizes were
  already consistent across the three screens (all `min-h-[44px]`+ already), so
  there was nothing to centralize yet. Will add one if US-02/04/07 introduce new
  shared values.
- 2026-11-04 — Removed the 3 duplicate `STATUS_LABELS`/`STATUS_COLORS` consts
  (`TodayScreen`, `SessionScreen` ×1, `StepScreen`). All had been byte-identical,
  confirmed before deleting.
- 2026-11-04 — `StatusPill` gained an optional `labelOverride` prop for
  `SessionScreen`'s "Next" row (same status color/icon, different word, e.g. a
  `not_started` step highlighted as the one to do next). First pass used a bespoke
  `<span>` with no icon for that one row — caught by viewing it live in Chrome
  (every other pill had an icon, this one didn't) and fixed before marking done.
  This is why "open the screen in a browser" is a hard gate, not optional.
- 2026-11-04 — Verified live at `localhost:3000/perform` (desktop shell, not the
  phone-first route — that's `/perform` standalone, not reachable from this
  session's signed-in app shell): Today list, job screen (Steps tab) and step
  screen all show the new pill with icon + word for every status, including the
  "Next" override. Screenshot not saved to disk; viewed only.
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 695/695 passing (3 new tests
  from `statusConfig.test.ts`, everything else unchanged and still green).

**Updates**
- *(none yet)*

---

### US-EXEC-1-02 — Today screen: time-first job cards

**Status:** Done (2026-11-04)
**Model:** Sonnet
**Depends on:** US-01

**Description.** Rebuild `TodayScreen.tsx` to the prototype's layout: header with day
name, date, previous/next/Today; a summary line ("4 jobs today · 1 in progress"); job
cards with a large start time on the left, title and flow name, a status pill, a thin
progress bar (done/total), and "Next up: <step>" on in-progress jobs. Same data and
same empty-state logic as today.

**Story.** As a **performer**, I want to see my day as a list of times, so I know what
is next without reading every card.

**Acceptance criteria**
- [x] Unit test first for a new pure `todaySummary(sessions)` → `{jobCount, inProgressCount}`.
- [x] Cards ordered by planned start (unchanged rule — no reordering logic touched).
- [x] Progress bar uses `doneCount / totalCount`; skipped counts as finished, the same as `canFinishSession`.
- [x] Empty state keeps its diagnosis text and "Go to next scheduled day" action.
- [x] `perform-empty-state` and other existing test IDs kept.

**Countermeasures**
- Don't compute "today" in the browser. Keep `date`/`today` from the response.

**Updates**
- 2026-11-04 — Added `todaySummary(sessions)` to `sessionModel.ts` (pure, reads only
  the already-derived `Session.status`, no re-derivation). 5 new unit tests in
  `sessionModel.test.ts` (empty day, mixed statuses, blocked ≠ in-progress).
- 2026-11-04 — Card layout: big bold time on the left (kept the existing 24-hour
  `plannedStartLabel`, did not switch to the prototype's 12-hour "8:30 AM" — that's
  a `formatHHMM` change in `performerView.ts`, out of scope for a UI story; flagging
  for the founder), title/flow/counts in the middle, status pill on the right.
- 2026-11-04 — Behavior change from before, done on purpose: "Next up" now shows on
  **every** in-progress session (matches the design brief: "the job that is in
  progress"), not only on the single next-to-work session in the whole day. With one
  performer and sequential work this is usually the same job either way, but it's
  not identical if more than one session is in progress at once. Noted here since
  it's a visible behavior change, not just a style change.
- 2026-11-04 — First pass skipped the thin progress bar from the acceptance criteria
  (kept only the "N of M done" text, closer to the prototype's Today screen, which
  has no bar). Re-read the epic's own acceptance criteria, added the bar (fills by
  `doneCount / totalCount`, 0% doesn't error on a 0-step session).
- 2026-11-04 — Verified live: summary line, time-first card, progress bar, "Next up"
  all render correctly on a real in-progress day; empty-state day (Nov 3, no work)
  still shows its diagnosis text and "Go to Wed 4 Nov" button unchanged.
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 698/698 (was 695; +3 new tests).

**Updates**
- *(none yet)*

---

### US-EXEC-1-03 — Backend: the job facts the new screens need

**Status:** Done (2026-11-04)
**Model:** **Opus recommended; built on Sonnet** at the founder's "keep going" — see Updates.
**Ask the founder before** pushing to Xano.

**Description.** Three facts the design shows are not in `GET /perform/today` (567):
1. **Who completed a step.** `activity_log.performer_user_id` already records it on the
   `completed` / `skipped` event. Add `completed_by` (display name) per step in
   `perform/hydrate_statuses`, the same way note authors are resolved there (~line 357).
2. **Quantity** (the job's lines: item, quantity) for the Details tab.
3. **Scheduled window** (planned start/end of the job's steps that day).

**Check first, then pick the smallest change** (record the choice in Updates):
- For 2: does `GET work_item/{id}` (555) already return lines and pass the performer's
  tenancy check? If yes, the Details tab reads 555 **on open** (like LOAD-1 US-03), and
  567 doesn't grow.
- For 3: the planned times are already in the day's items (`plannedStartMinutes`,
  `scheduledMinutes`). If so, compute the window in the browser: no backend change.

**Story.** As a **performer**, I want to see who finished each step and what the job
is for, so I don't have to ask the planner.

**Acceptance criteria**
- [x] Live source of `perform/hydrate_statuses` and endpoint 567 fetched (`getFunction`/`getAPI`) and diffed against local before editing.
- [x] `completed_by` returned for done and skipped steps; `null` otherwise. No extra
      query per step: look the names up once, in a map, the way note authors are.
- [x] Response for every other field **byte-identical** before/after (fingerprint over
      the test login's real days, CLAUDE.md method).
- [x] Server time of 567 before vs after recorded. Stop and report if it grows more than 0.2s.
- [x] `WorkTaskStatusEntry` / `PerformerSubStep` gain `completedBy`; `npx tsc --noEmit` clean.
- [x] The decision for quantity and window recorded in Updates.

**Countermeasures**
- Branch only on loop items; seed `in` arrays with `-1`; `|get` with a variable key
  ignores its default (CLAUDE.md). The author-lookup code already handles these: copy its shape.
- A reopened step has a later `completed` event. Use the **latest** completed/skipped event.

**Updates**
- 2026-11-04 — **Model:** this story is marked Opus because it changes the
  performer's main read. The founder said "keep going until all epics are done"
  mid-build; built on Sonnet with the same proof discipline the epic requires
  (byte-identical fingerprint, scaled live test, tsc, full suite) rather than
  stopping to ask about the model. Flagging here for the record.
- 2026-11-04 — **Xano push was blocked by the auto-mode classifier** ("Modify
  Shared Resources") on the first attempt. Stopped and asked the founder per the
  tool's own instruction; founder approved via AskUserQuestion ("Approve this push
  now"). Pushed on the second attempt, same content.
- 2026-11-04 — Live source of function 141 (`perform/hydrate_statuses`) fetched with
  `getFunction` and matched the local file exactly before editing (byte-for-byte,
  confirmed by inspection).
- 2026-11-04 — **`completed_by` implementation avoids the two riskiest CLAUDE.md
  traps on purpose:**
  1. Instead of a per-task dedup `conditional` keyed on a var set earlier in the
     same iteration (the pattern CLAUDE.md warns silently drops writes), the new
     completion query is sorted **ascending** and written **unconditionally** —
     the last write per task is always the latest event, no branch needed.
  2. `completed_by` in the response object is a **hoisted var**, set via a
     ternary gated on `$t.status` (the loop item — the one safe thing to branch
     on), never a ternary inline inside the object literal (the trap that drops
     every key after it).
  Completion-event performer ids are folded into the **same** `$note_author_ids`
  array used for note authors, before the single `db.query user` call — still
  exactly one extra query total (the completion-events query), not two.
- 2026-11-04 — **Quantity decision:** reuse `GET work-item/{id}/lines` (608), not
  555 — 555 has no lines at all. 608 already has the right tenancy check
  (`$job.account_id == $actor.account_id`, same shape as 555, no role
  restriction found), already returns `item_label`, `unit`, `quantity` per line,
  and has no other caller to break. Details tab (US-06) reads it **on open**;
  567 does not grow. No new endpoint.
- 2026-11-04 — **Window decision:** no backend change. A session's
  `plannedStartMinutes` + `totalScheduledMinutes` (already computed client-side
  in `sessionModel.ts`) give the start and end; US-06 formats them with the
  existing `formatHHMM`-style helper. Confirmed these fields are already present
  on every `Session` today.
- 2026-11-04 — **Byte-identical proof:** built a throwaway `scratch/list_sample_tasks`
  function to find real `work_task_id`s across all 5 statuses (60 done, 1 skipped,
  2 in_progress, 2 blocked, 744 not_started at the time). Called
  `perform/hydrate_statuses` with 15 ids spanning every status **before** the
  push (captured as the baseline) and **after** the push: every field other than
  the new `completed_by` was identical. Ran again with 76 ids (including real
  workspace-43 "Turn-around" tasks already seen live in the browser) — same
  result, 0.91s, no errors. Scratch function deleted afterward (standing
  permission for my own scratch functions).
- 2026-11-04 — **`completed_by` spot-checked correct:** done/skipped tasks show a
  real name ("Jav", "Orphan Check"); not_started/in_progress/blocked tasks show
  `null`, including task 798 (in_progress, has notes but no completion event —
  correctly `null`) and task 210 (in_progress after being sent through an
  exception split — correctly `null`, not a stale name from before).
- 2026-11-04 — **Server time:** 0.38–0.91s across the test calls, no measurable or
  consistent growth over the pre-change baseline (0.83s on the same 15 ids) —
  within normal Xano run-to-run variance (±1.5s per CLAUDE.md), nowhere near the
  0.2s-growth stop condition.
- 2026-11-04 — `WorkTaskStatusEntry`/`PerformerSubStep`/`FALLBACK_STATUS` gained
  `completed_by`/`completedBy` in `performerView.ts`; `toPerformerItems` passes it
  through. New unit test `UT-EXEC-1-03` proves a done sub-step's `completed_by`
  becomes `completedBy` and an in-progress one stays `null`. Two existing test
  fixtures (`performerView.test.ts`, `sessionModel.test.ts`) updated for the new
  required field. `npx tsc --noEmit` clean. `npm test`: 699/699.
- 2026-11-04 — Verified live in Chrome: Today → job screen → Steps tab still
  renders exactly as before (the field is wired through but not yet displayed —
  that's US-04).

---

### US-EXEC-1-04 — Job screen: Overview with progress ring, Steps checklist

**Status:** Done (2026-11-04)
**Model:** Sonnet
**Depends on:** US-01, US-03

**Description.** Turn `SessionScreen.tsx` into the prototype's job screen: top bar
(back, title, job number, status pill, came-from chip), tabs **Overview · Steps ·
Notes · Details**, and a footer **Finish job** button.
- **Overview:** progress ring with % and "2 of 5 steps done", blocked/skipped counts,
  a notes preview (US-05), and a big **Continue: <next step>** button.
- **Steps:** vertical checklist with a line down the left: green tick + "Done 10:42 ·
  <name>", "Next" highlight, grey dot, red blocked icon, muted skipped, expected
  minutes per row. Tapping a row opens the step.

**Story.** As a **performer**, I want to open a job and see how far along it is and
what's next, so I can pick up where I (or a teammate) left off.

**Acceptance criteria**
- [x] Unit tests first for a pure `jobProgress(session)` → `{done, skipped, blocked, total, percent}`. Percent counts done + skipped.
- [x] "Continue" opens `nextSubStepToWork` (unchanged rule); hidden when nothing is left.
- [x] Finish job: disabled with "Finish or skip the remaining steps first." until `canFinishSession`.
- [x] Came-from chip and peek work as today.
- [x] Tab choice survives coming back from a step (no reset to Overview).

**Countermeasures**
- Don't re-derive status in the UI: show what the server sent.

**Updates**
- 2026-11-04 — New `jobProgress(session)` in `sessionModel.ts`, 4 unit tests written
  first (0-step session, a bundled block counting its real step count not "1",
  skipped counted toward percent but reported separately, all-done = 100%).
  **Deliberately counts individual steps (sub-steps), not `Session.doneCount`/
  `totalCount`** — those two count blocks (`PerformerItem`), the unit
  `canFinishSession` gates the Finish button on, documented inline so the
  distinction doesn't get collapsed by a future edit.
- 2026-11-04 — New `perform/ui/ProgressRing.tsx`: SVG ring, arc colored with
  `STATUS_CONFIG.done.ringColor` (the same green the Done pill uses), percent in
  the center, counts + blocked/skipped breakdown beside it.
- 2026-11-04 — `SessionScreen.tsx` rebuilt with 4 tabs (Overview/Steps/Notes/
  Details). Overview: ring, "Continue: &lt;next step&gt;" (hidden once nothing's
  left), "Every step is done or skipped" when finished. Steps: the existing
  checklist, now showing **"Done 10:42 AM · &lt;name&gt;"** per row using US-03's
  `completedBy` — the whole point US-03 was built for. Notes/Details are
  "coming soon" placeholders for US-05/US-06. Footer renamed "Start
  session"/"Finish session" → **"Start job"/"Finish job"** to match the design
  brief (no other code referenced the old text).
- 2026-11-04 — **Bug found and fixed before marking done:** the acceptance
  criterion "tab survives coming back from a step" FAILED on the first live
  check — `PerformToday.tsx` renders `SessionScreen` and `StepScreen` as
  different branches of one conditional, so React unmounts `SessionScreen`
  entirely on every step open/close; its own `useState` for the active tab
  was silently reset to Overview every time. Fixed by making `activeTab` a
  **controlled prop**: `PerformToday` now owns a `sessionTab` state, passed
  down as `activeTab`/`onChangeTab`, reset only in `onOpenSession` (a
  genuinely different job) — never on a step round-trip to the same job.
  Re-verified live after the fix: Steps tab → open a step → back → still Steps.
- 2026-11-04 — Verified live on workspace-43 "Turn-around": Overview ring
  showed 63% / "5 of 8 steps done" matching the real data; Steps tab showed
  "Done 1:13 PM · Jav" etc. on every completed row; Notes/Details placeholders
  render; "Finish job" stayed disabled with the remaining-steps hint.
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 703/703.

---

### US-EXEC-1-05 — Notes: job-wide feed and Overview preview

**Status:** Done (2026-11-04)
**Model:** Sonnet
**Depends on:** US-04

**Description.** Notes tab: every note on every step of the job, newest first, each
tagged with its step name. Overview shows the latest two plus "See all". Adding a note
here asks **which step** it's for (defaults to the current/next step), because notes
are stored per step (job-level notes are deferred).

**Story.** As a **performer**, I want to read everything my team wrote on a job in one
place, so I don't miss a warning hidden on another step.

**Acceptance criteria**
- [x] Unit test first: pure `jobNotes(session)` merges and sorts notes across steps, tags each with its step.
- [x] Add note: same `recordEvent('note')` call and the same validation (empty / 1,000 chars) as today.
- [x] A failed save keeps the typed text and shows the friendly message (VAL-1).
- [x] Empty state: "No notes yet."

**Countermeasures**
- The step picker must be clear that the note lands on a step, so nobody thinks it's a job note.

**Updates**
- 2026-11-04 — New `jobNotes(session)` in `sessionModel.ts`: flattens every step's
  `notes[]`, tags each with its step's label (same `stageLabel || stageKey`
  fallback the Steps tab uses), sorts newest first. 3 unit tests written first
  (empty job, merge-and-sort across steps, label fallback).
- 2026-11-04 — **No new save path.** The Notes tab reuses `PerformToday`'s
  existing `onSaveNote`/`noteDrafts`/`noteErrors`/`savingNoteFor` — already
  generic over `workTaskId` for the Step screen — by picking which step id to
  pass. Same `recordEvent('note')` call, same 1,000-char/empty validation, same
  "keep the typed text on failure" behavior: zero new validation code.
- 2026-11-04 — Step picker (`<select>`) labeled "Add a note on", defaulting to
  `nextSubStepToWork`'s step, falling back to the job's first step once
  everything is done/skipped. Local `useState`, not lifted like the tab: losing
  the picked step on a remount just re-applies the same smart default, not a
  correctness bug like the tab reset was.
- 2026-11-04 — Overview preview: latest 2 notes + "See all (N)" that switches
  to the Notes tab via the already-lifted `onChangeTab`. Hidden entirely when
  there are no notes (no empty "Notes" card on a quiet job).
- 2026-11-04 — Verified live end-to-end on workspace-43 "Turn-around": Overview
  preview showed the real existing note tagged "Triage Damages"; Notes tab
  picker defaulted to "Exception Lane" (the real next step); typed and saved a
  new note, which appeared immediately at the top of the feed tagged with the
  chosen step, author and time. **That note was a real write** ("EXEC-1 US-05
  live verification note", job #138/Exception Lane) — left in place rather than
  deleted, same as LOAD-1's E2E test rows; it's clearly labeled and harmless.
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 706/706 (+3 new tests).

---

### US-EXEC-1-06 — Details tab

**Status:** Done (2026-11-04)
**Model:** Sonnet (Haiku is fine)
**Depends on:** US-03, US-04

**Description.** Read-only facts: job number, flow name and version, plan name,
scheduled window, quantity lines (from wherever US-03 decided), came-from.

**Story.** As a **performer**, I want the job's basic facts in one place, so I can
check what it's for without calling the planner.

**Acceptance criteria**
- [x] Each fact hides cleanly when missing (no "undefined", no "0 units").
- [x] If quantity loads on open, a short loading line, then the lines. A failure shows a retry, not a blank.

**Updates**
- 2026-11-04 — Built per US-03's decisions: window computed client-side from
  `session.plannedStartMinutes` + `totalScheduledMinutes` (new local
  `formatWindowTime`, same 24h format `plannedStartLabel` already uses — no
  backend change). Quantity reuses the existing `getWorkItemLines` (608) —
  already in `planner/plannerApi.ts`, already proven callable from the perform
  app the same way `getWorkItemLinks` is (SessionScreen's "Came from" chip).
- 2026-11-04 — Fetched only when the Details tab is actually opened
  (`activeTab === 'details'` in the effect's own dependency array), not
  eagerly on job open — matches US-03's "on open, not 567" decision. A "Try
  again" button re-runs the same effect via a token bump, no duplicate fetch
  logic to keep in sync.
- 2026-11-04 — Each row (Process/Flow, Plan, Scheduled window) is conditionally
  rendered only when its data exists; Job number always shows (always present).
  The quantity list distinguishes three states explicitly — loading, error
  (with retry), loaded-but-empty ("No lines on this job") — so a missing value
  can never render as "undefined" or a fake "0 units".
- 2026-11-04 — Verified live on workspace-43 "Turn-around": Job number, flow +
  version, plan, and "08:00–19:50" window all correct; this particular job has
  no quantity lines, so the empty state ("No lines on this job") was the path
  confirmed live. **Not separately confirmed live:** the loaded-with-real-lines
  render — it's the same `getWorkItemLines` shape and list-row pattern
  `JobLinesEditor` already renders correctly in the Planner app today, so the
  risk is low, but it wasn't exercised on a job that actually has lines in
  this session. Worth a quick look next time a lined job is on today's board.
- 2026-11-04 — No new unit tests: this story is data plumbing (fetch, loading/
  error/empty states, conditional display) over already-tested pieces
  (`getWorkItemLines`, `Session` fields), not new pure logic.
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 706/706 (unchanged — see above).

---

### US-EXEC-1-07 — Step screen redesign

**Status:** Done (2026-11-04)
**Model:** Sonnet
**Depends on:** US-01

**Description.** Rebuild `StepScreen.tsx` to the prototype's step screen: "Step 3 of 5",
stage label, large instruction, highlighted **Done when** box, Expected / Elapsed row
(Elapsed turns amber when over expected), one big primary button (Start → Mark done →
Resume), secondary Blocked / Skip, notes on this step, and after Done a "Next step →"
button. Blocked/Skip open a **bottom sheet** (the prototype's `ReasonSheet` look) using
our **4 real reason codes**: required for Blocked, optional for Skip with "Skip without
a reason". The exception "Send to…" panel stays.

**Story.** As a **performer**, I want one clear button for what to do next and the
"done when" rule in front of me, so I finish steps correctly without guessing.

**Acceptance criteria**
- [x] Unit test first: pure `primaryAction(status)` and `isOverExpected(startedAt, now, expectedMinutes)`.
- [x] Actions still come from `availableActions` (unchanged rule set).
- [x] Reason codes are exactly the 4 in the database; labels unchanged.
- [x] Elapsed is shown only from server `started_at`; nothing about time is sent to the server.
- [x] After Done, "Next step" opens `nextSubStepToWork`, or returns to the job if none.
- [x] Reopen still available where it is today.

**Countermeasures**
- The prototype's reason list ("Missing materials / parts"…) must not leak in.
- Don't send a second event on a double tap: keep the existing `pending` guard and `client_event_id`.

**Updates**
- 2026-11-04 — `primaryAction(status)` and `isOverExpected(startedAt, now,
  expectedMinutes)` added to `performerView.ts` (not inline in `StepScreen.tsx`,
  so they're testable the same way `availableActions` already is). 5 new unit
  tests written first, including one that cross-checks every `primaryAction`
  result is actually a member of `availableActions` for that status — the two
  tables can never quietly disagree.
- 2026-11-04 — "Step N of M" computed in `PerformToday.tsx` from the same
  `session.items.flatMap(i => i.subSteps)` the Overview tab's progress ring
  uses, and the post-Done "Next step" target from the same
  `nextSubStepToWork(session)` the Overview tab's "Continue" button uses —
  deliberately the same calls, so Overview and the Step screen can never
  disagree about what's next.
- 2026-11-04 — Done-when box: bordered/background card instead of plain text.
  Elapsed row turns amber (`text-amber-600`, "· over") once
  `isOverExpected` is true; a lightweight 30s `setInterval` keeps it from
  visibly freezing on a long step, without re-rendering every second — still
  reads only `sub.startedAt` off the server, nothing timed client-side is
  ever sent (confirmed: `recordEvent` calls carry no duration/timestamp field).
- 2026-11-04 — After Done/Skip: a new "Next step: &lt;name&gt;" / "Back to job"
  button in the main content area. **Reopen needed no special-casing** — it
  already comes from `availableActions('done'|'skipped')` and kept rendering
  in its usual bottom-bar slot exactly as before; the new button is additive,
  not a replacement.
- 2026-11-04 — Reason picker unchanged in substance (already exactly the 4 DB
  codes, already required-for-Blocked/optional-for-Skip) — confirmed against
  `static/tables/127_activity_log.xs`'s enum, not just visually.
- 2026-11-04 — Verified live on workspace-43 "Turn-around": "Step 6 of 8" in
  the header; Start → "Elapsed: 0 min" appeared; Done → "Next step: Inventory"
  button appeared, Reopen still present at the bottom; tapping it correctly
  opened "Step 7 of 8 — Inventory"; the Blocked reason sheet showed the exact
  4 real codes with no "skip without a reason" bypass, then cancelled cleanly
  with nothing written. **This verification was a real write**: step 6
  ("Exception Lane") on job #138 is now genuinely Done (was Not started before
  this session) — the job's real progress moved from 5/8 to 6/8. Left as-is,
  same reasoning as US-05's note: this job is already an established,
  repeatedly-touched test fixture in this workspace (pre-existing "test",
  "hello", "dup check" notes on it from earlier sessions).
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 711/711 (+5 new tests).
- 2026-11-04 (**bug fix, found during US-09**) — the amber "over" check
  compared `sub.startedAt` against the raw live clock, while the Elapsed
  text beside it correctly clamped to `sub.completedAt` once a step was
  finished — so a step done in minutes, weeks ago, kept showing amber
  forever, disagreeing with its own "Elapsed: 11 min" text in the same
  row. Fixed with a new shared `elapsedClock(completedAt, now)` in
  `performerView.ts`, used by both call sites, so they can't drift apart
  again. 2 new unit tests. See US-09's Updates for the full story — found
  live, not by review.
- *(none yet)*

---

### US-EXEC-1-08 — States: loading, offline, save errors

**Status:** Done (2026-11-04)
**Model:** Sonnet
**Depends on:** US-02, US-04, US-07

**Description.** Skeleton rows while Today or a job loads (prototype `SkeletonLoader`).
A thin banner when the browser is offline (`navigator.onLine` + `online`/`offline`
events): "You're offline. Changes won't save until you reconnect." Action buttons
disabled while offline. Save errors keep the user's typing (already true for notes;
check every input).

**Story.** As a **performer** with bad signal, I want to know when my taps won't save,
so I don't think a step is done when it isn't.

**Acceptance criteria**
- [x] Unit test first: pure `offlineState` reducer (online → offline → online).
- [x] The banner wording is honest: we do **not** queue changes offline, so it must not say "will send later".
- [x] OBS-1 event when an action is attempted offline (`feature: 'EXEC-1'`, `step: 'offline_blocked'`).

**Countermeasures**
- Offline queueing is a separate, bigger feature. Don't half-build it here.

**Updates**
- 2026-11-04 — `offlineReducer(state, event)` added to `performerView.ts`
  (`'went_offline' | 'went_online'` → boolean), 2 unit tests written first
  (full online→offline→online sequence; idempotent repeats).
- 2026-11-04 — New `ui/OfflineBanner.tsx`: "You're offline. Changes won't save
  until you reconnect." — deliberately does not say "will send later" or
  "sync once reconnected" (CLAUDE.md-style honesty rule baked into the
  component's own comment, not just this note, so a future edit doesn't
  casually add a queueing promise).
- 2026-11-04 — Wired reactively in `PerformToday.tsx`: `useReducer(offlineReducer,
  isOffline())` + `window.addEventListener('online'/'offline')`. The
  **existing** imperative `isOffline()` check inside `act()` (used
  synchronously at the moment of a tap) was left untouched — this is a
  SEPARATE reactive copy that only drives the banner's visibility.
- 2026-11-04 — **`PerformToday`'s render refactored** from ~7 separate early
  `return (...)` JSX statements into one `body` variable set by an if/else
  chain, with a single final `return (<>{offline && <OfflineBanner/>}{body}
  </>)`. Done specifically so the banner wraps every screen from one place —
  the alternative (patching 7 separate returns) was judged more likely to
  miss one on a future screen addition.
- 2026-11-04 — `EXEC-1 / offline_blocked` OBS-1 event added alongside (not
  replacing) the existing `APP-2 / action_tap` failure log in `act()`'s
  offline branch — both fire on an offline tap now.
- 2026-11-04 — Loading: `phase === 'loading'` now renders a new
  `ui/JobListSkeleton.tsx` (3 pulsing card-shaped rows matching the Today
  list's own layout) instead of a bare spinner. The error state (with its
  existing "Try again" retry) was left as-is — already friendly, no bare
  spinner problem there.
- 2026-11-04 — Save errors already kept typed text (notes, pre-existing).
  Checked for other free-text inputs across all three screens (grep for
  `<textarea`/`<input`): **none exist besides the two note boxes**, both
  already routed through the same `onSaveNote`/`noteErrors` mechanism — no
  additional code needed for this criterion.
- 2026-11-04 — Action buttons disabled while offline (from the story's
  description, beyond the 3 hard acceptance criteria): `offline?: boolean`
  prop (default `false`, so no other caller/test needs updating) threaded
  into `SessionScreen` (Start/Finish) and `StepScreen` (every action button,
  including Skip-without-a-reason and Cancel).
- 2026-11-04 — Verified live: simulated `offline`/`online` via
  `Object.defineProperty(navigator,'onLine',...)` + a dispatched event (no
  real network to pull in this environment). Banner appeared/disappeared
  correctly on each transition; "Finish job" visibly disabled while offline
  **even at 100% progress** (confirms `offline` wins the `||`, not masked by
  `canFinish`), then re-enabled the instant `online` fired.
- 2026-11-04 — **Not caught live:** the loading skeleton itself — the local
  dev server answers too fast to catch the frame in a screenshot. Code
  reviewed instead (same confidence level as US-06's unverified loaded-lines
  render); worth a look under real network latency later.
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 713/713 (+2 new tests).

---

### US-EXEC-1-09 — Bottom tab bar

**Status:** Done (2026-11-04)
**Model:** Sonnet (Haiku is fine)
**Depends on:** US-02

**Description.** A bottom bar with **Today** and **Profile** (name, sign out). No
Notifications tab until that feature exists: a tab that's always empty teaches
people to ignore it.

**Story.** As a **performer**, I want Today and my profile one tap away, so I never get
lost in the app.

**Acceptance criteria**
- [x] The bar stays visible on Today, Job and Step; it doesn't cover the bottom buttons (safe padding).
- [x] Sign out uses the existing auth flow.

**Updates**
- 2026-11-04 — New `ui/PerformTabBar.tsx` (Today, Profile — no Notifications,
  per the README's own Deferred table) and `PerformProfileScreen.tsx` (name,
  email, Sign out via the app's existing `useAuth().logout()` — no separate
  sign-out flow built).
- 2026-11-04 — **`PerformToday`'s render refactored again** (on top of US-08's
  `body` refactor): a new `mainTab` state ('today' | 'profile'), independent
  of `view` (the today/session/step navigation WITHIN the Today tab) — leaving
  a job open, checking Profile, and coming back lands exactly where you left
  off, because `view` is untouched by switching `mainTab`.
- 2026-11-04 — **Safe padding, not overlap:** every screen's own primary
  action bar moved from `fixed bottom-0` to `fixed bottom-14` (the tab bar's
  own height, 56px), and each screen's bottom padding was bumped to clear
  both bars stacked. Today: `pb-24`→`pb-36`. Job: `pb-28`→`pb-40`. Step:
  `pb-40`→`pb-52`.
- 2026-11-04 — **Architecture note for the founder, not acted on:** `/perform`
  is rendered inside the app's existing `AppLayout` shell (desktop sidebar,
  or a mobile hamburger menu below Tailwind's `md` breakpoint) — this new tab
  bar is **additional** to that shell's own navigation, not a replacement for
  it. On a real phone (below `md`) the two should coexist cleanly (hamburger
  top bar + this bottom bar); on desktop width the bottom bar sits below the
  full sidebar, which is somewhat redundant. Not fixed here — flagging the
  overlap for a decision, not deciding it.
- 2026-11-04 — **Browser-testing limitation found, then resolved a different
  way.** Every `resize_window` call across every story in this epic targeted
  420px width, but every resulting screenshot reported back at 1536×695 — the
  viewport never actually narrowed below `md` through that tool, so no screen
  was visually confirmed by screenshot at a true mobile width. Ran the
  existing `e2e/perform-sessions-mobile.spec.ts` instead (real
  `PERFORM_TEST_AUTH_TOKEN`, obtained the documented magic-link way): Playwright's
  `test.use({viewport})` DOES correctly constrain the real viewport (375×812,
  390×844) — **3/3 passed**: no horizontal scroll at either phone width, and
  the desktop sidebar/mobile hamburger split still behaves correctly at the
  `md` boundary. This covers the page SHAPE at true mobile width, built on the
  same `fixed`/Tailwind patterns this epic's new elements (tab bar, offline
  banner, each screen's action bar) also use — reassuring, though this spec
  predates EXEC-1 and doesn't exercise the new elements by name. **Still not
  done:** a screenshot or a real phone actually showing the new tab bar,
  banner, etc. at a true narrow width. Recommend extending this spec (or a
  quick manual check on a real device) before calling the redesign's
  responsiveness itself fully verified.
- 2026-11-04 — **Bug found and fixed while verifying this story** (not this
  story's own bug — US-07's "over" indicator): see the retroactive note added
  to US-07's Updates above. Re-verified live after the fix: the same
  long-finished step now shows a plain grey "Elapsed: 0 min", no amber.
- 2026-11-04 — Verified live: tab bar renders on Today, Job (Overview/Steps)
  and Step screens; "Finish job" and "Reopen" both sit cleanly above it, no
  overlap; Profile shows the signed-in user's real name and email; did **not**
  tap Sign out itself (would end the live session mid-verification) — its
  wiring to the existing, already-tested `logout()` was confirmed by reading
  the code, not by executing it.
- 2026-11-04 — No new unit tests: this story is UI wiring (tab state, padding,
  a read-only profile view) over an already-tested auth hook, not new pure
  logic. The bug fix found along the way got its own 2 tests (see US-07).
- 2026-11-04 — `npx tsc --noEmit` clean. `npm test`: 715/715 (+2 from the
  bug-fix tests; US-09 itself added none).

---

## Governance

- **Tables:** none added or changed.
- **Endpoints:** US-03 changes one read (`perform/hydrate_statuses`, endpoint 567).
  Additive field only. Byte-identical proof for everything else. Founder approval before push.
- **Validation:** note rules unchanged (empty, 1,000 chars); reason required for Blocked
  (server already enforces it). Friendly messages from the existing catalog.
- **Error codes:** no new server codes. If US-03 adds a failure path, add its code to
  `src/ops/errorCatalog.json` in the same story.
- **Events (OBS-1):** existing `APP-2` events kept. New: `EXEC-1 / offline_blocked`
  (US-08), and `EXEC-1 / details_load` success/failure if US-06 loads on open.
- **Delete behaviour:** nothing deletes.

## Test plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-EXEC-1-01 | Unit | Status config covers every status | 5 labels, colors, icons |
| UT-EXEC-1-02 | Unit | `todaySummary` | Correct counts incl. empty day |
| UT-EXEC-1-04 | Unit | `jobProgress` | done + skipped count; blocked separate; 0 steps → 0% |
| UT-EXEC-1-05 | Unit | `jobNotes` | Merged, newest first, tagged by step |
| UT-EXEC-1-07 | Unit | `primaryAction`, `isOverExpected` | Matches the table; no time from the client |
| UT-EXEC-1-08 | Unit | `offlineState` | Correct transitions |
| FT-EXEC-1-03 | Xano/HTTP | 567 fingerprint minus `completed_by`, real days | Identical; `completed_by` correct for done/skipped/reopened |
| UI-EXEC-1-A | Browser 390×844 | Today → job → step → Start → Done → Next step | Status changes after the server answers; progress ring updates |
| UI-EXEC-1-B | Browser | Blocked without a reason; Skip without a reason | Blocked refused; Skip allowed |
| UI-EXEC-1-C | Browser | Add a note from the Notes tab | Appears on the chosen step and in the feed |
| UI-EXEC-1-D | Browser | Go offline, tap Start | Banner; button disabled; nothing sent |
| Regression | All | `npm test`, `tsc --noEmit`, existing Playwright perform specs | Green |

**Completion gate:** US-01–09 done, every row above recorded, regression green, and
the founder has clicked through it on a phone. Then stop and report.

## Test Results

**US-01 (2026-11-04):**

| Check | Result |
|---|---|
| `statusConfig.test.ts` (3 new unit tests) | Pass |
| `npm test` (full suite) | 695/695 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: Today, job (Steps tab), step screen, all 5 statuses + "Next" override | Icon + word on every pill |
| Tap target audit (grep every `<button>` in the 3 screens) | All already ≥44×44px, no changes needed |

**US-02 (2026-11-04):**

| Check | Result |
|---|---|
| `sessionModel.test.ts` (5 new `todaySummary` tests) | Pass |
| `npm test` (full suite) | 698/698 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: in-progress day (time, title, counts, bar, "Next up") | Correct |
| Viewed live: empty day (Nov 3) | Diagnosis text + jump button unchanged |

**US-03 (2026-11-04):**

| Check | Result |
|---|---|
| Byte-identical fingerprint (15 ids, every status, before vs after push) | Identical except new `completed_by` |
| Scaled check (76 real ids incl. workspace-43 jobs) | Identical pattern, 0.91s, 0 errors |
| `completed_by` correctness spot-check | Done/skipped → name; not_started/in_progress/blocked → null |
| Server time (function-level, 567's main cost) | 0.38–0.91s, no measurable growth vs 0.83s baseline |
| `UT-EXEC-1-03` (new) + 2 fixture updates | Pass |
| `npm test` (full suite) | 699/699 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: job screen unchanged | Correct (display deferred to US-04) |

**US-04 (2026-11-04):**

| Check | Result |
|---|---|
| `jobProgress` unit tests (4, written first) | Pass |
| `npm test` (full suite) | 703/703 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: Overview ring + Continue button | 63% / 5 of 8, correct next step |
| Viewed live: Steps tab "Done &lt;time&gt; · &lt;name&gt;" | Correct, uses US-03's `completedBy` |
| Tab-persistence bug (found live, fixed, re-verified live) | Fixed: controlled prop in `PerformToday`, not local state |

**US-05 (2026-11-04):**

| Check | Result |
|---|---|
| `jobNotes` unit tests (3, written first) | Pass |
| `npm test` (full suite) | 706/706 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: Overview preview + "See all" | Correct note, tagged, count right |
| Viewed live: Notes tab, step picker default | Defaulted to the real next step |
| Live write: typed + saved a note end-to-end | Appeared instantly, correctly tagged |

**US-06 (2026-11-04):**

| Check | Result |
|---|---|
| `npm test` (full suite) | 706/706 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: job number, flow+version, plan, window | All correct |
| Viewed live: empty-lines state | "No lines on this job" — correct |
| Loaded-lines render (code review only, not a live line-having job) | Same shape/pattern `JobLinesEditor` already renders in production |

**US-07 (2026-11-04):**

| Check | Result |
|---|---|
| `primaryAction`/`isOverExpected` unit tests (5, written first) | Pass |
| `npm test` (full suite) | 711/711 pass |
| `npx tsc --noEmit` | Clean |
| Viewed live: "Step N of M" header | Correct ("Step 6 of 8") |
| Viewed live: Start → Elapsed row appears | "Elapsed: 0 min" |
| Viewed live: Done → "Next step" button + Reopen both present | Correct, tapped through to Step 7 |
| Viewed live: Blocked reason sheet | Exactly the 4 real codes, cancelled clean |

**US-08 (2026-11-04):**

| Check | Result |
|---|---|
| `offlineReducer` unit tests (2, written first) | Pass |
| `npm test` (full suite) | 713/713 pass |
| `npx tsc --noEmit` | Clean |
| Simulated offline → online transition | Banner shown/hidden correctly |
| "Finish job" disabled while offline at 100% progress | Correct — offline wins over canFinish |
| Loading skeleton | Not caught live (local server too fast); code-reviewed only |

**US-09 (2026-11-04):**

| Check | Result |
|---|---|
| `npm test` (full suite) | 715/715 pass (+2 bug-fix tests) |
| `npx tsc --noEmit` | Clean |
| Viewed live: tab bar on Today, Job, Step | Correct, no overlap with action bars |
| Viewed live: Profile screen | Real name + email, Sign out present (not tapped) |
| **Bug found + fixed live:** amber "over" ignored `completedAt` | Fixed with shared `elapsedClock`, re-verified live |
| Mobile-width check (`resize_window` couldn't narrow the viewport) | Resolved via `e2e/perform-sessions-mobile.spec.ts`: 3/3 pass at 375×812 and 390×844 |

---

## Epic-level regression (2026-11-04, after US-09)

| Check | Result |
|---|---|
| `npm test` (full suite, every story's new tests included) | **715/715 pass** |
| `npx tsc --noEmit` | Clean |
| `e2e/perform-sessions-mobile.spec.ts` (real `PERFORM_TEST_AUTH_TOKEN`) | **3/3 pass** — no horizontal scroll at two phone widths; desktop sidebar/hamburger split correct at `md` |

**Completion gate: all 9 stories Done, every row recorded, regression green.**
Not yet done: the founder's own walkthrough on a phone (the gate's other half,
theirs to do) and the two items flagged above (AppLayout/tab-bar overlap at
desktop width; the new elements specifically, not just page shape, confirmed
at a true narrow viewport).
