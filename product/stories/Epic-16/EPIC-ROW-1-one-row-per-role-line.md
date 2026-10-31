# EPIC-ROW-1 — One row per role line, and the job name stops offering a new job

**Status:** ✅ **All three stories built 2026-10-31**, same session as the design. Typecheck, 650/650
unit, build and 47-spec parse all green; **zero e2e spec edits needed** (D-5 held). One deviation —
the pure flatten function this spec asked for was withdrawn as dead code, see §10. **Not done: the
founder browser pass** (§8 item 4), the gate item for this epic.
**Default model:** spec'd **Sonnet 5.5**; actually built on **Opus 5** (§10). No Opus review pass
required — see §6.
**Depends on:** QUE-1 (Epic-15 — the Unscheduled grid and its Stages panel, built 2026-10-30/31),
EXC-2 (`JobPeekSheet`, the read-only job view — live).
**Blocks:** nothing. This is polish on the surface QUE-1 just built.
**Risk:** **low.** No schema, no endpoint, no new state. The one thing to get right is not
breaking the 26 e2e locators that scope themselves to a job group — and §4's D-5 says how to
avoid that entirely.

---

## 1. Goal

Two things the founder found by using the screen, 2026-10-31:

> *"Basically two lines for a job … the first one, a role, and that pretty much takes up all the
> real estate. And then the other one is a task details. … Should we have it just in one line,
> somehow squeeze the role in the same row that you already have the task and details?"*

> *"When you click on the role on the unscheduled, it opens up new jobs. Is that really necessary
> considering where it's at right now, which is unscheduled? Why would we need to create a new job
> in unscheduled?"*

Both are right, and both are cheap to fix:

| | Today | Wanted |
|---|---|---|
| **A job in Unscheduled** | Two rows: a full-width job-title row, then its role line underneath. A job with one role line spends half its height on a header. | **One row.** `Job · Role` in the Role/Task cell, Steps / Min / Est. unchanged. |
| **Clicking the job name** | Opens `JobsModal` — the surface whose top half is the "+ New job" creation form. | Opens **`JobPeekSheet`**, the read-only job view that already exists and is already wired into this very file. |

Settled with the founder the same day: **flat, one row per role line, no group header.** Asked
explicitly ("always flat, or keep a group header only when a job has 2+ role lines?") and answered
"a few lines, concise."

---

## 2. What exists today (verified 2026-10-31 — re-verify before building)

In `webapp/protype-2/src/planner/components/BacklogDrawer.tsx`:

- The Unscheduled list is a `<table className="w-full table-fixed">` with one `<thead>`:
  `Role / Task` (no declared width, the one flexible column) · `Steps` `w-12` · `Min` `w-24` ·
  `Est.` `w-36` · actions `w-[52px]`. Five columns.
- One **`<tbody data-testid="unscheduled-job-group">` per job**, produced by `groupCardsByJob`
  (`boardModel.ts`, built and unit-tested in BOARD-1 — reused, not rewritten).
- Inside each `<tbody>`, first a **group-header row**: `<tr><td colSpan={5}>` wrapping a button
  `data-testid="unscheduled-job-title"` that calls `onOpenJob(group.workItemId)`.
- `onOpenJob` is wired in `PlannerApp.tsx:1356` to `setJobsFocusId(...)` + `setIsJobsOpen(true)` —
  i.e. **`JobsModal`**, which carries the new-job form. This is the behaviour the founder queried.
- Then one `<tr data-testid="unscheduled-card">` per role line, draggable, click-to-select (the
  selection drives the Stages panel on the right).
- The `Place…` form renders as its own **sibling detail `<tr>`** inside the same `<tbody>`, not
  nested in the card's row. This already caught the QUE-1 session out once; see D-5.
- `JobPeekSheet` is **already imported** (`BacklogDrawer.tsx:29`), already has state (`peekId`,
  line 133) and is already rendered (line 1141) for the exception chips. Nothing new to build.

Plain ad-hoc backlog tasks render in their own flat list below the job groups and are **out of
scope** — they have no job and already occupy one row each.

---

## 3. MVP scope — three stories

### US-ROW-1-01 — A role line is one row, carrying its own job name
**Status:** ✅ **Built 2026-10-31 (Opus 5 — see §10 for why not Sonnet).** The group-header `<tr>`
is gone; each role line's first cell now renders `Job · Role` as one truncating string, with the
full `Job · Role` on the cell's `title` for hover. The per-job `<tbody>` was kept exactly as D-5
requires. **Deviation: the pure `flattenJobGroupsToRows` function this story called for was written,
tested (6 cases, green), and then removed again — D-5 makes it dead code.** The reasoning is in
§10; it is the one real deviation in this epic.

