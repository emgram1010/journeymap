# EPIC-EXC-2 — Follow the work you sent

**Epic:** Epic-14 — Follow the work you sent
**Status:** 📝 **Designed 2026-10-27. Nothing built.**
**Default model:** **Sonnet 5.5.** Per-story models are in each story header and in
`START-HERE.md` §5. Haiku 5.5 for catalog entries and fixtures. Opus 5.5 for the optional
completion review and for any bug that fails twice.
**Depends on:** EXC-1 (phase 7) — built and live, **uncommitted** when this was written. Check
first (`START-HERE.md` §3).
**Blocks:** nothing.
**Risk:** low. No writes, no schema, no new status. The one place to be careful is the XanoScript
tally in US-EXC-2-01 (silent-failure traps, §4).

---

## 1. Goal

From **either module**, a person who sees that work was sent elsewhere can **open that other job
and see its steps, their statuses and how far along it is**, read-only — and a person working a
sent job can see where it **came from**.

**As a** performer whose step sent work elsewhere, **I want** to tap the "sent" chip and see that
job's steps and progress, **so that** I know whether the item is coming back and when.

**As a** performer working a sent job, **I want** to see which job and step it came from, and why,
**so that** I have the context (what broke, who sent it, the note) without asking.

**As a** planner, **I want** each sent job on a parent's detail to show its progress and open in
one tap, **so that** I can follow exceptions without hunting through the job list.

---

## 2. What exists today (verified 2026-10-27 — re-verify before building)

| Thing | Where | What it gives you |
|---|---|---|
| `GET work_item/{id}` | `apis/planner/555_work_item_work_item_id_GET.xs` (planner group, `api:PE5iDldw`) | One job: `work_item`, `parent`, `children` (both from `exceptions/job_links`), `pinned_version {id, version_no, title}`, `derived_status`, `tasks[]` each `{id, stage_key, lens_key, status, started_at, completed_at, stage_label, owner_lens_label, task, done_when, expected_minutes, …}`, `estimate_summary`. Tenancy check only (job's `account_id` = caller's). **No frontend wrapper exists for it yet.** |
| `GET work_item/{id}/links` | `apis/planner/611_work_item_work_item_id_links_GET.xs` | `parent`, `children[]`, `send_options[]` from `exceptions/job_links`. Wrapped as `getWorkItemLinks` in `webapp/protype-2/src/planner/plannerApi.ts:826`. |
| `exceptions/job_links` | `functions/exceptions/job_links.xs` | Builds `parent` `{work_item_id, title, status, stage_key, stage_label, reason_code, note, moved_lines, created_at, via}` and each child `{work_item_id, title, status, target_map_title, stage_key, stage_label, reason_code, note, moved_lines, parent_blocked, created_at, via}`. **No progress fields.** |
| Performer step screen | `webapp/protype-2/src/perform/StepScreen.tsx:152` renders `ExceptionSendPanel variant="performer"` | Shows the "Send to…" button and, for work sent from *this* step, chips `"{n} → #{id}"`. |
| Sent chips | `webapp/protype-2/src/exceptions/ExceptionSendPanel.tsx` ~line 172–188 | `<span data-testid="exception-chip">` — **not interactive**. Planner variant adds ` · {stage_label}`. |
| Planner job list | `webapp/protype-2/src/planner/components/JobsModal.tsx` | Row: title, "{status} · {finished} of {total} steps done", `job-parent-chip` "from #N" (works → `showJob(parent)`), `job-children-chip` "N sent on" (**calls `showJob(job.id)` — opens the parent itself**). Expanded detail: `ExceptionSendPanel variant="planner"`, `JobLinesEditor`, variance, "What the performer reported". |
| Performer data | `webapp/protype-2/src/perform/performApi.ts` (`performRequest`, same planner base URL) | Today snapshot + live statuses. A performer's session/step screens only know jobs on their published day. |
| Client event logging | `webapp/protype-2/src/ops/logEvent.ts` → `logEvent({feature, step, outcome, severity, errorCode, entityType, entityId, …})` | Rate-limited, offline-buffered, posts to `/ops/event` (Ops group). |
| Error catalog | `functions/ops/error_catalog.xs` **and** `webapp/protype-2/src/ops/errorCatalog.json` (158 entries; highest EXC code **E-EXC-013**) | Must change together. `ops/errorCodeRegistry.test.ts` (GUARD-REG-01) and `ops/errorCatalog.test.ts` (UT-OBS-1-01/02/03) enforce it. |
| EXC-1 e2e | `webapp/protype-2/e2e/exceptions.spec.ts` | Has the hit-test helper pattern (E2E-EXC-1-06). Reuse it. |

**Who can read another job today:** anyone signed in to the same account (555/611 check tenancy
only). EPIC-USR-2 (module access, `product/stories/Epic-13/`) has **not** attached its middleware
yet, so nothing is module-gated. See **Q-1** and **D-6**.

