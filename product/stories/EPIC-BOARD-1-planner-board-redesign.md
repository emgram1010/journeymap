# EPIC-BOARD-1 — The planner board: jobs on the left, days on the right, drag between them

**Status:** 📝 **Designed 2026-10-28. Nothing built.**
**Default model:** **Sonnet 5.5** to build; **Opus 5.5** review pass on US-02 (the drag → schedule
wiring) before calling the epic done, and for any bug that fails twice.
**Depends on:** BLK-1 (cards, endpoint 559/583 — live), EST-1 (estimate badge — live),
EXC-1/2 (chips and the read-only job view — live), RPT-1 (Plan vs Action already moved out — done).
**Blocks:** nothing.
**Risk:** medium. Frontend-only, **no new endpoints, no schema, no new status** — but it rewires
the planner's main surface and retires the Jobs modal's scheduling form, so a regression here is a
regression in the founder's daily screen.

**Reference design:** `product/images/screen1.png` — a dispatch/routing product (jobs column, map,
routes, stop sequence). The founder's read of it, 2026-10-28: the jobs column + drag-to-route +
route-click-shows-sequence is the shape we want; **the map is not applicable** to Emgram.

---

## 1. Goal

**Make the planner's main screen the whole loop: work waiting on the left, people's days on the
right, drag from one to the other — instead of a form buried in a modal.**

**As a** planner, **I want** every job's waiting cards in a column beside the day board, **so that**
I see what needs a day and who has room in one glance, without opening anything.

**As a** planner, **I want** to drag a card onto a person's day, **so that** placing work is one
motion instead of expand-row → pick who → pick day → Place.

**As a** planner, **I want** clicking a person's day to show its sequence with minutes, **so that**
"what is Maria actually doing Tuesday" is one click (this mostly exists — the DayBoard — and gets
the job cards rendered properly rather than rebuilt).

### What we are deliberately NOT copying from the reference

- **The map.** Emgram work has no geography; the day's ordered list IS the route.
- **Marker-id columns.** Rows carry the job's words (title, role, steps, minutes), never codes.
- **Unexplained warning icons.** Every badge here already carries words (estimate status, blocked
  reason, exception chips); keep that rule.
- **"Scenarios."** That layer is our existing plans (workspaces). No new concept.
- **Resequence/Optimize buttons.** We have no travel times to optimize; order within a day is the
  planner's hand-set sequence. Deferred until there is something real to optimize.

---

## 2. What exists today (verified 2026-10-28 — re-verify before building)

| Thing | Where | What it gives you |
|---|---|---|
| Job-card backlog | `GET workspace/{id}/backlog_work` (559), wrapped `listBacklogWork` | One CARD per (job × actor row): `card_key`, `job_title`, `lens_label`, `step_count`, `expected_minutes`, `estimate_status`, `first/last_stage_label`, `parent_work_item_id`, `child_count`. **Rendered only inside `JobsModal.tsx` ("Work waiting for a day").** |
| Card scheduling | `POST card/schedule` (583), wrapped `scheduleCard` | Places a whole card on (agent, date); creates the slot; refuses a published day with a friendly sentence; logs `ops/log_event` server-side on success and failure. **Called only from the modal's pick-who/pick-day form.** |
| Unschedule | `unscheduleWorkTask` + the modal's "Scheduled" section | Releases a slot back to the backlog unless the day is published. |
| Day board + drag | `DayBoard.tsx`, `PlanCanvas.tsx`, `BacklogDrawer.tsx` in `src/planner/components/` | Drag **already works** for plain `planner_task`s: `BacklogDrawer` drags onto agent days (`onAddToAgentDay`), `DayBoard` moves tasks across day columns. The job cards are NOT in this flow. |
| Ensure-day rule | `PlannerApp.tsx` (`onEnsureTimeline`) | Creates the (agent, date) day idempotently — the modal already borrows it; the board drag will too. |
| Jobs modal | `JobsModal.tsx` | Create job from map, the job list with per-job detail (lines, exceptions, activity), the backlog section, the scheduled section, the schedule form. |
| View modes | `PlannerApp.tsx` `viewMode: 'plan' | 'schedule'` | The surface this epic reshapes. |

**The gap is exactly one thing:** the job cards (559) are not on the main surface and not draggable;
their only path to a day is the modal form. Everything else is reuse.

---

## 3. MVP scope — four stories

