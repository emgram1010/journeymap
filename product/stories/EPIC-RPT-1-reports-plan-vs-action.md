# EPIC-RPT-1 — Reports → Plan vs Action

**Status:** ✅ **Built 2026-10-28.** Frontend only. No backend, no schema, no new endpoint.
**Model:** Opus 5 (the session already running; the work is low-risk UI).
**Depends on:** VAR-1 (endpoint 568, `GET variance/work_item/{id}`) — built and live since 2026-10-15.
**Blocks:** nothing.
**Risk:** low. Read-only. One existing block moves; nothing is deleted and no data changes.

---

## 1. Goal

**Planned vs actual becomes its own page, reached from a new "Reports" group in the left menu,
directly under Execution.**

The founder asked for it in one line: a new menu option under Execution called **Reports**, with a
sub-item **Plan vs Action**, and the Plan-vs-Actual block moved out of the Jobs section into it.

**As a** product manager, **I want** plan-vs-actual on its own page in the menu, **so that** I can
ask "did this take what we said it would?" without first opening the planner, opening Jobs, finding
the job and expanding it.

**Why it is worth moving rather than copying:** the report answers a question you *arrive* with, not
a question about a job you already have open. In the Jobs modal it was a four-line table inside an
expanded row — the right numbers in a place nobody goes to read numbers. Two copies would also mean
two places to keep honest.

---

## 2. What changed

| # | Change | File |
|---|---|---|
| 1 | New left-nav **group** "Reports" (icon `BarChart3`), directly under Execution, with one sub-item **Plan vs Action**. Groups are new: a `NavItem` with `children` renders as a header button that opens/closes, and only its children navigate. | `webapp/protype-2/src/AppLayout.tsx` |
| 2 | New page `PlanVsActionPage` — plan picker, job picker, summary line, and the full planned/actual/difference table with outliers and warnings. | `webapp/protype-2/src/reports/PlanVsActionPage.tsx` (new) |
| 3 | New pure module: which jobs the pickers offer and in what order. | `webapp/protype-2/src/reports/reportsModel.ts` (new) |
| 4 | Routes `/reports` (redirects) and `/reports/plan-vs-action`. | `webapp/protype-2/src/main.tsx` |
| 5 | The "Planned vs actual" block and its 568 fetch **removed** from the Jobs modal; a one-line note says where it went. "What the performer reported" stays — that one *is* about a job you already have open. | `webapp/protype-2/src/planner/components/JobsModal.tsx` |
| 6 | `jobStatusLabel` extracted to the one place both screens read it from (CLAUDE.md: a shared rule lives in its own function, not a copy per reader). | `webapp/protype-2/src/jobModel.ts` |

**No backend change.** The page calls three endpoints that already existed and were already in use:
`GET workspace`, `GET workspace/{id}/work_item`, `GET variance/work_item/{id}`.

---

## 3. Decisions

- **D-1 — "Reports" is a group header, not a link.** It is not a page. A header that navigated
  somewhere would leave two things highlighted at once (itself and the child it opened).
- **D-2 — The group starts expanded.** With one report in it, starting collapsed hides the only
  thing in the group and costs a click on every visit. It stays however the user last left it
  (the sidebar never unmounts).
- **D-3 — Gated on the `planning` module, not `execution`, despite sitting under Execution.**
  Before the move this report was reachable only through the planner's Jobs modal, so everyone who
  could read it had the planning module. **A move must not widen who can see something.** One line
  in `AppLayout.tsx` and one in `main.tsx` change it if the founder wants it on `execution`.
- **D-4 — The report opens on a job that has something recorded** (then newest first). A report
  that opens on an untouched job shows an empty table and reads as broken.
- **D-5 — Mobile shows the group's children immediately,** with no disclosure. The phone menu is a
  one-shot sheet; spending a tap on a toggle that closes again is waste.
- **D-6 — Still read-only, like the endpoint.** Nobody reports variance by hand (VAR-1's own first
  sentence); every figure is derived on each load. Nothing on this page writes.

---

## 4. Gherkin