---

## 3. Builder brief

### Read first (in this order)

1. `functions/exceptions/job_links.xs` — you extend it in US-EXC-2-01.
2. `apis/planner/611_work_item_work_item_id_links_GET.xs` and `apis/planner/555_work_item_work_item_id_GET.xs` (whole file — note how it hydrates tasks from the pinned snapshot and the "k:" key-prefix trick).
3. `webapp/protype-2/src/exceptions/ExceptionSendPanel.tsx`, `exceptionSheet.ts` (+ its test).
4. `webapp/protype-2/src/perform/StepScreen.tsx`, `SessionScreen.tsx`, `PerformToday.tsx`, `performApi.ts`.
5. `webapp/protype-2/src/planner/components/JobsModal.tsx` (rows ~480–560, `showJob` ~337).
6. `webapp/protype-2/src/planner/plannerApi.ts` (`getWorkItemLinks`, the `JobChildLink` type).
7. `webapp/protype-2/e2e/exceptions.spec.ts` (fixtures, login, the hit-test helper).

### Files you will create

| File | Story |
|---|---|
| `webapp/protype-2/src/exceptions/jobProgress.ts` + `jobProgress.test.ts` | 02 |
| `webapp/protype-2/src/fixtures/job-progress-golden.json` | 01, 02 (shared by both sides) |
| `webapp/protype-2/src/exceptions/JobPeekSheet.tsx` | 02 |
| `webapp/protype-2/e2e/follow-sent-work.spec.ts` | 03, 04, 05 |

### Files you will change

| File | Story | Change |
|---|---|---|
| `functions/exceptions/job_links.xs` | 01 | Add `progress` to `parent` and to each child. |
| `webapp/protype-2/src/planner/plannerApi.ts` | 01, 02 | `JobChildLink`/parent types gain `progress`; add `getWorkItem(id)` wrapper for 555. |
| `webapp/protype-2/src/exceptions/ExceptionSendPanel.tsx` | 03, 04 | Chips become buttons that open `JobPeekSheet`; show progress. |
| `webapp/protype-2/src/perform/StepScreen.tsx` (and/or `SessionScreen.tsx`) | 03 | "Came from" chip on a child job's step/session. |
| `webapp/protype-2/src/planner/components/JobsModal.tsx` | 04 | "N sent on" opens the child (or the view); progress on chips. |
| `functions/ops/error_catalog.xs` + `webapp/protype-2/src/ops/errorCatalog.json` | 05 | E-EXC-014, E-EXC-015. |
| `product/stories/Epic-14/EPIC-EXC-2-follow-sent-work.md` | all | Test Results. |

**Not changed:** 610, 611's own XanoScript (it just returns what `job_links` gives it), 555's
XanoScript (same), any table, `log/*`, publish code.

### Order

US-01 → US-02 → US-03 → US-04 → US-05, tests first in each. US-05's catalog entries can be
written at the start (Haiku) so 02–04 can reference real codes.

---

## 4. XanoScript traps that WILL bite US-EXC-2-01

All from `CLAUDE.md`, all found live. Re-read the full entries there.

1. **`|get` with a variable key drops its default.** A per-child tally `$counts|get:$k:0` returns
   `null` for a missing key → `null + 1` = `null`. **Pre-seed** every child's counters to 0 in a
   first loop over `$child_jobs`, then tally in a second loop.
2. **A `conditional` inside a `foreach` that reads a var `var.update`d earlier in the same pass
   silently discards its writes.** Branch only on the loop item (`$t.status == "done"`) or avoid
   branching: use `(($t.status == "done" || $t.status == "skipped")|to_int)` — bool `|to_int` gives
   0/1 (confirmed) — and add it.
3. **A ternary or `|filter:arg` as an object-literal value silently deletes every key after it.**
   Hoist every computed value into a `var` first, or wrap the whole expression in its own
   parentheses. Never write `progress: {done: …, label: $x|get:…}` inline.
4. **`$obj|get:"":x` returns the whole object.** Prefix lookup keys: `"c:" ~ child_id`,
   `"k:" ~ stage_key`. `job_links` already does this — keep the pattern.
5. **`[index]` on a script-built array fails; "first match" via a found-flag in a loop hits trap 2.**
   For "current stage" use positions + `|max` (confirmed working on an `array.push` array):
   push `0 - position` for every unfinished step, take `|max`, negate → lowest unfinished
   position. Seed the array with a sentinel (e.g. `-999999`) so `|max` of an all-finished job is
   defined, and treat the sentinel as "none". **Probe `|max` on a small array with a scratch
   function before relying on it** (CLAUDE.md lists it as confirmed, but this exact use is new).