### US-BOARD-1-01 — The Jobs column
The plan view gets a left column listing every waiting card from 559, grouped under its job's
title, each row: role · steps · minutes · estimate badge · exception chips (from/sent-on, reusing
EXC-2's components). A count in the header ("Jobs (7)" = jobs with waiting work). Clicking a job's
title opens the slimmed Jobs modal on that job (detail, not scheduling).

```gherkin
Scenario: Seeing what needs a day
  Given my plan has two jobs with unscheduled cards and one fully scheduled job
  When I open the planner
  Then the Jobs column lists the two jobs with their waiting cards
  And each card shows role, steps, minutes and its estimate badge in words
  And the fully scheduled job is not in the column
```

### US-BOARD-1-02 — Drag a card onto a day
Dragging a card onto an agent's day calls the SAME `scheduleCard` (583) the form called, through
the SAME `onEnsureTimeline`. A published day refuses with the server's sentence and the card stays
put. **Drag is an enhancement, not the only path:** each card keeps a "Place…" button (who + day,
the old form inline) so keyboard and touch users are not locked out.

```gherkin
Scenario: One motion instead of four
  Given Maria has an unpublished Tuesday
  When I drag the "Wash & Clean" card onto Maria's Tuesday
  Then the card leaves the Jobs column and appears in Tuesday's sequence with its minutes
  And the board refetches so capacity numbers update

Scenario: A published day refuses
  When I drop a card on a published day
  Then I see the server's own sentence and the card is still in the Jobs column

Scenario: No mouse
  When I use the card's "Place…" button and pick Maria and Tuesday
  Then the result is identical to the drag
```

### US-BOARD-1-03 — The day's sequence, with its jobs
A day column's job-card slots render like the reference's stop list: position, job title, role,
minutes, and an Unschedule control (hidden on published days, exactly the modal's rule). Nothing
new is computed — this is the modal's "Scheduled" section moving to where the day already is.

```gherkin
Scenario: What is Maria doing Tuesday
  Given Tuesday has two job cards and a plain task
  When I look at Maria's Tuesday column
  Then I see them in sequence with minutes, job cards marked by their job title
  And Unschedule appears on each job card because the day is not published
```

### US-BOARD-1-04 — Slim the Jobs modal
Remove the backlog section, the scheduled section and the schedule form from `JobsModal.tsx`
(RPT-1 already took Planned-vs-actual). What remains is per-job: create a job from a map, lines,
exceptions, activity — with one-line notes saying where scheduling went. Nothing is deleted from
the product; it is relocated, the RPT-1 precedent.

```gherkin
Scenario: The modal is about one job now
  When I open a job in the Jobs modal
  Then I see its lines, exceptions and activity
  And I do not see "Work waiting for a day" or a schedule form
  And a line tells me scheduling now happens on the board
```

### Deferred (not MVP)
- Multi-select / bulk place. — Resequence/Optimize. — Cost header from the reference (capacity
  summary already exists in `BacklogDrawer`'s panel; unifying it is its own story). — Retiring the
  plain-task `BacklogDrawer` (see Q-2). — Any phone layout for the planner (it is `md+` today).

---

## 4. Decisions

- **D-1 — No new backend.** 559 + 583 + ensure-timeline cover every story. If a story seems to
  need a new endpoint, the story is wrong.
- **D-2 — Words, not codes** (anti-pattern from the reference). No column may show an id a human
  didn't name. Ids appear only inside "#N" chips that open something.
- **D-3 — Drag never bypasses the server's rules.** The drop handler calls the same endpoint with
  the same refusals; a refused drop restores the exact prior state and shows the server sentence.
- **D-4 — Every path has a click alternative** (the "Place…" button). Drag-only UI fails keyboard,
  touch and E2E hit-testing.
- **D-5 — The modal survives as the job-detail surface** (D-2 of EXC-2 still holds: one read-only
  job view everywhere). Create-job stays in it for now.
- **D-6 — The card stays the unit** (BLK-1): you place a job's work for one role as one thing;
  this epic never schedules a single step.

## 5. Open questions (founder)

- **Q-1:** Jobs column rows — grouped under job titles (recommended, matches "Jobs (28)" reading)
  or one flat list of cards?
- **Q-2:** The old plain-task backlog (`BacklogDrawer`) — keep beside the Jobs column, or fold
  plain tasks into the same column as a "Quick tasks" group? (Recommend: fold, later story.)
- **Q-3:** Should create-job move out of the modal onto the Jobs column header ("+ New job")?
  (Recommend: yes, it is one button; can ride US-01.)

---

## 6. Governance

- **Tables / schema / deletes:** none. Frontend only.
- **Validation:** all writes go through 583's existing preconditions (published day, tenancy,
  already-scheduled); the UI repeats none of them, it only renders the sentences.
- **Error codes:** no new ones expected; 583's catalog entries already exist. A failed drop logs
  `feature: 'BOARD-1', step: 'card_drop', outcome: 'failure'|'rejected'` client-side (OBS-1), with
  the card_key and target in metadata.
- **Events:** 583 already logs success/failure server-side; do not duplicate the success event
  client-side.
- **UI helps, server validates again:** a drop the UI believed legal but the server refuses must
  keep the backlog state consistent — refetch on every refusal.

## 7. Test plan

| ID | Kind | What |
|---|---|---|
| UT-BOARD-1-01..n | unit | A pure `boardModel.ts`: grouping cards under jobs, the column's order, the "jobs with waiting work" count, day-sequence assembly. Golden cases include a job whose cards are all scheduled (absent) and a card with `estimate_status: 'incomplete'`. |
| UT-BOARD-1-0n | unit | Drop-intent rule: (card, agent, date, published?) → allow / refuse-reason, tested apart from the DOM. |
| E2E-BOARD-1-01 | e2e | Jobs column renders, drag to an unpublished day, card moves, sequence shows it (Playwright `dragTo`). |
| E2E-BOARD-1-02 | e2e | Drop on a published day → server sentence, card still in column. |
| E2E-BOARD-1-03 | e2e | "Place…" click path end-to-end equals the drag. |
| REG | — | Full unit suite, tsc, build, existing Playwright specs (several assert the modal's current sections — `jobs-and-day-navigation.spec.ts`, `card-scheduling.spec.ts` WILL need updating in US-04, which is expected, not drift). |

**Known honestly:** every e2e spec skips without `E2E_AUTH_TOKEN` (repo-wide baseline since APP-1);
the new specs get written and run the day a test login exists.

## 8. Completion gate

1. All four stories built; `boardModel` unit tests green; full suite, tsc, build green.
2. The modal no longer schedules anything, and the two e2e specs that asserted it are updated.
3. A browser pass by the founder on the real plan: find work, drag it, see the day, take it back off.
4. Founder answers Q-1..Q-3 (Q-1 before US-01 is built; the others can land as follow-ups).