```gherkin
Scenario: Reaching the report
  Given I am signed in with the planning module
  When I open the left menu
  Then I see "Reports" directly under "Execution"
  And under it a sub-item "Plan vs Action"
  When I click "Plan vs Action"
  Then I land on /reports/plan-vs-action

Scenario: The report opens on something worth reading
  Given my plan has three jobs and only one has been worked on
  When I open Plan vs Action
  Then the job picker has selected the job that has been worked on
  And the table shows one row per step with planned, actual and the difference

Scenario: A job nobody has started
  Given I pick a job with no recorded time
  Then I see "No steps to compare yet — nothing has been recorded against this job."
  And no row claims a figure it does not have

Scenario: A plan with no jobs
  Given I pick a plan that has no jobs
  Then I am told to start one from the Planner's Jobs screen
  And the job picker is disabled rather than empty and clickable

Scenario: The read fails
  Given the variance endpoint returns an error
  Then I see a friendly sentence and a "Try again" button
  And a failure event is recorded (feature RPT-1)

Scenario: The old place
  Given I expand a job in the planner's Jobs screen
  Then I no longer see "Planned vs actual" there
  And I see "Planned vs actual now lives in Reports → Plan vs Action."
  And "What the performer reported" is still there
```

---

## 5. Governance

- **Tables:** none touched. No schema change, no migration, no backfill.
- **Deletes:** none.
- **Validation:** nothing is typed on this page — both inputs are `<select>`s over ids the server
  returned. A plan or job id the caller does not own is refused by the endpoints (account tenancy,
  568 `precondition`), not by this page.
- **Errors:** three reads, three friendly sentences, one "Try again" that retries whichever failed
  (a nonce in both effects' deps — reloading the plan list alone would not re-fetch a report whose
  job id never changed).
- **Events (OBS-1):** every failed read logs `feature: 'RPT-1'`, `step: plans_load | jobs_load |
  variance_load`, `outcome: 'failure'`, `severity: 'warn'`, with the message and the job id.
  **No new error catalog codes** — these are read failures with no user-facing code, the same shape
  `logEvent`'s optional `errorCode` is for. If the founder wants them on the Health page by code,
  that is one catalog entry per step and a `errorCode` line here.
- **Visibility:** unchanged by design (D-3).

---

## 6. Test Results

Run 2026-10-28, local, against the live workspace for the backend reads.

| ID | What | Result |
|---|---|---|
| UT-RPT-1-01 | `reportJobOptions`: one option per job with planner status words | ✅ PASS |
| UT-RPT-1-02 | `reportJobOptions`: "1 of 1 step done" singular; `task_count: 0` → "No steps", never "0 of 0" | ✅ PASS |
| UT-RPT-1-03 | `reportJobOptions`: recorded jobs first, then newest id first | ✅ PASS |
| UT-RPT-1-04 | `reportJobOptions`: an unknown status is shown as it arrived | ✅ PASS |
| UT-RPT-1-05 | `reportJobOptions`: does not mutate the list it was given | ✅ PASS |
| UT-RPT-1-06 | `firstJobToShow`: the recorded job, and `null` for an empty plan | ✅ PASS |
| UT-RPT-1-07 | `jobStatusLabel`: all five statuses, plus unknown and empty pass through | ✅ PASS |
| REG-01 | Full unit suite (`npm test -- --run`) | ✅ PASS — 636/636 (628 before, +8 new) |
| REG-02 | `npx tsc --noEmit -p .` | ✅ PASS — 0 errors |
| REG-03 | `npm run build` | ✅ PASS |
| REG-04 | Existing Playwright specs | ✅ No new failures — they skip without an auth token (repo-wide baseline) |

**Not covered, honestly:**

- **No e2e for the new nav or page.** Every spec in this repo calls `test.skip` without
  `E2E_AUTH_TOKEN` / `PERFORM_TEST_AUTH_TOKEN`, so a new spec would be written and never run. Same
  gap as EXC-2's E2E-EXC-2-01/02/05.
- **Not opened in a real browser.** The three endpoints behind it were already live and already
  called by the Jobs modal with the same arguments, and the table renders the same rows from the
  same helpers — but nobody has looked at the page itself.

---

## 7. What is left

- A browser pass on the page (founder or a session with a test login).
- Optional: a second report under the group (the group exists precisely so the next one is one line
  in `children`).
- Optional: `errorCode`s in the catalog for the three read failures, if they should group on the
  Health page.