**As a** planner looking at what is ready to place,
**I want** each role line on a single row that tells me which job it belongs to,
**so that** the list shows me twice as much work per screen without my losing track of the job.

```gherkin
Scenario: A job with one role line takes one row
  Given a job "Bounce V3 · Moon bouncer repair" has one role line "Repair Tech" with no day
  When I look at the Unscheduled list
  Then I see exactly one row for it
  And that row's first cell reads the job name and the role, in that order
  And the Steps, Min and Est. cells are unchanged from before
  And no full-width job-title row appears above it

Scenario: A job with several role lines repeats its name, adjacently
  Given a job has role lines "Repair Tech" and "QA"
  When I look at the Unscheduled list
  Then I see two rows, one per role line
  And both rows name the same job
  And the two rows are next to each other, with no other job's row between them

Scenario: A long job name does not push the numbers off the row
  Given a job whose name is longer than the Role / Task column
  When I look at its row
  Then the first cell truncates with an ellipsis
  And hovering it shows the full job name and role
  And the Steps, Min and Est. cells stay in their columns
```

**Build notes.** The flattening itself is a pure transform and belongs in `boardModel.ts` next to
`groupCardsByJob`, not in JSX: a function taking the grouped output and returning one row per role
line, each carrying `workItemId`, `jobTitle`, the card, and its position within its job. Unit-test
the ordering guarantee (D-2) and the label fallback. Keep the per-job `<tbody>` (D-5).

---

### US-ROW-1-02 — The job name opens the read-only job view, not the new-job modal
**Status:** ✅ **Built 2026-10-31.** The job name is a button calling the `setPeekId(...)` that the
exception chips in the same file already used — `JobPeekSheet`, read-only, no new component and no
second path. It `stopPropagation()`s so clicking the name opens the job without also selecting the
row (the row click still drives the Stages panel). **`onOpenJob` became genuinely dead and was
deleted** — the prop, its destructure, and its `PlannerApp.tsx` wiring, as the build note required.
Nothing in the planner can now reach `JobsModal` from Unscheduled.

**As a** planner,
**I want** clicking a job's name in Unscheduled to show me that job,
**so that** I am not offered a form for creating a different job I did not ask for.

```gherkin
Scenario: The job name opens the job, read-only
  Given a role line's row names its job
  When I click the job name
  Then the read-only job view opens for that job
  And no new-job form is shown anywhere on screen

Scenario: Clicking the row is still how I see the stages
  Given a role line's row
  When I click the row anywhere other than the job name
  Then the row is selected
  And its stages appear in the Stages panel on the right

Scenario: Creating a job is still possible, from the jobs list
  When I want to create a job
  Then the "+ New job" button on the jobs list header is still the way to do it
```

**Build notes.** Swap the click target to the existing `setPeekId(workItemId)` that the exception
chips in this same file already use — reuse, do not add a second path (EXC-2's D-2: one read-only
job view everywhere). The `onOpenJob` prop may end up unused by this file; if so **delete it**
rather than leaving it wired to nothing, and remove it from `PlannerApp.tsx`'s render too. Check
first whether anything else in the drawer still needs it.

---

### US-ROW-1-03 — The e2e specs still describe the screen truthfully
**Status:** ✅ **Built 2026-10-31 — and it was the no-op D-5 predicted: zero spec edits.** All five
test ids the three specs rely on (`unscheduled-job-group`, `-card`, `-card-handle`, `-place`,
`-place-confirm`) still exist, unchanged. `filter({hasText: jobTitle})` keeps matching because the
job title moved *into* the rows rather than leaving the `<tbody>`. The `Steps` column is still
second, so `card-scheduling.spec.ts`'s `td:nth-child(2)` selector still points at it. Verified by
reading and by `playwright test --list`; as always, **never run** (no `E2E_AUTH_TOKEN`).

**As the** next session,
**I want** the Playwright specs to match the flattened list,
**so that** the day someone runs them they fail for real reasons only.

```gherkin
Scenario: Every spec that scopes itself to a job still resolves
  Given card-scheduling, jobs-and-day-navigation and planner-board each scope their
    assertions to a job's group in Unscheduled
  When the group-header row is removed
  Then each spec still finds that job's role lines
  And each spec still finds the Place… form belonging to them
```

**Build notes — read D-5 before touching any spec.** There are **26 references** across the three
specs to `unscheduled-job-group`, used both for scoping (`getByTestId('unscheduled-card')` within
one job) and for counting (`toHaveCount(cardsBefore - 1)`). D-5 keeps all of them working with no
edit. No spec references `unscheduled-job-title`, so that test id can go. Expect this story to be
close to a no-op — if it is turning into a rewrite, stop: D-5 has been broken.