6. **`where` clauses cannot call filters.** Build `$child_ids` (seeded `[-1]`) first, then
   `db.query work_task { where = $db.work_task.work_item_id in $child_ids }` — **one query for all
   children, never one per child.**
7. **Optional/absent JSON keys:** read snapshot fields through `??` into a `var` before any
   condition (`$v.snapshot.stages ?? []`). A bare `$obj.missing` in a condition throws.
8. **After the push, smoke-test with real, non-empty data** (a child with 0 done, one with some
   done, one all done, one blocked, one cancelled). A clean push proves nothing.

---

## 5. Stories

### US-EXC-2-01 — Progress on the family list (backend)

**Model:** Sonnet 5.5.
**As a** client of `GET work_item/{id}/links` and `GET work_item/{id}`, **I want** every parent
and child entry to carry a progress summary, **so that** both modules can show "2 of 6 · at Repair"
without loading each job separately.

**Shape** (added to `parent` when not null, and to every element of `children`):

```json
"progress": {
  "task_count": 6,
  "finished_count": 2,          // status done OR skipped (D-4)
  "has_blocked": false,          // any step blocked
  "current_stage_key": "s3",     // stage of the lowest-position unfinished step, "" when all finished
  "current_stage_label": "Repair" // label from THAT job's pinned version, "" when all finished
}
```

"Position" = the stage's index in **that job's own** pinned `snapshot.stages` order (a child and
its parent are on different maps). Steps whose stage is missing from the snapshot sort last.

**Approach:**
- After `$child_jobs` is loaded: build `$child_ids` (seed `[-1]`), one `db.query work_task` for all
  of them, plus one for the parent if `$job.parent_work_item_id != 0`.
- Stage positions: `$child_versions` is already loaded — build `"v:<version_id>::<stage_key>" →
  position` and `"v:<version_id>::<stage_key>" → label` maps from each `snapshot.stages`.
- Pre-seed `"c:<child_id>"` counters, tally with `|to_int`, collect `0 - position` per unfinished
  step into a per-child array keyed `"c:<id>"` (a map of arrays: `|get` → `array.push` → `|set`;
  pre-seed each with `[-999999]`).
- Hoist everything into vars, then build the `progress` object from plain vars.
- The parent's progress uses the same logic on the parent's tasks and the parent's version.
  **Write it once**: if the shape gets long, extract a small function
  `exceptions/job_progress` (input: `work_item_ids int[]`, output: map `"c:<id>" → progress`)
  and call it from `job_links` for both — the "one rule, one place" house rule (CLAUDE.md, LOG-1).

**Acceptance (Gherkin):**

```gherkin
Scenario: A sent job that hasn't started
  Given a parent job with one child job on a 6-stage linked map, no child step started
  When I GET work_item/{parent}/links
  Then children[0].progress is {task_count: 6, finished_count: 0, has_blocked: false,
       current_stage_key: <first stage key>, current_stage_label: <first stage label>}

Scenario: Part-way, with a skipped step
  Given the child's stage 1 is done and stage 2 is skipped
  Then finished_count is 2 and current_stage_label is the 3rd stage's label

Scenario: Blocked
  Given the child's stage 3 is blocked
  Then has_blocked is true and current_stage_label is stage 3's label

Scenario: All finished
  Given every child step is done or skipped
  Then finished_count equals task_count and current_stage_key is ""

Scenario: The child sees its parent's progress
  When I GET work_item/{child}/links
  Then parent.progress describes the PARENT's steps, with labels from the PARENT's map

Scenario: The same data through 555
  When I GET work_item/{parent}
  Then children[0].progress is identical to what 611 returned

Scenario: A job with no family
  Then parent is null and children is [] — no error, no extra queries per child
```

**Counter-measures:** the five trap rules in §4; one query per table, not per child; golden
fixture shared with the TypeScript twin (US-02) so both sides compute the same answer.

---

### US-EXC-2-02 — One read-only job view, for both modules (frontend)

**Model:** Sonnet 5.5. **Ask Q-1 before starting.**
**As a** person in either module, **I want** one sheet that shows another job's steps and
progress, **so that** I see the same thing whether I came from a step or from the planner.

**Build:**
- `plannerApi.ts`: `getWorkItem(workItemId)` → `GET /work_item/{id}` (planner base URL), typed to
  the 555 response in §2. Export a `JobProgress` type matching US-01.
- `exceptions/jobProgress.ts` (pure): `jobProgress(tasks, stageOrder)` → the US-01 shape, and
  `progressLabel(p)` → `"2 of 6 done · at Repair"`, `"Done"` (all finished), `"2 of 6 done · blocked at Repair"`.
  The TypeScript twin of US-01's rule, pinned by `fixtures/job-progress-golden.json`.