---

## 4. Decisions

- **D-1 — One row per role line; job identity travels in the row, not a header.** The founder's
  call, 2026-10-31. The header only ever paid for itself when a job had 2+ role lines, and cost a
  row every time it had one.
- **D-2 — Role lines of the same job stay adjacent.** Flattening must preserve `groupCardsByJob`'s
  order, so a job's repeated name clusters instead of scattering down the list. Without this, a
  flat list reads as random repetition. This is the ordering guarantee US-ROW-1-01's unit test
  pins.
- **D-3 — The job name opens the read-only view (`JobPeekSheet`), and job creation stays on the
  jobs list header only.** Follows EXC-2's D-2, "one read-only job view everywhere". Unscheduled
  is a queue of work ready to place; creating new work is not one of its jobs.
- **D-4 — `Job · Role` truncates as one string, with the full text on hover.** Role / Task is the
  only column without a declared width (`table-fixed`), so it is the only one that can absorb a
  long name — and must, rather than pushing the numeric columns around.
- **D-5 — Keep the per-job `<tbody data-testid="unscheduled-job-group">`; remove only the visible
  header `<tr>` inside it.** This is the whole reason this epic is low-risk. The `<tbody>` is the
  structural scope 26 e2e locators depend on, and it has no visual weight of its own. Because the
  job title now appears in every row, even `filter({hasText: jobTitle})` keeps matching. Removing
  the `<tbody>` as well would turn a two-file change into a three-spec rewrite for no user-visible
  gain.
- **D-6 — Plain ad-hoc backlog tasks are untouched.** They have no job, already take one row, and
  live in their own list below.

---

## 5. Open questions (founder)

- **Q-1 — When a job has several role lines, should the repeated job name be dimmed (or dropped)
  on the second and later rows, "same as above" style?** Full repetition is the honest default and
  survives filtering, which is why it is specified that way; it also reads as noisy when a job has
  five lines. Not a blocker — build D-1 as written and look at it on the real screen.
- **Q-2 — Does "+ New job" stay on the jobs list header?** Carried over unanswered from QUE-1's
  own Q-2. US-ROW-1-02 assumes yes, because it has to assume something; this epic does not move
  that button.

---

## 6. Governance

- **No schema change, no new table, no new column, no delete.** Frontend only.
- **No new endpoint.** Everything renders from 559 (`listBacklogWork`), already fetched by this
  panel. `JobPeekSheet` fetches on its own, as it does today for the exception chips.
- **No new validation and no new error code** — nothing here takes user input.
- **No new success/failure event.** The only logging this epic touches is the `'invalid'` drop
  branch the Opus review added on 2026-10-31; leave it as it is.
- **No Opus review pass required**, and this is a deliberate call rather than an omission: unlike
  QUE-1's US-05/06, no story here can lose the founder's work. There is no write path at all — the
  riskiest thing that can happen is a row renders wrong. Per CLAUDE.md's model table, Sonnet 5.5
  is the right builder and a review pass is reserved for publish gates, status engines, guards and
  tenancy. Say so to the founder rather than silently skipping it.
- **Do not edit the QUE-1 epic** (Epic-15) while building this, even though this epic supersedes
  its group-header layout. Note the supersession in §10 here and ask before touching that file.

---

## 7. Test plan