- `exceptions/JobPeekSheet.tsx`: props `{workItemId: number; open: boolean; onClose(): void; onOpenJob?(id: number): void}`.
  Loads `getWorkItem(workItemId)` when opened. Shows, top to bottom:
  1. **Header:** job title, map title + version (`pinned_version`), job status label, progress bar
     + `progressLabel`.
  2. **"Came from"** (when `parent` is set): "#125 · TurnAround · sent from Triage Damages",
     reason (plain label, the same `REASON_LABELS` the send sheet uses), the note, the counts that
     moved. Tapping it calls `onOpenJob(parent.work_item_id)` (opens the parent in the same sheet).
  3. **Steps:** one row per task, in stage order: stage label, owner row label, a status pill
     (Not started / In progress / Blocked / Done / Skipped), and — per **Q-1** — the step text and
     done-when, collapsed by default. The `current_stage` row is marked "Now".
  4. **"Sent on"** (when `children` is non-empty): one chip per child with its `progressLabel`;
     tapping calls `onOpenJob(child.work_item_id)`.
  5. **Sticky footer:** a single **Close** button (reachability rule).
- States: loading skeleton; **error** → catalog message for E-EXC-014 with a **Try again** button
  and the Reference (correlation id); **404** → E-EXC-015 message, no retry. Every failure also
  goes to `logEvent` (US-05).
- **Read-only (D-1):** no action buttons for the viewed job. Nothing in the sheet writes.
- Mobile first: full-height sheet at 375 px, scrolls inside, footer always visible.

**Acceptance:**

```gherkin
Scenario: Open a sent job
  Given job #P sent 1 item to job #C (6 steps, 2 done)
  When the view opens for #C
  Then I see #C's title, its map and version, "2 of 6 done · at <stage 3 label>"
  And six step rows in stage order, the first two "Done", the third marked "Now"
  And a "Came from #P" block with the stage it was sent from, the reason and the note
  And no button that changes #C

Scenario: Hop between parent and child
  When I tap "Came from #P"
  Then the same sheet shows #P, with #C under "Sent on" showing "2 of 6 done"

Scenario: The job can't be loaded
  Given the request fails
  Then I see the E-EXC-014 message, a Reference, and "Try again"
  And a failure event is logged once (not once per render)

Scenario: The job isn't there any more
  Given the request returns 404
  Then I see the E-EXC-015 message and no retry button
```

---

### US-EXC-2-03 — Execution: sent chips open the view; sent jobs show where they came from

**Model:** Sonnet 5.5.
**As a** performer, **I want** the "1 → #126" chip under *Send to…* to open that job, and a sent
job's steps to show where it came from, **so that** I can follow work across jobs from my phone.

**Build:**
- `ExceptionSendPanel.tsx`: each `exception-chip` becomes a `<button>` (keep `data-testid`,
  add `aria-label="Open sent job #126"`). Label: `"1 → #126 · 2 of 6"` (append `progressLabel`
  short form; keep the existing count prefix). Tap → `JobPeekSheet` for that child.
- The performer's step and session screens for a **child** job: a compact "Came from #125 ·
  Triage Damages" chip near the header (data from `getWorkItemLinks(workItemId).parent`, which
  `ExceptionSendPanel` already loads — reuse that fetch, do not add a second call per render).
  Tap → `JobPeekSheet` for the parent.
- After a successful send (existing `onSent`), the new chip appears with progress "0 of N".

**Acceptance:**

```gherkin
Scenario: Follow sent work from my step (375 px)
  Given I am on step "Triage" of job #P and I sent 1 item to #C earlier
  When I tap the chip "1 → #C · 0 of 6"
  Then the job view opens for #C showing its 6 steps, none started
  And Close returns me to my step with nothing changed

Scenario: The sent job's progress moves
  Given someone completes 2 of #C's steps
  When I reopen my step
  Then the chip reads "1 → #C · 2 of 6"

Scenario: Working a sent job
  Given #C is on my day and I open its first step
  Then I see "Came from #P · <stage>"
  And tapping it shows #P read-only

Scenario: No sent work
  Given nothing was sent from this step
  Then there is no chip and no extra request beyond what EXC-1 already makes
```

---

### US-EXC-2-04 — Planner: sent work shows progress and opens in one tap

**Model:** Sonnet 5.5.
**As a** planner, **I want** each sent job to show its progress on the parent and open directly,
**so that** I can follow exceptions without searching the job list.

**Build:**
- `ExceptionSendPanel variant="planner"`: same clickable chips as US-03, label
  `"1 → #126 · Triage Damages · 2 of 6"`. Tap → if the child is in this plan's job list, call the
  modal's `showJob(childId)` (expand and scroll to its row, existing behaviour); otherwise open
  `JobPeekSheet`. Pass a callback prop (e.g. `onOpenJob`) from `JobsModal`; the panel must not
  know about the job list.
- `JobsModal.tsx` row chip **"N sent on"**: fix it to open the work that was sent, not the parent
  itself. With one child → `showJob(childId)`. With several → expand the parent's detail and
  scroll to its *Exceptions* block (where each child chip now opens its job). Rename the title
  attribute to "Opens the work sent from this job".
- The child row's existing "from #N" chip is unchanged (it already works).

**Acceptance:**

```gherkin
Scenario: One tap from parent to sent work
  Given job #P in this plan sent 1 item to #C (also in this plan)
  When I click "1 sent on" on #P's row
  Then #C's row is expanded and scrolled into view

Scenario: Progress on the parent
  Given #C has 2 of 6 steps done
  When I expand #P
  Then its Exceptions block shows "1 → #C · <stage> · 2 of 6"

Scenario: Sent work outside this plan
  Given #C is not in this plan's job list
  When I click its chip
  Then the read-only job view opens for #C
```

---

### US-EXC-2-05 — Governance: codes, events, catalog, reachability

**Model:** Haiku 5.5 for the catalog entries and the golden fixture; Sonnet 5.5 for the rest.

| Item | Detail |
|---|---|
| **E-EXC-014** | user_message: "We couldn't open that job just now. Try again." · what_happened: "The job view failed to load the other job's steps." · likely_cause: "A dropped connection or a server error." · owner: engineer *(built as `engineer`, not `system` — the catalog's `owner` enum is `user\|product_manager\|engineer`; caught by `UT-OBS-1-01` failing on push)* · severity: warn · fix_hint: "Try again. If it keeps happening, quote the Reference to support." |
| **E-EXC-015** | user_message: "That job isn't available any more." · what_happened: "The job view asked for a job that no longer exists in this account." · likely_cause: "The job belongs to another account, or the link is stale." · owner: user · severity: info · fix_hint: "Nothing to fix on the job you're on. Ask a planner if the sent work was moved." |
| Catalog | Both entries in **both** `functions/ops/error_catalog.xs` and `webapp/protype-2/src/ops/errorCatalog.json`, one identical sentence each (GUARD-REG-01 pairs codes with messages). Push the function; run UT-OBS-1-01/02/03 and GUARD-REG-01. |
| Client events | `logEvent({feature: "EXC-2", step: "job_view_load", outcome: "failure", severity: "warn", errorCode: "E-EXC-014", entityType: "work_item", entityId})` on a failed load; `outcome: "rejected", severity: "info", errorCode: "E-EXC-015"` on a 404. **No success event per open** (reads are not logged — it would flood `event_log`; same stance as every other read in this app). |
| Server events | None new. `job_links` is a read and logs nothing (unchanged). |
| Validation | `JobPeekSheet` only opens for a positive integer id; anything else is a programming error → render nothing and `console.error`, no request. |
| Tenancy | Unchanged and server-enforced: 555/611 return 404 for another account's job. FT-EXC-2-06 proves it. |
| Delete behaviour | N/A — no new rows. |
| Reachability | Every new tappable thing (each chip, "Came from", the sheet's Close) hit-tested at 375 px — E2E-EXC-2-05. |

---

## 6. Test plan

IDs are final; record each in **Test Results** with pass/fail and evidence.

### Unit (`npm test` in `webapp/protype-2`)

| ID | What | Expect |
|---|---|---|
| UT-EXC-2-01 | `jobProgress` against every case in `job-progress-golden.json` | Exact match |
| UT-EXC-2-02 | finished = done + skipped; in_progress and blocked are unfinished | — |
| UT-EXC-2-03 | current stage = lowest-position unfinished stage; unknown stage sorts last; all finished → `""` | — |
| UT-EXC-2-04 | `progressLabel` for not started / part-way / blocked / done / zero steps (`"No steps"`) | Exact strings |
| UT-EXC-2-05 | The two new catalog entries pass UT-OBS-1-01/03; GUARD-REG-01 still green | — |

**Golden fixture cases (minimum):** 0 steps; 6 not started; 2 done + 1 skipped; blocked at
stage 3; all done; two owner rows at one stage with one done and one not (stage is unfinished);
a step whose stage is missing from the snapshot.

### Functional — live, on fixtures (HTTP over the planner group, or `runWorkspaceFunction` on `exceptions/job_links`)

| ID | What | Expect |
|---|---|---|
| FT-EXC-2-01 | Parent with a fresh child (send via 610 on a map-219 job → map 220) | `children[0].progress` = 0 of N, first stage |
| FT-EXC-2-02 | Complete 2 child steps via `POST work_task/{id}/event` (`started`, `completed`) | 2 of N, third stage |
| FT-EXC-2-03 | Block one child step | `has_blocked: true`, that stage current |
| FT-EXC-2-04 | Child's links → `parent.progress` uses the parent's map labels | Parent's stage label, not the child's |
| FT-EXC-2-05 | 555 vs 611 for the same parent | `children[*].progress` identical |
| FT-EXC-2-06 | 555 and 611 for a job id in **another account** | 404 "Job not found" (unchanged) |
| FT-EXC-2-07 | Server progress = `jobProgress` (TS) for the same live tasks | Identical (compare in the test script) |
| FT-EXC-2-08 | Job with 3 children: response time and query count sane | One `work_task` query for all children (read the function), < 1 s |

### UI (Playwright, `e2e/follow-sent-work.spec.ts`)

| ID | Viewport | What | Expect |
|---|---|---|---|
| E2E-EXC-2-01 | 375 px (perform) | Step chip → view → steps listed → Close | View shows child steps; back on the same step |
| E2E-EXC-2-02 | 375 px (perform) | A child job's step shows "Came from" → tap → parent view | Parent shown read-only |
| E2E-EXC-2-03 | desktop (planner) | "1 sent on" → child row expanded and in view | Child row `aria-expanded=true`, visible |
| E2E-EXC-2-04 | desktop (planner) | Exceptions chip shows "· 0 of N", after completing 2 child steps (API) → "· 2 of N" after reopening | Label updates |
| E2E-EXC-2-05 | 375 px | **Reachability**: every chip, "Came from", and the sheet's Close are hit-tested — `document.elementFromPoint(centre)` returns the element itself (or a descendant), 0 px clipped by any scroll container — with a long step list (≥ 12 steps) | All pass |
| E2E-EXC-2-06 | 375 px | Load failure (route the 555 request to 500) → E-EXC-014 message + Try again → succeeds on retry | Message, then the view |

### Existing suites (must stay green)

`npm test` (baseline 610/610 on 2026-10-27), `npx tsc --noEmit -p .`, `e2e/exceptions.spec.ts`
(3/3), `e2e/perform-sessions-mobile.spec.ts`, `e2e/jobs-and-day-navigation.spec.ts`,
`e2e/card-scheduling.spec.ts`.

### Fixtures

- Maps **219** (parent, exception link at `s2` → **220**) and **220** (published, Items row).
  Both are EXC-1 clones marked "safe to delete". Never 193, 178, 224.
- Create your own plan via `POST /workspace`, accept map 219 via `POST /workspace/{id}/map`,
  create jobs via `POST /work_item`, lines via `PUT /work-item/{id}/lines`, send via
  `POST /work-task/{id}/exception`. Recipes: `product/stories/phase-7/EPIC-EXC-1-exception-child-jobs.md`
  Test Results.
- Token for HTTP tests: CLAUDE.md, "A token minted by `security.create_auth_token` …" — use the
  magic-link route, never a password.
- Cleanup at the end (standing permission for your own fixtures): `POST /work_item/{id}/cancel`
  for every job you created, `POST /workspace/{id}/archive` `{"is_archived": true}` for every plan,
  delete scratch functions.

---

## 7. Decisions

| # | Decision | Why | Status |
|---|---|---|---|
| D-1 | The job view is **read-only**. | Doing another job's work belongs on its assignee's Today (who is assigned, what day, published or not). Mixing that into a peek would bypass the plan. | Proposed by design — settled unless the founder objects. |
| D-2 | **One** component for both modules. | The same job must look the same everywhere; EXC-1's "one list for both screens" rule (611) extended to the view. | Settled. |
| D-3 | **No new endpoint**: extend `job_links`, read 555. | 555 already hydrates steps from the pinned version with tenancy. A second "job summary" endpoint would be a second copy of that rule. | Settled. |
| D-4 | Finished = `done` or `skipped`; progress = finished ÷ all steps. | Matches the planner row's existing "X of N steps done" wording and LOG-1's terminal statuses. Re-check `JobsModal`'s `finished_count` source uses the same rule; if it doesn't, say so — don't silently pick one. | Settled. |
| D-5 | No new status, event type, table or column. | This is a read path. | Settled. |
| D-6 | Visibility = same account (existing tenancy). | Matches 555/611 today. Module access (USR-2 story 03) isn't enforced yet; when it is, 555/611 must stay readable by Execution-only users or this epic breaks. **Add that as a note to USR-2's "Still open" only if the founder agrees** (it's another epic's document). | Settled for now; flagged. |

## 8. Open questions — ask before building the story named

| # | Question | Recommendation | Ask before |
|---|---|---|---|
| **Q-1** | What may a performer see of a job that isn't theirs: stage names and statuses only, or also each step's task text and "done when"? | **Stage names, statuses, and task text + done-when (collapsed).** It's the same account's work and it's what tells them "is my item coming back". Do **not** show other people's notes/activity in this epic. | US-EXC-2-02 |
| **Q-2** | Should the Health page's Exceptions panel also show progress per open child? | Not in this epic. Offer it as a follow-up once the founder has used the view. | Completion |

---

## 9. Completion gate

- [ ] UT-EXC-2-01…05 green; FT-EXC-2-01…08 green on live fixtures; E2E-EXC-2-01…06 green.
- [ ] Existing suites green (numbers recorded against the §6 baseline).
- [ ] The founder's scenario reproduced on fixtures, end to end: send from a parent step → chip on
      the performer screen opens the child view (0 of N) → complete 2 child steps → chip and
      planner Exceptions chip both read 2 of N → child step shows "Came from".
- [ ] Every new tappable element hit-tested at 375 px.
- [ ] `job_links` live source = local file (diffed after the last push).
- [ ] Fixtures cancelled/archived; scratch functions deleted.
- [ ] Test Results below filled in, including anything skipped and why.
- [ ] Recommend the optional Opus review to the founder in one bullet.
- [ ] **Stop and report.** Do not start another epic.

---

## 10. Test Results

_Empty — fill in while building. One row per test ID: result, date, evidence (job ids, response
excerpts, screenshot path). Record failures and skips, not just passes._

| ID | Result | Evidence |
|---|---|---|
| Baseline (2026-10-27, before any change) | ✅ | `npm test` 610/610; `tsc --noEmit` 0 errors; live Xano (`exceptions/job_links` fn 260, endpoints 555/611) diffed against local `.xs` — no drift. EXC-1 committed first as `dbd942d` (a larger snapshot commit — the whole working tree had several uncommitted epics piled up, not just EXC-1; see commit message). |
| US-EXC-2-01 backend | ✅ built, pushed, smoke-tested | New function `exceptions/job_progress` (fn 267): one query per table (`work_item`, `journey_map_version`, `work_task`), no `[index]` access, no `conditional` reading a var updated earlier in the same iteration (two-pass unconditional merge instead — see file header). `exceptions/job_links` (fn 260) extended to call it once per request and attach `progress` to `parent` and each child via `|set`. Live source re-fetched and diffed against local `.xs` after push — matches. |
| FT-EXC-2-01…04 (shape) | ✅ via `runWorkspaceFunction` | **Real existing fixtures (read-only):** job 58 (parent, blocked) → `progress {task_count:8, finished_count:0, has_blocked:true, current_stage_key:"s1", current_stage_label:"Receive at the dock"}`; job 59's `parent` (job 58) carries the same shape; three sibling children on job 59 each carry their own `progress`. Confirms cross-job stage labels (child uses its own map's labels, parent uses its own) and multi-child aggregation in one call. **Constructed scratch fixtures (created + deleted in the same run, scratch fn 268, now deleted):** (a) two owner rows at one stage (one done, one not) + one skipped + one blocked-and-unknown-stage → `{task_count:4, finished_count:2, has_blocked:true, current_stage_key:"s1"}` — proves the unknown stage does **not** win "current" despite being blocked, and a partially-done stage stays current; (b) all 4 done/skipped → `{finished_count:4, current_stage_key:""}`; (c) 0 tasks → `{task_count:0, current_stage_key:""}`. All three match the golden-case list in §4/§6 exactly. |
| FT-EXC-2-05 | ✅ by code inspection, not live HTTP | `555` and `611` both do `function.run "exceptions/job_links"` and return `$links.children`/`$links.parent` unchanged (neither endpoint's own XanoScript was touched, per the epic's "not changed" list) — structurally identical by construction. **Not independently re-verified over real HTTP** — no test-account auth token was available this session (account 2 is the founder + a real teammate; CLAUDE.md's magic-link method mints a token for a specific user, and minting one for either real person wasn't done without asking). Flagged as a gap, not skipped silently. |
| FT-EXC-2-06 (tenancy) | ⏭ not re-run | Tenancy check in 555/611 is unchanged code; not considered at risk, but not independently re-confirmed this session. |
| FT-EXC-2-07/08 (TS-twin parity, query-count/perf) | ⏭ pending | Needs `jobProgress.ts` (US-EXC-2-02) and the shared golden fixture file, not yet written. |
| UT-EXC-2-01…05, E2E-EXC-2-* | ⏭ pending | US-EXC-2-02 through 05 not started. |
| Cleanup | ✅ | Scratch function `scratch/probe_job_progress` deleted from Xano and locally. No fixture job/map/plan of my own was left behind (I reused job 58/59 read-only; constructed test rows were created and deleted inside the same scratch-function run). |
| US-EXC-2-01 catalog codes (E-EXC-014/015) | ✅ pushed, tests green | Added to `functions/ops/error_catalog.xs` (fn 69) and `errorCatalog.json`, with GUARD-REG-01-style unit tests both sides. **Deviation:** spec said `owner: system` for E-EXC-014; the catalog's `owner` enum is `user\|product_manager\|engineer` (enforced by `UT-OBS-1-01`, which failed on first push) — built as `owner: engineer` instead, same reasoning as the existing E-OBS-001/E-GOV-001 "dropped connection/server error" entries. Noted in §5's table too. |
| US-EXC-2-02 frontend (jobProgress.ts twin + JobPeekSheet) | ✅ built, unit-tested | `exceptions/jobProgress.ts` (pure): `jobProgress(tasks, stageOrder)`, `progressLabel(p)`, plus `progressShortLabel(p)` (the "N of M" chip form, not in the original spec list but needed by US-03/04 and kept DRY in one place rather than duplicated per caller). `src/fixtures/job-progress-golden.json`: 9 cases — the 7 named in the epic plus 2 that reproduce the exact live scratch-function runs from US-EXC-2-01 byte-for-byte (`UT-EXC-2-golden-08/09`), giving real backend/frontend parity evidence without a live HTTP round trip. **Found and fixed before it shipped:** a naive port used a single `Infinity` sentinel for both "nothing unfinished yet" and "unknown stage" — collapsing them made a job with only unknown-stage unfinished steps register as falsely "all finished" (`Infinity < Infinity` is `false`). Fixed to match the backend's own two-sentinel pattern (999999 vs 999999999) exactly. `exceptions/JobPeekSheet.tsx` built per the spec (header, progress bar, "Came from", step list with collapsible task/done-when per Q-1, "Sent on" chips, fixed-footer Close, loading skeleton, E-EXC-014/015 error states via the existing `ErrorBanner`-adjacent catalog lookup, one failure/rejection `logEvent` per load attempt, no success event). **Not wired into StepScreen/ExceptionSendPanel/JobsModal yet** — that is US-EXC-2-03/04. No component-level unit test (this codebase doesn't RTL-test components; verification is e2e, per US-EXC-2-03/04/05). |
| `npm test` / `tsc` after US-EXC-2-01+02 | ✅ | 623/623 (610 baseline + 13 new in `jobProgress.test.ts`, added to `package.json`'s explicit test file list — it's not a glob); `tsc --noEmit` 0 errors. |
| US-EXC-2-03 (chips open the view; "Came from") | ✅ built | `ExceptionSendPanel.tsx`: each `exception-chip` is now a `<button>` (`data-testid` kept, `aria-label="Open sent job #N"`), label gains the progress short form (` · 2 of 6`), tap opens `JobPeekSheet`. Added `onLinksLoaded?(parent)` — called from the panel's own existing `getWorkItemLinks` fetch, so a caller's "Came from" chip costs **zero extra requests** (the thing §3/US-03 explicitly asked for). Added `onOpenJob?(id)` so a caller (US-EXC-2-04's planner) can take over what tapping a chip does instead of the panel opening its own sheet; when absent, the panel manages its own `JobPeekSheet` (`peekId` state) — this is how the performer path works today. `StepScreen.tsx`: new "Came from #N · <stage>" button right under the header (above the stage/task text), fed by `onLinksLoaded`, opens its own `JobPeekSheet` instance with `onOpenJob` wired for hopping between parent/children inside the same sheet. `SessionScreen.tsx`: same chip and sheet, but this screen has no existing fetch to reuse (`ExceptionSendPanel` isn't mounted there), so it makes its own single `getWorkItemLinks` call per session open — one new, justified request, not a duplicate of anything already happening on that screen; failure degrades quietly to "no chip" (not a blocking error — the session still works). |
| UT/`tsc` after US-EXC-2-03 | ✅ | `npm test` still 623/623 (no new pure logic to unit-test — this story is UI wiring only); `tsc --noEmit` 0 errors; `npm run build` (vite) succeeds. |
| E2E-EXC-2-03/04 (planner path) | ✅ written, ⏭ not run | `e2e/follow-sent-work.spec.ts` — reuses EXC-1's map 219→220 fixtures; sends from the planner, asserts the chip is a real hittable button with the "0 of N" progress label, opens `JobPeekSheet` showing the child's steps with a "Now" marker and no action buttons (read-only, D-1), hit-tests the sheet's footer Close, confirms closing returns to the planner unchanged. Compiles and skips cleanly with the rest of the suite (`npx playwright test` — 11/11 skipped, same as baseline) because no `E2E_AUTH_TOKEN` was available this session. |
| E2E-EXC-2-01/02 (performer path, 375 px: step/session "sent" and "Came from" chips) | ⏭ not covered | Same gap `exceptions.spec.ts` already flags for the send flow itself: the only two users in account 2 are real people, and `/perform` only shows an agent's own published day, so there is still no dedicated test login for the performer app. The code path is the same shared components either way (D-2), and is exercised structurally by the planner-path test above, but the actual 375 px performer screens were not driven end-to-end this session. |