| ID | Kind | What it proves |
|---|---|---|
| ~~UT-ROW-1-01-01..05~~ | ~~Unit~~ | **Withdrawn during the build, not skipped** — they tested `flattenJobGroupsToRows`, which D-5 made dead code. Written and green (6 cases) before the contradiction was spotted, then removed with the function. See §10. The behaviour they would have covered (D-2's adjacency, the `Job #id` fallback) is already covered by BOARD-1's own `UT-BOARD-1-01`/`-02`/`-03` on `groupCardsByJob`, which is still the only thing deciding job order and titles. |
| REG-01 | Suite | `npm test` — full unit suite green (650, unchanged: this epic adds no pure logic) |
| REG-02 | Typecheck | `npx tsc --noEmit` clean |
| REG-03 | Build | `npm run build` succeeds |
| REG-04 | Parse | `npx playwright test --list` — all 47 enumerate |
| REG-05 | E2E (never run) | The three specs in US-ROW-1-03 still locate their job groups |
| UI-01 | Founder | On the real plan: the list shows more work per screen, each row names its job, and clicking a job name opens the read-only view with no new-job form |

**Every e2e spec in this repo skips without `E2E_AUTH_TOKEN`.** Write them, report them as unrun,
and never record a skip as a pass.

---

## 8. Completion gate

1. All three stories built.
2. The five unit cases green, plus the full suite, `tsc` and `build`.
3. `playwright test --list` clean, and the three specs confirmed (by reading, not running) to
   still resolve their locators.
4. **A founder browser pass** — the one thing QUE-1 proved cannot be substituted with green
   checks, since the founder found both defects in this epic by looking at the running app.
5. Then stop and wait. Q-1 is answered from the real screen, not in advance.

---

## 9. Test Results (run 2026-10-31, build session — Opus 5)

| ID | Result |
|---|---|
| ~~UT-ROW-1-01-01..05~~ | ⚪ **Withdrawn, not skipped.** Written as 6 cases against `flattenJobGroupsToRows` and **green (16/16 in `boardModel.test.ts`)** before D-5 was recognised as making the function dead; removed with it. §7 records what still covers the behaviour. |
| REG-01 | ✅ PASS — `npm test`, 650/650 (unchanged; this epic adds no pure logic) |
| REG-02 | ✅ PASS — `npx tsc --noEmit`, 0 errors (run four times across the build) |
| REG-03 | ✅ PASS — `npm run build` (pre-existing chunk-size warning only) |
| REG-04 | ✅ PASS — `npx playwright test --list`, 47 tests across 18 files |
| REG-05 | ✅ **Zero spec edits needed** — D-5 held. All five relied-on test ids intact, `filter({hasText:})` still matches, `td:nth-child(2)` still the Steps column. Confirmed by reading + `--list`; **never run** (no `E2E_AUTH_TOKEN`, repo-wide baseline). |
| UI-01 | ❌ **Not done.** No founder browser pass yet. This is the gate item, and it is the one that found both defects this epic fixes. |

**A near-miss worth recording.** The first attempt to remove the withdrawn function used
`git checkout -- boardModel.ts boardModel.test.ts`. That would have reverted both files to HEAD —
destroying QUE-1's **uncommitted** `classifyUnscheduleTarget` and its three unit tests along with
the new code. The sandbox refused the command as irreversible local destruction, and the removal
was redone surgically instead. Nothing was lost. The lesson is narrower than "be careful": with a
whole epic sitting uncommitted, `git checkout --` is never the way to undo one edit in a file that
also holds work you want.

---

## 10. Notes

- **The one deviation: D-5 and US-ROW-1-01's build note contradicted each other, and D-5 won.**
  The story said to put the flattening in a pure function in `boardModel.ts`; D-5 said to keep the
  per-job `<tbody>`. Both were written into this spec in the same sitting without noticing that the
  second makes the first pointless — if the markup still iterates groups to emit a `<tbody>`, there
  is nothing left for a flatten function to do. It was written and unit-tested (6 cases, green)
  before that landed, then removed. **The rendering is now `groups → tbody → one row per card`,
  with the job title read from `group.jobTitle` inside the row.** No abstraction was added, because
  none was needed. Recorded rather than quietly dropped, because the spec is wrong on this point
  and the next reader deserves to know which half to trust.
- **Model: built on Opus 5, not the Sonnet 5.5 this file specifies.** The founder had switched to
  Opus 5 earlier in the session for the QUE-1 review and said "start building" without switching
  back; they were told this before any code was written. This is the harmless direction of that
  mismatch — more capable, more expensive, no risk to their work — unlike the QUE-1 session, which
  built an Opus-marked story on Sonnet and had to disclose it after the fact. Noted so the cost is
  visible, not because the output is in doubt.
- **This epic supersedes part of QUE-1's US-QUE-1-02**, which specified the per-job group header
  row ("one `<tbody>` per job acting as that group's row header, the job name shown once, not
  repeated per role line"). That was the right call for the grid as designed; the founder changed
  their mind after using it, for a reason the original design could not have known — a job with one
  role line is the common case in their real plan, so the header was costing a row almost every
  time. Epic-15's file is **not edited** per its own rule and §6 above; this note is the record.
- **Both defects in this epic were found by the founder using the running app**, within minutes,
  on the same day four rounds of green typecheck / 650 unit tests / build / 47-spec-parse had
  found nothing. The QUE-1 Opus review made the same point from the other direction. Treat a
  browser pass as part of the gate, not a nicety.
- **The cheap-looking part is the risky part.** Dropping the `<tbody>` along with the header row
  would feel tidier and would quietly invalidate 26 e2e locators across three files. D-5 exists
  because that trap is invisible from the component's own source — exactly the shape of mistake
  the QUE-1 session made twice with these same specs.
- **`onOpenJob` may become dead.** If US-ROW-1-02 leaves nothing in the drawer calling it, delete
  the prop and its `PlannerApp.tsx` wiring rather than leaving a prop pointing at a modal nothing
  opens. CLAUDE.md: no backwards-compatibility shims, no unused re-exports.
