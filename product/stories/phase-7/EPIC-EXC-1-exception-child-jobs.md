# EXC-1 — Exceptions Become Child Jobs

**Epic ID:** EXC-1
**Feature:** While doing a step, a performer (or the planner) can say "this part of the job is leaving the happy path" — and the system starts a **child job** on the map that the parent map's exception link points to, pinned to that map's published version, tied back to the parent job and step, carrying the item counts that left. The parent keeps going.
**Status:** Built 2026-10-26 — waiting for the founder (see Test Results → Completion gate)
**Depends on:** phase-4 JOB-1 (jobs pinned to a version, `parent_work_item_id`), LOG-1 (status engine, `blocked` + reason), BLK-1 (one card per order per actor row); phase-6 EST-1 (`work_item_line`, `estimate_job`, slot refresh). Intelligence-layer links (`journey_link`, snapshot `links[]`) already exist.
**Model:** Sonnet to build; **Opus** writes US-EXC-1-03 (the spawn transaction) and does the review pass at the gate.
**MVP:** readiness `warn` for an unpublished or item-less linked map; `work_item_exception` table; one spawn endpoint (`POST planner/work-task/{id}/exception`) usable by a performer tap now and an AI/system caller later; `554` accepts an optional parent; 555/559 and the cards show the link both ways; StepScreen action sheet; job-detail action for the planner; Health **Exceptions** panel; TypeScript twin + golden fixtures for the line split. Deferred: re-merging items back into the parent, automatic spawn from `stage_automation_config`, sub-journey *steps* on a task (EXE-M-1), `flagged_quantity` (EXE-M-1).
**Goal:** On a clone of map 193 linked to a published repair map: flag 2 of 3 tables at Triage → a child job appears in the backlog with 2 tables, pinned to the repair map's latest version; the parent's Wash/Inventory estimates drop by exactly 2 × rate; the parent is **not** blocked; both jobs show the link; Health lists the open child. On a 178 clone (no items): the same action spawns a child with no lines and the parent continues. Nothing in `workflow_tests/1–32` changes result.

---

## Builder brief

> **New session? Read [START-HERE.md](START-HERE.md) before this file.** It carries the context this
> brief assumes: vocabulary, what the founder has already settled, the build order, and the limits.

- **Model: Sonnet, except US-03 which is Opus, and an Opus review pass at the gate.** Say so at the start, before US-03, and before the review.
- **Read first:** `static/tables/122_work_item.xs`, `123_work_task.xs`, `139_work_item_line.xs`, `14_journey_link.xs`, `127_activity_log.xs`; `apis/planner/554_work_item_POST.xs`, `555_…_GET.xs`, `557_…_cancel_POST.xs`, `559_…_backlog_work_GET.xs`, `563_work_task_…_event_POST.xs`, `567_perform_today_GET.xs`, `607_…_lines_PUT.xs` (the "Refresh scheduled, untweaked slots" section); `functions/jobs/tasks_from_version.xs`, `functions/log/next_status.xs`, `functions/pub/build_map_snapshot.xs` (the Links section), `functions/pub/evaluate_readiness.xs`; `webapp/protype-2/src/perform/StepScreen.tsx`, `planner/components/JobsModal.tsx`, `planner/plannerApi.ts`, `App.tsx` around `cellLinkType`.
- **Live ids / state:** workspace 1. Map 193 clone as the parent; create a small published "repair" map in the same `journey_architecture` (31) as the linked map; 178 clone for the no-items path. Confirm `planner_workspace_map` rows for the test plan before testing E-JOB-002 behaviour.
- **CLAUDE.md rules that bite here:** `function.run` (`tasks_from_version`, `estimate_job`, `log_event`) stays **outside** `db.transaction` — compute everything first, write in one block. `db.patch` on a `json` column **merges**: the child's `attributes` is written once on `db.add` (safe); if you ever rewrite `moved_lines`, use the null-then-value two-step. `0 == null`, `[] == null`, `false == null`: test `parent_work_item_id != 0`, test counts with `!= 0`, use `|has` for map lookups. `|get` with a variable key ignores its default — seed or null-check. Array membership by loop, never `|contains`. `where … not in $ids` with a `[-1]` seed. Only branch on the loop item, an input, or a var set before the loop. `where` cannot call filters. Optional `int`/`bool` inputs arrive as `0`/`false` — `also_block_parent` must be read via `util.get_raw_input|has`.
- **One implementation, one place:** job creation (`554`) and the spawn must call the same `jobs/create_job` function; slot refresh (`607`) and the spawn must call the same `estimate/refresh_job_slots` function. Extract first, then re-verify 554 and 607 still pass FT-JOB/FT-EST before writing the new caller. No copied blocks.
- **Do not open:** the catalog UI, the Items cell editor, publish/hash code (`canonical_hash`, `verify_version`), the status transition table (`next_status`). This epic adds no status and no event type.
- **Session:** one epic per session. Read only this epic, `README.md` (phase-7), PRD §7.4 (EX-5, EX-7) and §9, and `CLAUDE.md`. Do not open other epics except the specific files named above.
- **Order of work (CLAUDE.md build protocol):** tests first, then code; run the new tests and the existing suites; record results in Test Results; stop and wait for the founder at the completion gate.
- **Ask before:** any change to an existing table (there should be none), any delete, anything on the original 193/178. Table 140 is **already approved** (founder, 2026-10-26) — create it, then record the id Xano assigns.
- **Report back:** what was built (1–2 sentences), tests pass/fail by ID, differences from the epic, what is next.

---

## Context

PRD §2 (Definition → Commitment → Record), §7.4 EX-5 (built) and EX-7 ("Exceptions can start a linked sub-journey or exception journey", P1, **not built**), §9 ("Exception: blocked status plus reason code → exception frequency by stage and reason").

The design conversation (2026-10-25) settled the shape:

- The happy path is **planned**. A deviation is **discovered while executing**. So the recovery work is spawned at that moment, from that step, as a **child job** — never pre-planned, never a sub-task.
- The parent **does not wait**. The founder's own Exception Lane stage says "items leave the main flow here and do not rejoin it." 97 good chairs must not wait on 3 damaged tables. If a performer genuinely needs the parent step to stop, that is the existing `blocked` + reason, chosen explicitly.
- "Does it come back?" — **depends on the item**, and that is the linked map's business: its last stage decides (back to stock / retire / charge / return). Re-merging into the *same parent order* is deferred.
- A method's **sub-journey** (how-to steps for a stage) and an **exception link** (work leaves) are two different things that happened to share a word. This epic acts on `exception` links only.
- Generic. The example was a torn rental item going to a vendor; the feature is "work leaves this journey here, on this map, for this reason" for any work type.

Already true, verified live 2026-10-25: `journey_link` supports `exception | anti_journey | sub_journey`; the cell link picker exists in the map UI; `build_map_snapshot` writes `links[] {stage_key, lens_key, link_type, target_map_id}`; `work_item.parent_work_item_id` exists and `554` writes `0`; ISSUES-BACKLOG #19 and BLK-1 "Still open" both name child jobs as the next epic.

## Existing Architecture (Do Not Break)

- **Reference, do not copy.** A child job is a normal `work_item` pinned to the linked map's version. It gets one `work_task` per cell from `tasks_from_version`, exactly like any job. No copied text, no "task library".
- **Statuses are fixed** (`not_started | in_progress | blocked | done | skipped`) and **event types are fixed** (`activity_log.event_type`). This epic adds neither. The spawn is recorded in its own table plus a `note` event on the parent task and OBS-1 `event_log` rows. Optional blocking of the parent goes through LOG-1's engine (`563`'s logic), never a direct status write.
- **Three durations, three owners.** Expected = `estimate_job`; scheduled = planner tweak; actual = log. Moving counts changes *expected* on the parent's **untweaked** slots only (EST-1 D-1); tweaked slots keep their number and raise `estimate_changed_under_tweak`.
- **Two variances, never mixed** (BLK-1). The child's actuals never roll into the parent's stage variance. `task_report` is untouched.
- **Cancel, never delete** (JOB-1). Cancelling a parent does not cancel children; `work_item_exception` is append-only.
- **`estimate_job` is the only formula.** The split touches lines; it never computes minutes.
- **Snapshot and hash untouched.** `links[]` already exists in schema v1 and v2; this epic reads it, never changes `canonical_hash`.
- **Job generation untouched.** Lines never create tasks; a child with zero lines is a perfectly normal job.

## Non-Goals

- No re-merge of items into the parent order; no "return to parent" button.
- No automatic spawn from `stage_automation_config.exception_condition` (hook noted, endpoint ready; wired with the AI run path later).
- No display of a method's sub-journey **steps** on a task (EXE-M-1); no `flagged_quantity` writes (EXE-M-1).
- No new status, no new `event_type`, no change to `next_status`.
- No cross-account or cross-workspace spawn: the child lands in the parent's workspace, same account.
- No change to `canonical_hash` / `verify_version`.

---

## Stories

### US-EXC-1-01 — Intelligence layer: the exception link means something, and readiness says when it won't work

**Files:** `functions/pub/evaluate_readiness.xs` (additive), `webapp/protype-2/src/readiness.ts` + test (twin), `App.tsx` (link picker helper text, stage-header chip — additive), `e2e/exceptions.spec.ts` (first case)

**As a** map author, **I want** to see which stages can hand work off to another map, and be warned before publishing if that handoff cannot actually happen, **so that** the first real exception is not the moment I discover the repair map was never published.

- The link picker's three options get one plain line each. `Exception`: "Work leaves this journey here and continues on the linked map. Performers can send part of a job there." `Sub-Journey`: "How this stage is done, in more detail. Shown as steps; never starts a separate job." `Anti-Journey`: unchanged wording from today.
- A stage whose cells carry at least one `exception` link shows a small chip in the stage header ("⚠ exception → *Repair*"), read from the live links, so the author sees the handoff without opening the cell.
- **Readiness** (never a block, always `warn`):
  - `exception_map_unpublished` — an `exception` link's target map has no `journey_map_version`. Message names the stage and the target map: "Triage sends work to *Repair*, which has never been published. Performers won't be able to send work there until it is."
  - `exception_map_has_no_items_row` — only when **this** map has an Items row and the target does not: "Items sent from Triage to *Repair* won't have an estimate there — *Repair* has no Items row."
  - `exception_map_other_architecture` — target not in the same `journey_architecture`: "Triage links to a map in a different architecture; keep exception maps in the same architecture."
- The TypeScript readiness twin mirrors the three warnings; a golden case for each.
- **Gherkin**
  - *Given* a cell at Triage with an `exception` link to a map with no versions, *when* readiness runs, *then* `warnings[]` contains `exception_map_unpublished` with `stage_key = s2` and the target title, and `ready` is unchanged.
  - *Given* the target is published, *when* readiness runs, *then* no exception warning.
  - *Given* a `sub_journey` link only, *when* readiness runs, *then* no exception warning (the how-to link is not a handoff).

### US-EXC-1-02 — `work_item_exception` table

**Files:** `static/tables/140_work_item_exception.xs` (Xano assigns the id; record it)

| Column | Type | Rule |
|---|---|---|
| `account_id` | ref `account` | required (tenancy, GOV-1 S4) |
| `parent_work_item_id` | ref `work_item` | required |
| `parent_work_task_id` | ref `work_task` | required — the step the exception was raised on |
| `child_work_item_id` | ref `work_item` | required, **unique** — one record per child |
| `stage_key`, `lens_key` | text | copied from the parent task at spawn time; survive later map edits |
| `link_type` | enum `exception` | MVP accepts only `exception`; enum kept so `sub_journey`/`anti_journey` can be allowed later without a schema change |
| `target_map_id` | ref `journey_map` | the linked map |
| `target_version_id` | ref `journey_map_version` | the version the child was pinned to |
| `reason_code` | enum, same four values as `activity_log.reason_code` | required (EX-5's one list — no second vocabulary) |
| `note` | text, trim | 0–500 chars, no HTML |
| `moved_lines` | json | `[{item_type_id, item_key, quantity}]`; `[]` for a whole-job exception |
| `parent_blocked` | bool | whether the performer also blocked the parent step |
| `source` | enum `manual | ai | system` | default `manual` (PRD EX-9 hook) |
| `created_by` | ref `user` | 0 for ai/system |

Indexes: primary; unique `(child_work_item_id)`; btree `(parent_work_item_id)`, `(parent_work_task_id)`, `(account_id, created_at desc)`, `(target_map_id)`.

Delete: **never**. Append-only history, same stance as `activity_log`. Both jobs are cancel-never-delete already; this row is what lets Health say "this child's parent was cancelled."

### US-EXC-1-03 — The spawn endpoint (**Opus**)

**Files:** `apis/planner/…_work_task_work_task_id_exception_POST.xs`, `functions/jobs/create_job.xs` (extracted from `554`), `functions/estimate/refresh_job_slots.xs` (extracted from `607`), `functions/exceptions/split_lines.xs`, `workflow_tests/33_exceptions.xs`

**As a** performer on a step (or a planner on a job), **I want** one action — "send this to *Repair*" — with a reason and, when the job has items, which ones and how many, **so that** the exception is tracked as its own job instead of being absorbed, deferred, or scribbled in a note.

`POST planner/work-task/{work_task_id}/exception`

Input: `target_map_id` (int), `reason_code` (text, one of the four), `note?` (text), `lines?` (json `[{item_type_id, quantity}]`), `also_block_parent?` (bool — read via raw input), `source?` (text, default `manual`), `correlation_id?`.

Order of work (every check before any write; every `function.run` before the transaction):

1. `resolve_actor`; task exists, job is the caller's account, job not `cancelled`/`completed` (`E-EXC-001`). Workspace not archived (existing guard).
2. The parent job's **pinned snapshot** has a `links[]` entry with `stage_key == task.stage_key`, `link_type == "exception"`, `target_map_id == input.target_map_id` (`E-EXC-002`). Any lens on that stage counts — the Items row or a description cell may carry the link. The live `journey_link` table is **not** consulted: the job runs on its pinned version.
3. Target map is the same account (`E-EXC-002`) and has a published version; pick the **latest** (`E-EXC-003`). Record it as `target_version_id`.
4. Plan acceptance: a map reached through an exception link from an accepted map is **implicitly accepted** for the child (D-3). `E-JOB-002` is not raised here. (If `559`/`558` filter by `planner_workspace_map`, add the child's map to that table inside the transaction instead — verify at build; FT-EXC-1-10 pins whichever is true.)
5. Lines (only when provided and non-empty): parent map has an Items row (`E-EXC-004`); every `item_type_id` is on a parent line (`E-EXC-005`); `1 ≤ quantity ≤ parent line quantity` and integer (`E-EXC-006`); no duplicate item (`E-EXC-007`). `split_lines(parent_lines, moved)` → `{parent_after[], child_lines[], removed_item_ids[]}` — pure, mirrored in TypeScript (US-08). A line moved in full is **removed** from the parent (EST-1 forbids quantity 0). `flagged_quantity` is untouched (that is EXE-M-1's number, meaning "handled in-house").
6. The target map must have an Items row if `child_lines` is non-empty (`E-EXC-008`) — otherwise the child cannot hold them.
7. Compute the child's title: `"<parent title> · <link label or target map title>"`, truncated to 120; when lines moved, append ` (<n> <item label>)` for one item or ` (<n> items)` for several. The caller may override with `title?`.
8. `tasks_from_version(target snapshot)` → the child's task list (outside the transaction).
9. **`db.transaction`:** `create_job` core writes (child `work_item` with `parent_work_item_id = parent.id`, `attributes` = parent's with each entry's `source` set to `"parent #<id>"`, `status = open`); child `work_task` rows; child `work_item_line` rows; parent `work_item_line` patches/deletes by **id** (loop, never field-match); `work_item_exception` row. If `also_block_parent`: nothing here — see step 11.
10. Outside: `refresh_job_slots(parent)` (EST-1 D-1 — untweaked slots take the new estimate, tweaked ones raise `estimate_changed_under_tweak`); `estimate_job(child)` once so its cards are right from the first read.
11. If `also_block_parent`: call the same function `563` uses to record `blocked` with `reason_code` and `note = "Sent <n> to <child title> (#<child id>)"`. Refused transitions (e.g., parent step already `done`) do **not** fail the spawn — they log `rejected` with the engine's message and the response says `parent_blocked = false`.
12. Always: a `note` event on the parent task (`source` = input source) reading "Sent to *Repair* → job #<child id> (<n> items). Reason: <reason>." — so the parent's activity feed shows the fork without a new event type.
13. OBS-1 events (`feature = EXC-1`): `exception_raised` `success` with child id, target version, moved count; or `rejected`/`failed` with the code.

Response: `{child: {work_item_id, title, journey_map_version_id, status}, parent: {work_item_id, lines_after[], estimate}, exception_id, parent_blocked}`.

**Gherkin**
- *Given* job #482 (3 tables, 100 chairs) on a 193 clone whose Triage has an `exception` link to *Repair* (published), *when* the performer posts `lines: [{table, 2}]`, reason `something_went_wrong`, *then* a child job exists with `parent_work_item_id = 482`, one line `table × 2`, tasks for every *Repair* cell, pinned to *Repair*'s latest version; the parent's table line is `1`; the parent's untweaked Wash/Inventory slots dropped by `2 × rate`; a `work_item_exception` row exists; the parent task's status is **unchanged**.
- *Given* the same, *when* `lines: [{table, 3}]`, *then* the parent has no table line at all and the child has `table × 3`.
- *Given* a 178 clone (no Items row), *when* the performer posts with no `lines`, *then* a child with zero lines is created and the parent continues.
- *Given* `also_block_parent = true` on an `in_progress` step, *then* the parent step is `blocked` with the reason, through LOG-1's engine, and the response says so.
- *Given* the target map has no published version, *then* `E-EXC-003`, nothing written, `rejected` event.
- *Given* `quantity` greater than the parent line, *then* `E-EXC-006`, nothing written.
- *Given* the step's stage has no `exception` link in the **pinned** snapshot (even if the live map now has one), *then* `E-EXC-002`.

### US-EXC-1-04 — `554` accepts a parent; one `create_job`

**Files:** `apis/planner/554_work_item_POST.xs`, `functions/jobs/create_job.xs`

- Extract 554's write path into `jobs/create_job` (inputs: actor, workspace, version, title, attributes, `parent_work_item_id`, `created_by`). 554 and US-03 both call it. FT-JOB-1-* must pass unchanged before US-03 is written.
- 554 gains optional `parent_work_item_id?` (int). When non-zero: parent exists, same account **and** same workspace (`E-EXC-009`), not `cancelled` (`E-EXC-001`). No lines move and no `work_item_exception` row is written — this is the planner saying "this job belongs under that one" (a manual child), not an exception. The job-detail UI exposes it as "Add a related job under this one" only if there is time; otherwise API-only in MVP.

### US-EXC-1-05 — Planning: the link is visible both ways

**Files:** `apis/planner/555_work_item_work_item_id_GET.xs`, `558_…_work_item_GET.xs`, `559_…_backlog_work_GET.xs` (additive fields), `webapp/protype-2/src/planner/components/JobsModal.tsx`, the card components, `plannerApi.ts`

**As a** planner, **I want** to see on a job that part of it went elsewhere, and on a child where it came from, **so that** nothing looks like it vanished and nothing looks like it appeared from nowhere.

- `555` adds `parent: {work_item_id, title, stage_key, stage_label, reason_code, moved_lines, created_at} | null` and `children: [{work_item_id, title, status, target_map_title, moved_lines, created_at}]`, read from `work_item_exception` (+ `parent_work_item_id` for manual children with no exception row).
- `558`/`559` rows and cards add `parent_work_item_id` and `child_count`. Card chips: parent — "2 → *Repair* #491"; child — "from #482 · Triage". Clicking opens the other job's detail.
- Job detail gains an **Exceptions** section listing children (and the parent, when it is one) with reason and note — and a **Send to…** button offering the same action as the performer's (US-06), for the planner who is told about the problem by phone.
- A child job is in the **backlog, unscheduled** on creation. The planner schedules it like any card (`583`). Nothing else in scheduling changes.
- `557` (cancel) is unchanged; the Health panel (US-07) surfaces open children of a cancelled parent.

### US-EXC-1-06 — Execution: the action on the step

**Files:** `webapp/protype-2/src/perform/StepScreen.tsx`, `perform/performApi.ts`, `perform/exceptionSheet.ts` + test (pure helpers), `apis/planner/567_perform_today_GET.xs` (additive: the step's `exception_links[]` and the job's lines), `e2e/exceptions.spec.ts`

**As a** performer, **I want** a one-tap way to say "this part is leaving the happy path," pick why, and say which items, **so that** I never have to choose between pretending it is fine and stopping everything.

- A step shows **Send to…** only when `exception_links[]` (from the pinned snapshot, stage-matched) is non-empty. One link → the button names it ("Send to *Repair*"); several → a picker.
- The sheet: reason (the same four EX-5 buttons already used for Blocked); optional note; when the job has lines, each line with a stepper `0…quantity` (default 0; "all" shortcut); a toggle "This step is stuck until it's resolved" (off by default — the parent continues); Send.
- On success: a toast "Sent 2 tables to *Repair* (#491)", the step's line list shows the remaining counts, and a chip "2 → #491" stays on the step. On rejection: the message, the sheet stays open with everything typed (CLAUDE.md UI rule).
- **Mobile first** (`perform-sessions-mobile.spec.ts` conventions): 44px targets, works at 375px.
- `567` adds, per step, `exception_links: [{target_map_id, target_map_title, link_label, published: bool}]` and, per job, `lines: [{item_type_id, label, unit, quantity}]` (reuse `608`'s shape). An unpublished target is shown disabled with "not published yet" — the server still rejects if tried.
- **Gherkin**
  - *Given* a step at Triage on a job with 3 tables, *when* I tap Send to *Repair*, choose "something went wrong", set tables to 2, Send, *then* I see the toast and the step shows "1 table" remaining and the chip.
  - *Given* a step with no exception link, *then* no Send to… button.
  - *Given* I set 5 tables on a line of 3, *then* the stepper will not go past 3; *given* the server rejects anyway, *then* my reason, note and counts are still there.

### US-EXC-1-07 — Health page: Exceptions panel

**Files:** `webapp/protype-2/src/health/*` (additive), `functions/ops/exceptions_panel.xs`

- Open children (status not `completed`/`cancelled`): parent title, step, reason, target map, age in days, moved counts. Sorted oldest first.
- Counts for the last 30 days by stage and by reason (PRD §9: "exception frequency by stage and reason").
- **Needs attention:** children whose parent is `cancelled`; exception links whose target is unpublished (from the latest readiness run of each active map); spawn rejections in the last 7 days with their codes.
- Plain language throughout: "Order #482 sent 2 tables to *Repair* (#491) at Triage, 6 days ago — still open."

### US-EXC-1-08 — TypeScript twin and golden fixtures

**Files:** `webapp/protype-2/src/exceptions/splitLines.ts` + `.test.ts`, `exceptions/exceptionLinks.ts` + `.test.ts`, `src/fixtures/exception-split-golden.json`

- `splitLines(parentLines, moved)` → `{parentAfter, childLines, removed}` or a typed rejection (`E-EXC-005/006/007`). Same rules as `functions/exceptions/split_lines.xs`; FT-EXC-1-01 runs the backend over the same fixtures.
- `exceptionLinksForStage(snapshot, stageKey)` → the `links[]` entries with `link_type === 'exception'` for that stage, any lens, de-duplicated by target. Used by `567`'s twin and the StepScreen.
- `childTitle(parentTitle, linkLabel, targetTitle, moved, labels)` — the one place the title rule lives on the frontend; backend mirrors it.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-EXC-1-01 | Unit | `splitLines`: 3 tables, move 2 | parent `1`, child `2`, `removed = []` |
| UT-EXC-1-02 | Unit | move 3 of 3 | parent line removed, child `3`, `removed = [table]` |
| UT-EXC-1-03 | Unit | move 4 of 3 / 0 / 2.5 / duplicate item / unknown item | `E-EXC-006` / `E-EXC-006` / `E-EXC-006` / `E-EXC-007` / `E-EXC-005` |
| UT-EXC-1-04 | Unit | two items moved, one in full | one removed, one reduced, child has both |
| UT-EXC-1-05 | Unit | `exceptionLinksForStage`: links on two lenses of one stage, one `sub_journey`, one duplicate target | only `exception` links, one per target |
| UT-EXC-1-06 | Unit | `childTitle` over 120 chars, one item, several items, no items | truncated; " (2 tables)"; " (5 items)"; no suffix |
| UT-EXC-1-07 | Unit | readiness twin: unpublished / no items row / other architecture / sub-journey only | three warnings / none |
| FT-EXC-1-01 | Functional (`workflow_tests/33_exceptions.xs`) | Backend `split_lines` over every golden fixture | Equals the frontend |
| FT-EXC-1-02 | Functional | Spawn with 2 of 3 tables | Child pinned to latest target version, 1 line × 2, tasks = target cells; parent line 1; parent task status unchanged; exception row; `success` event |
| FT-EXC-1-03 | Functional | Spawn with 3 of 3 | Parent line gone; child × 3 |
| FT-EXC-1-04 | Functional | Spawn on a 178 clone, no lines | Child with zero lines; parent untouched |
| FT-EXC-1-05 | Functional | Target unpublished / not linked in pinned snapshot / linked only on the live map | `E-EXC-003` / `E-EXC-002` / `E-EXC-002`; nothing written |
| FT-EXC-1-06 | Functional | `also_block_parent` on `in_progress` / on `done` | `blocked` + reason via engine / spawn succeeds, `parent_blocked = false`, `rejected` logged |
| FT-EXC-1-07 | Functional | Parent has a tweaked Wash slot and an untweaked Inventory slot; spawn 2 tables | Inventory drops by `2 × rate`; Wash unchanged + `estimate_changed_under_tweak` |
| FT-EXC-1-08 | Functional | Target map has no Items row, lines provided | `E-EXC-008` |
| FT-EXC-1-09 | Functional | Parent `completed` / `cancelled` | `E-EXC-001` |
| FT-EXC-1-10 | Functional | Child visible in `558`/`559` for the workspace | Appears, unscheduled, with `parent_work_item_id`; parent shows `child_count = 1` |
| FT-EXC-1-11 | Functional | `555` on parent and on child | `children[]` / `parent` populated as specified |
| FT-EXC-1-12 | Functional | VAR-1 `task_report` on parent after spawn | Expected = new estimate; child's actuals absent from the parent |
| FT-EXC-1-13 | Functional | `554` with `parent_work_item_id` same workspace / other workspace / cancelled | Created with parent / `E-EXC-009` / `E-EXC-001` |
| FT-EXC-1-14 | Functional | Child spawns its own child | Allowed; Health shows depth 2 |
| FT-EXC-1-15 | Functional | `554` and `607` after extraction, before US-03 | FT-JOB-1-* and FT-EST-1-* unchanged |
| FT-EXC-1-16 | Functional | Readiness on parent with unpublished target | `exception_map_unpublished` warn; `ready` unchanged |
| E2E-EXC-1-01 | UI (map) | Add an exception link; readiness shows the warning; publish the target; warning gone | As described |
| E2E-EXC-1-02 | UI (perform, 375px) | Send 2 tables to *Repair*; toast; remaining count; chip | As described |
| E2E-EXC-1-03 | UI (perform) | Server rejection | Message; reason, note, counts kept |
| E2E-EXC-1-04 | UI (planner) | Parent card chip → child detail → "from" chip → back | Both directions navigate |
| E2E-EXC-1-05 | UI (health) | Exceptions panel lists the open child with age and reason | As described |
| E2E-EXC-1-06 | UI (perform, 375px) | **Reachability**: with the sheet open and every field filled, the confirm button is hit-tested, not just clicked | Its own centre returns the button itself; 0 px clipped by any scroll box |

> ### A UI test that only clicks proves nothing (learned the hard way, 2026-10-25)
>
> ITEM-1's Items cell editor shipped with a Save button that no person
> could press: it sat 19 of its 32 pixels below the fold of the panel's
> scroll box, and a click on its own centre landed on the "Link to map"
> label painted underneath. Its e2e test passed the whole time, because
> Playwright's `.click()` scrolls the element into view first and then
> dispatches at it directly — it reproduces nothing a person does. The
> feature looked tested and was unusable, and the founder found it, not
> the suite.
>
> **The rule for every button this epic adds** — the perform sheet's
> confirm, "Send to…", the planner's action, the Health panel's links:
> at least one test must assert the button is genuinely hittable in the
> state that matters (sheet open, list long, all fields filled), not
> merely clickable by the driver. The shape that catches it:
>
> ```ts
> const r = button.getBoundingClientRect();
> const atCentre = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
> // must be the button itself, and nothing may clip it
> expect(button === atCentre || button.contains(atCentre)).toBe(true);
> ```
>
> Prefer a sticky or fixed footer for any action button that sits below
> content of unbounded length (a line per item, a list of children) —
> that is what the ITEM-1 fix did, and it removes the failure mode
> rather than testing for it.

**Completion gate:** all pass; `npm test`, `workflow_tests/1–32` and `33`, existing e2e green; **E2E-EXC-1-06 proves every new action button is reachable by a person**; FT-EXC-1-15 proves the two extractions changed nothing; the phase-4 end-to-end rehearsal (E2E-1) re-run on the 193 clone **with** a spawn mid-way and on the 178 clone; **Opus review** → Test Results.

## Governance (data integrity, validation, observability)

**Data integrity:** `work_item_exception.child_work_item_id` unique; append-only; child `work_item.parent_work_item_id` set once at creation and never changed; all spawn writes in one `db.transaction` with every read and `function.run` before it; line patches/deletes by `id` in a loop; the spawn is the **only** writer allowed to change `work_item_line` after work has started, and every such change has a `work_item_exception` row and a `success` event naming it; schema audit (GOV-1) covers 140.

**Validation and friendly messages**

| Field | Rule | Friendly message | Code |
|---|---|---|---|
| job | open or in progress | "This job is finished (or cancelled), so nothing can be sent from it." | `E-EXC-001` |
| target | an `exception` link for this step's stage in the job's pinned version; same account | "This step doesn't send work to that map. Add an exception link on the map and publish a new version — new jobs will have it." | `E-EXC-002` |
| target | has a published version | "*Repair* hasn't been published yet. Publish it, then try again." | `E-EXC-003` |
| lines | parent map has an Items row | "This work type doesn't track items, so you can't pick which ones to send. Send the whole step instead." | `E-EXC-004` |
| lines | item is on the parent order | "That item isn't on this order." | `E-EXC-005` |
| lines | 1 ≤ integer ≤ line quantity | "Enter how many to send, from 1 to <n>." | `E-EXC-006` |
| lines | no duplicate item | "That item is listed twice — combine them." | `E-EXC-007` |
| target | has an Items row when lines are sent | "*Repair* doesn't track items, so the counts can't go with the work. Add an Items row to *Repair* and publish, or send without counts." | `E-EXC-008` |
| parent (554) | same workspace, exists | "That parent job is in a different plan." | `E-EXC-009` |
| reason | one of the four | "Pick a reason." | `E-EXC-010` |
| note | ≤ 500 chars, no HTML | "Keep the note under 500 characters." | `E-EXC-011` |

**Events logged** (`feature = EXC-1`): `exception_raised` (`success` with child id, target version, moved count, `parent_blocked` / `rejected` with code / `failed`); `child_job_created` (`success`, from `create_job` when `parent_work_item_id != 0`); `lines_moved` (`success`, parent id, child id, `moved_lines`); `exception_map_unpublished` (`warn`, from readiness); `parent_cancelled_child_open` (`warn`, from GOV-1's daily audit or the Health query). EST-1's `estimate_changed_under_tweak` fires as today.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-EXC-1-G01 | Unit | Junk corpus (HTML, 501 chars, negative, decimals, strings) through reason/note/lines validation | All rejected with the right codes |
| FT-EXC-1-G01 | Functional | Rejected spawn | 422 + message + Reference + `rejected` event; parent lines, tasks and status unchanged; no child |
| FT-EXC-1-G02 | Functional | Force a failure after the child row inside the transaction (scratch) | Nothing persisted; `failed` event |
| FT-EXC-1-G03 | Functional | Schema audit on 140 | Pass |
| FT-EXC-1-G04 | Functional | Cancel the parent after a spawn | Child untouched; Health "needs attention" lists it |
| FT-EXC-1-G05 | Functional | Attempt to delete a `work_item_exception` row via any endpoint | No endpoint exists; documented |

## Decisions (settled)

**The founder confirmed D-1, D-3, D-7 and D-11 on 2026-10-26, including approval to create table 140.**
Every row below is now a decision, not a proposal. Do not re-open one to save effort mid-build: if a
decision turns out to be wrong, stop, say which one and why, and wait.

| # | Question | Decision |
|---|---|---|
| D-1 | Does the parent step stop when work is sent away? | **No — the parent continues.** Matches the founder's Exception Lane ("items leave and do not rejoin"). Blocking is an explicit toggle that goes through LOG-1 with a reason. **(confirmed by the founder, 2026-10-26)** |
| D-2 | Which version does the child pin to? | **The target map's latest published version at spawn time.** Improvements to the repair process reach the next exception without republishing the parent. Recorded in `target_version_id`. |
| D-3 | Must the target map be in the plan's accepted maps (`planner_workspace_map`)? | **No — implicitly accepted through the link.** The planner accepted the parent map, and the parent map declares where its exceptions go. If list endpoints filter on acceptance, insert the row in the same transaction rather than refusing. **(confirmed by the founder, 2026-10-26)** |
| D-4 | What happens to a line moved in full? | **Removed from the parent.** EST-1 forbids quantity 0, and "0 tables" on an order is noise. The exception row keeps the history. |
| D-5 | Do moved counts also count as "flagged"? | **No.** `flagged_quantity` (EXE-M-1) means "handled in-house at a `per_flagged_unit` stage". Moved means "left". Two numbers, two meanings. |
| D-6 | Which links can spawn? | **`exception` only in MVP.** `sub_journey` is a method's how-to (EXE-M-1). The enum on 140 leaves the door open. |
| D-7 | Cancelling the parent — cancel children? | **No.** Children are real work someone may be doing. Health flags them; a person decides. **(confirmed by the founder, 2026-10-26)** |
| D-8 | Child's title and attributes | **Auto title "<parent> · <link label>" (+ counts); attributes copied with `source = "parent #id"`.** Overridable title on the API. |
| D-9 | Who may spawn? | **Anyone who can record events on the step (performer) or open the job in the planner.** Same guards as `563`/`555`. |
| D-10 | Where the exception happened, when the link sits on a different lens of the same stage? | **Stage-matched, any lens.** The Items row or the description cell may hold the link; the performer's step is on the actor row. |
| D-11 | Record in `work_item.attributes` or a new table? | **New table (140).** Attributes is flat key/value by JOB-1's rules; this is a relationship with history and reporting needs. **(confirmed by the founder, 2026-10-26)** |
| D-12 | Should the AI run path auto-spawn now via `stage_automation_config.exception_condition`? | **Not now.** The endpoint takes `source = ai|system` so it can, when D-39's deferred AI path is picked up. |

---

## Test Results

*Build started 2026-10-26 (Opus 5.5, founder away — "make the best call"). Filled in as each step lands; a step not listed here has not been done yet.*

### Progress log

| Step | State | Evidence |
|---|---|---|
| Table 140 `work_item_exception` | ✅ created, **Xano assigned id 140** | `static/tables/140_work_item_exception.xs`; `trim` validators survived `addTable` (only `updateTableSchema` drops them) |
| Probe: does `function.run` inside `db.transaction` roll back? | ✅ **yes** | Scratch pair: inner function's `db.add` + outer `db.add`, then a failing precondition → table stayed empty and the two ids were consumed (rows came back as 3, 4 on the success run). Success run committed both. Scratch functions and probe rows deleted. This is what lets `create_job` run *inside* the spawn's transaction. |
| Extract `jobs/create_job` (fn 241) from `554` | ✅ pushed; 554 now calls it inside its own `db.transaction` | FT-EXC-1-15 below |
| Extract `estimate/refresh_job_slots` (fn 242) from `607` | ✅ pushed; 607 now calls it | FT-EXC-1-15 below |
| **FT-EXC-1-15** | ✅ **pass** | **607:** `PUT` job 43 lines (6 × item 13) before the swap and after it → the whole response JSON is byte-identical (`refreshed_count 1`, `total_minutes 757`) and slot 96 refreshed to 96 min both times; job 43 put back to its original 4 (slot back to 87); E-EST-001 on 2.5 still rejected. **554:** job 53 (before) vs job 54 (after) on map 219 → `work_item` identical except id/time/title, same 8 tasks in the same order, same pinned version 22; 8 `work_task` rows really written for job 54; job 55 with no `attributes` stores `{}`, `parent_work_item_id 0`; E-JOB-002 still raised for an unaccepted map. |
| Extract `log/record_task_event` (fn 251) from `563` | ✅ pushed; 563 is now a thin wrapper | Not in the epic — needed because 563 had no function for the spawn to call (see Deviations). Replayed a 14-outcome sequence (start, duplicate, missing/bad reason, block, empty/long note, illegal moves, skip, complete-from-not-started) on job 53 before and job 54 after: every HTTP code, message and body identical except the job-specific `first_task_id`. |
| US-EXC-1-08 TS twin (`splitLines`, `exceptionLinksForStage`, `childTitle`) | ✅ | 20 unit tests green; golden file `src/fixtures/exception-split-golden.json` |
| `exceptions/split_lines` (fn 246) | ✅ | FT-EXC-1-01: all 11 golden cases identical to the TypeScript; junk corpus (null/"two"/"2"/{}/[]/-0.5/1e9 quantities; null/"table"/"11"/11.5/0 ids) all refused with the right code, no crash (first version crashed "Not numeric." — fixed by JSON-encoding before matching digits) |
| US-EXC-1-01 backend: `exceptions/exception_targets` (fn 248), `evaluate_readiness` + `evaluate_gate` (additive input), 520 | ✅ | FT-EXC-1-16: 7 golden cases word-for-word equal to `readiness.ts::exceptionLinkWarnings`; `ready` never changes; omitting the input changes nothing. Real HTTP on map 219: warns 222 unpublished + no items, 218 no items; 220 and 223 clean. `Publish version` (201) still works (re-published 220 → its v2, id 24). |
| US-EXC-1-01 frontend | ✅ code | Link-picker help line, stage-header "⚠ exception → …" chip, Checklist "Handoffs to other maps" box (server warnings). UI e2e pending (E2E-EXC-1-01). |
| US-EXC-1-03 spawn endpoint **610** `POST planner/work-task/{id}/exception` | ✅ | See Test IDs |

### Fixtures (all "safe to delete", account 2)

| Object | Id | What it is |
|---|---|---|
| Parent map (193-based, Items row) | **219**, version **22** | Clone of 216. Triage (`s2`) has 3 `exception` links on 3 different rows: description → **220**, `lens-2` → **222**, items → **218** |
| Linked "repair" map (Items row) | **220**, version **21** | Clone of 216, published |
| Never-published target | **222** | Clone of 218, never published (E-EXC-003 path) |
| No-items target | **218** | Existing RATE-1 fixture (no Items row, published) — linked to, not modified (E-EXC-008 path) |
| No-items parent | **223**, version **23** | Clone of **218** (see Deviations) with Triage → 220 exception link |
| Abandoned 178 clone | 221 | Cloned but fails the publish gate; unused (link 30 on it) |
| Test plan | workspace **34** "EXC-1 test plan (safe to delete)" | Accepts 219 and 223 only — deliberately **not** 220, to exercise D-3 |
| Clones' `owner_user` | — | `clone_scenario` leaves `owner_user = 0`, which makes `Publish version` return 403. Fixed on 219–223 with a scratch `db.patch` (not `updateTableContentItem`). |

### Suites

| Suite | Result |
|---|---|
| `npm test` (webapp/protype-2) | ✅ **608 / 608**, including the new EXC-1 files (`splitLines`, `exceptionLinks`, `exceptionSheet`, `healthText`, plus readiness and matrix-header additions). The error-code registry (GUARD-REG-01) and schema audit (FT-GOV-1-01) each caught a real problem mid-build; both pass now. |
| `npx tsc --noEmit` | ✅ clean |
| `e2e/exceptions.spec.ts` | ✅ 3 / 3 — E2E-EXC-1-01, -02/03/04/06 (one flow), -05 |
| Existing Playwright specs | see **Regression run** below |
| `workflow_tests/1–32` | ⚠️ **not runnable from a session** (CLAUDE.md: no tool runs a workflow test). Shared code they cover was protected instead by re-running the endpoints over HTTP before and after every change (FT-EXC-1-15 for 554 / 607 / 563). |
| `workflow_tests/33_exceptions.xs` | ⚠️ **written locally, NOT pushed** — Xano refused: *"Your plan only supports 10 workflow tests."* Its assertions were run live through scratch harnesses (FT-EXC-1-01, -16). |

### Test IDs

| ID | Result | Evidence |
|---|---|---|
| UT-EXC-1-01…04 | ✅ | golden file, both twins |
| UT-EXC-1-05 | ✅ | `exceptionLinksForStage` |
| UT-EXC-1-06 | ✅ | `childTitle` (the cut keeps the count; a trailing space is trimmed) |
| UT-EXC-1-07 | ✅ | 7 golden readiness cases |
| FT-EXC-1-01 | ✅ | backend `split_lines` = TypeScript on all 11 golden cases |
| FT-EXC-1-02 | ✅ | Job 58: 3 items, Triage **started** (EST-1's freeze in force — a 607 PUT was refused E-EST-007), sent 2 → child **59** with 2 items, pinned to Repair's latest version (v2, id 24), 8 tasks; parent line 1; parent estimate 723 → 715 and its untweaked slot 107 refreshed 723 → 715; parent step still `in_progress`; exception row 6; `exception_raised`, `child_job_created`, `lines_moved` success events; the parent step's feed reads "Sent to … → job #59 (2 items). Reason: something went wrong." |
| FT-EXC-1-03 | ✅ | Job 56: the last item of a line moved → parent line removed, child has it |
| FT-EXC-1-04 | ✅ | No-items job 64 (map 223): counts refused **E-EXC-004**; whole-job send → child 65 with no lines, parent untouched |
| FT-EXC-1-05 | ✅ | unpublished target → **E-EXC-003**; stage with no link → **E-EXC-002**; a link added to the **live** map only (219 s3, link 32) → **E-EXC-002** |
| FT-EXC-1-06 | ✅ | block on an `in_progress` step → `blocked` with the reason through LOG-1's engine, `parent_blocked = true`; block on a `done` step → the send still succeeds, `parent_blocked = false`, `block_refusal` = LOG-1's own sentence, `rejected` logged |
| FT-EXC-1-07 | ✅ | slot 106 tweaked to 700 ("other"); moving 5 items left it at 700, `tweaked_skipped_count 1`, `estimate_changed_under_tweak` warn |
| FT-EXC-1-08 | ✅ | counts sent to map 218 (no Items row) → **E-EXC-008** |
| FT-EXC-1-09 | ✅ | cancelled job 55 and completed job 53 → **E-EXC-001** |
| FT-EXC-1-10 | ✅ | children show in 559 (unscheduled, `parent_work_item_id` set) and 558 (`child_count`) — even though plan 34 never accepted map 220 (D-3) |
| FT-EXC-1-11 | ✅ | 555 on job 58: `children` 59 / 61 (exception) and 67 (added by hand); on 59: `parent` 58 at Triage |
| FT-EXC-1-12 | ✅ | variance (568) for job 58: expected = the new estimate (62, 13, …); none of the child's work appears |
| FT-EXC-1-13 | ✅ | 554 with a parent: same plan → set; other plan → **E-EXC-009**; cancelled → **E-EXC-001**; missing → **E-EXC-009**; omitted → 0 |
| FT-EXC-1-14 | ✅ | Repair map 220 given its own exception link (→ 223) and republished (v3, id 25); job 58 → child **79** (on v3) → its Triage → child **80**; Health shows depth 2 |
| FT-EXC-1-15 | ✅ | 554, 607 **and 563** identical before/after extraction (Progress log) |
| FT-EXC-1-16 | ✅ | golden cases live + real HTTP on maps 219 / 220 / 223 |
| E2E-EXC-1-01 | ✅ | stage-header chip; Checklist "Handoffs to other maps" on 219, none on 223 |
| E2E-EXC-1-02 | ✅ (planner trigger) | send 2 → toast "Sent 2 FT Active Item to … (#N)", chip "2 → #N", parent left with 1 |
| E2E-EXC-1-03 | ✅ | a server refusal (E-EXC-008) shows its sentence; reason, note and count all kept |
| E2E-EXC-1-04 | ✅ | child row "from #P" opens the parent; parent shows "1 sent on" |
| E2E-EXC-1-05 | ✅ **render test** | see Found, not fixed #1 — nobody is a platform admin, so the page was served the panel function's real output |
| E2E-EXC-1-06 | ✅ | confirm button hit-tested with every field filled and again after a refusal; send buttons and chips hit-tested |

### Governance tests

| ID | Result | Evidence |
|---|---|---|
| UT-EXC-1-G01 | ✅ | junk reason / note / counts in the sheet rules; the same junk through backend `split_lines` live — all refused with the right code, **no crash** (the first version crashed "Not numeric."; fixed) |
| FT-EXC-1-G01 | ✅ | 13 refusal cases over HTTP: each 400 + plain sentence + code, a `rejected` event (Health counts them by code), job 58's lines unchanged afterwards |
| FT-EXC-1-G02 | ✅ | the endpoint's own try/transaction shape, forced to fail AFTER `create_job` with a real unique-index violation: caught, the half-made job and its task rolled back (0 survivors) |
| FT-EXC-1-G03 | ✅ | `schemaAudit.ts` covers 140 (append-only, unique child, enums); it caught two unindexed references — both indexes added live and locally |
| FT-EXC-1-G04 | ✅ | job 56 cancelled → children 57 / 60 / 63 still `open`; all three under Health "needs attention" |
| FT-EXC-1-G05 | ✅ | 140 added to `historyTables.ts`: any `db.del` on it now fails the build. The one write after insert (`parent_blocked = true`) is documented on the table |

### Deviations from the epic

- **No-items parent is a clone of 218 (193-based, no Items row), not a 178 clone.** A fresh 178 clone (221) fails the publish gate on every stage; 223 gives exactly what the test needs.
- **`create_job` runs inside the caller's transaction** (the epic said `function.run` stays outside) — verified safe live first.
- **563's engine was extracted too** (`log/record_task_event`). The epic said "call the same function 563 uses"; there wasn't one. Copying its writes into the spawn would be the duplication the house rule forbids, so it was moved verbatim and 563 now calls it — proven identical over 14 outcomes. It adds a `soft` mode so a refused block can't fail a send.
- **Per-step targets come from a new read, `GET work_item/{id}/links` (611)**, not from 567. One list for both screens; 567 untouched. 555 still gained `parent` / `children`.
- **The snapshot's links carry no label**, so the child's title uses the target **map title** (adding a label would change the version hash, which this epic must not touch).
- **`also_block_parent` is read as a plain bool** — omitted and false both mean "don't block", so a raw-input check adds nothing.
- **Health's "unpublished targets" read live link rows**, and readiness doesn't log `exception_map_unpublished` events: 520 is polled, and an event per poll would flood the log (OBS-1's heartbeat lesson).
- **Refusals return 400, not 422** — this codebase's standard for `inputerror`.
- **E-EXC-001's wording widened** to "That job is finished or cancelled, so nothing can be sent from it or added under it." One code was carrying two sentences; the registry test flagged it.
- **Readiness warnings appear in the map's Checklist** (read when it opens). No e2e adds a link through the picker itself.

### Found, not fixed

1. **Nobody can open the Health page.** No user in the workspace has `is_platform_admin`, including the founder (`/health` redirects away; `ops/*` returns E-OBS-001). Fixing it means setting that flag on a `user` row — a change to existing data, so it needs your yes.
2. **The performer's "Send to…" button is not e2e-tested.** `/perform` only shows published days for an agent linked to the signed-in user, and account 2 has only the founder and a real teammate. A dedicated test login would close this. The sheet is the same component and is fully tested from the planner.
3. **Sending items away also lowers the parent's expected minutes for stages already DONE** (`estimate_job` reads the current lines) and refreshes those stages' untweaked slots. FT-12 expects exactly this, but it rewrites "expected" for finished work. Needs a decision: freeze expected minutes for finished steps, or accept it.
4. **The backlog read (559) took ~14 s on the 20-job test plan** — EST-1 estimates every job on each read. Not caused by EXC-1, but every send triggers that reload.
5. **A send takes ~4 s** (events, slot refresh, feed note). The button shows "Sending…".
6. **`errorCatalog.json` was garbled before this session** — 37 user messages showed "â€”" instead of "—" (double-encoded, in uncommitted edits). Repaired mechanically; every entry in the last commit now matches it exactly.
7. **Xano plan limit: 10 workflow tests** — new `workflow_tests/*` files can't be pushed.
9. **The planner board is slow for plans with many Items-row jobs.** `planner/job_step_hydration` (EST-1) loads EVERY job in the plan — cancelled ones too — and runs a ~1 s estimate for each Items-row job on every board read: 13–15 s for a 25-job plan. It will hit real plans as they grow. Not fixed here (EST-1's code); the obvious first step is skipping cancelled jobs.
8. **Three new silent XanoScript traps**, now in CLAUDE.md: an unwrapped ternary or filter-with-arguments as an object value drops every key after it; an omitted function input inherits the caller's input of the same name; `|get:""` returns the whole object.

### Live objects changed

- **Table 140** `work_item_exception` created (approved), plus indexes on `target_version_id` and `created_by`.
- **New functions:** 241 `jobs/create_job`, 242 `estimate/refresh_job_slots`, 246 `exceptions/split_lines`, 248 `exceptions/exception_targets`, 251 `log/record_task_event`, 260 `exceptions/job_links`, 261 `ops/exceptions_panel`.
- **New endpoints:** 610 `POST planner/work-task/{id}/exception`, 611 `GET planner/work_item/{id}/links`, 612 `GET ops/exceptions`.
- **Updated (additive or behaviour-identical):** 554, 555, 558, 559, 563, 607 (planner); 520 (journey-map); functions 93 `pub/evaluate_readiness`, 94 `pub/evaluate_gate`, 69 `ops/error_catalog` (+11 EXC codes).
- **Fixtures** (all "safe to delete", account 2): maps 219–223, versions 21–25, links 27–33, plan 34 with agent 45 / timeline 39 (moved to 2027-01-15), jobs 53–82 in plan 34, exception rows 5–21. **Plan 34 is archived** (restorable via the archive endpoint) and every job in it except 58 / 59 / 64 / 65 is cancelled, to keep it from slowing the planner (Found #9). Each e2e run makes and archives its own "EXC-1 e2e <time>" plan. Job 43 (an EST-1 fixture) was edited and put back to its original 4 items. Scratch functions all deleted.
- **Not touched:** maps 193 and 178, `product/validation-publish-execution/`, the catalog UI, the Items cell editor, publish / hash code, `log/next_status`.

### Regression run

Full suite (45 tests, one worker, 22.5 min): **12 passed, 28 failed, 5 skipped** on the first pass. Then the specs in the areas this epic touches were re-run after two fixes below.

| Spec | Result | Why |
|---|---|---|
| `exceptions` (new) | ✅ 3 / 3 | — |
| `jobs-and-day-navigation` | ✅ 4 / 4 (after the fix) | W1-01 first failed: it picks the first plan with a map, which had become the EXC-1 test plan, and that plan's board read took 13–15 s. **Fixed by** making `exceptions.spec.ts` create, use and archive its own small plan per run, and archiving plan 34 (restorable). Root cause is Found #9. |
| `health-page`, `plan-templates-roster` | ✅ 1 / 1, 2 / 2 | — |
| `items-row` | ⚠️ 01 ✅, 02/03/04 **vary run to run** | Fixture state on map 215: the screenshot shows the Items cell with no item lines to type into, so the steps that need a line can't start. The "Link to Map" section this epic edited isn't rendered on that page. Not caused by EXC-1; needs ITEM-1's spec to set up its own lines. |
| `card-scheduling` | ✘ 1 | The **pre-existing** "8 steps" selector ambiguity EST-1 already documented (matches the Jobs-list row instead of the card). |
| AI / chat / `cell-identifiers` / `internal-actor` / `seed-map-data` (21) | ✘ | Pre-existing: these open `/` and expect to land in a map (O14's note), or wait on live AI replies; they never reach code this epic changed. The map page itself is proven working by E2E-EXC-1-01 and `items-row` 01. |
| `perform-sessions-mobile` (3) | skipped | needs `PERFORM_TEST_AUTH_TOKEN` (pre-existing) |


### Completion gate

| Gate item | State |
|---|---|
| Every in-scope test green by ID | ✅ (E2E-05 as a render test — Found #1) |
| `npm test` | ✅ 608 / 608 |
| Existing e2e | see Regression run |
| `workflow_tests/1–32`, `33` | ⚠️ not runnable; 33 not pushable (plan limit) |
| Extractions changed nothing (FT-EXC-1-15) | ✅ 554, 607, 563 |
| Every new button reachable by a person (E2E-EXC-1-06) | ✅ planner side; performer trigger untested (Found #2) |
| Phase-4 E2E-1 rehearsal with a send mid-way | ⚠️ **partial** — plan → job → lines → schedule → start → send → block → complete → cancel → variance all exercised on the 193-based clone and the no-items clone; the **publish-a-day → perform** leg was not, for the same reason as Found #2 |
| Opus review pass | ✅ run 2026-10-26 — all 4 confirmed findings fixed and verified live (#4 via a founder-approved change to table 140) — see Opus review |

### Opus review (2026-10-26, independent, read-only)

**Confirmed (as found):**

1. **A retry can make a second child job.** 610 has no idempotency key, and the panel makes a new correlation id on every tap. The post-commit work (estimate, slot refresh, feed note, events, `610:826-998`) runs outside the try/catch, so a throw or a mobile timeout there shows "didn't send" after the data is already saved. A second tap then sends again.
2. **The parent's feed note can go missing silently.** `610:879-891` ignores `$note_result`. A `member` sending from a step assigned to someone else is refused by E-LOG-003 in soft mode, so the note is never written. "Also block" is refused the same way.
3. **The performer's step screen goes stale after a send.** `StepScreen.tsx:149` passes no `onSent`, so after "This step is stuck" blocks the step on the server, the screen still shows the old status and buttons. Complete then fails with E-LOG-001.
4. **Two simultaneous sends can move more items than exist.** The parent's lines are read before the transaction (`610:248`) and patched to absolute quantities without a re-read. Two "2 of 3" sends would leave the parent at 1 and give each child 2.

**Plausible, not confirmed:**

- A non-array `lines` input may 500 instead of returning E-EXC-006.
- A plain-text attribute value may break the attribute copy (`610:632`).
- `refresh_job_slots.xs:244-263` branches on a var updated in the same loop pass. This came across verbatim from EST-1, and FT-15 covered only complete jobs.
- `exception_targets.xs:96` looks up stage labels with no `"k:"` prefix (`|get:""` trap). Low likelihood.
- 558 and 559 count `child_count` differently.

**Fixes (2026-10-26, founder said yes; all pushed live):**

| # | Fix | Live evidence |
|---|---|---|
| 1 | Retry. The sheet keeps ONE request id per opening and reuses it on retry. 610 refuses a repeat as **E-EXC-013**, "This was already sent. Reopen the job to see it.", both up front and again inside the transaction. `child_job_created` now logs INSIDE the transaction, so the marker commits with the job. The panel treats E-EXC-013 as sent (`isAlreadySent`, unit-tested). The follow-up work after the commit (estimate, slots, note, block) runs in its own try_catch, so a failure there logs `exception_followup` / `failure` and still returns the child (`followup_failed: true`), never an error. | Plan 38, job 90: first send 200 (child 91); the same request id again → **400 E-EXC-013**; parent 5 → 4, not 3 |
| 2 | Feed note. New `system_note` input on `log/record_task_event`: a system-written **note** skips the assignment rule; every other event type ignores it. 610 sets it for the note, NOT for the block. If the note is still refused, an `exception_followup` warning is logged. | runWorkspaceFunction on an assigned task (137, EST-1 fixture) as an unassigned member. A note with the flag off → E-LOG-003, unchanged. With the flag on → written. `started` with the flag on → still **E-LOG-003**. |
| 3 | Stale step screen. `StepScreen` takes `onExceptionSent`, and `PerformToday` passes its `refresh` (re-fetch without losing the user's place). | tsc clean. The performer path still has no e2e (Found #2). |
| 4 | Two sends at once. **First try failed:** a no-op `db.patch` "row lock" plus a lines re-read in the transaction; two parallel sends BOTH committed (children 92, 93; parent left at 1), because Xano's transaction does not serialize requests. **Fix (founder said yes, 2026-10-26):** new column `work_item_exception.parent_seq` + UNIQUE index (`parent_work_item_id`, `parent_seq`). Each send claims `parent_seq` = exceptions on the parent **counted with the lines its checks read** + 1. The loser's insert is refused, its whole transaction rolls back, and 610 reports **E-EXC-012** (it sees its claimed number taken) and logs it `rejected`. The lock patch is removed. **Second lesson:** counting inside the transaction (just before the insert) still let both win (children 102/103 got seq 1 and 2); the count must come from the same moment as the checks. | Plan 40: 3 of 3 rounds both succeeded (count in the transaction). **Plan 41, after the fix: 4 of 4 rounds = exactly one 200 + one 400 E-EXC-012, parent left at 1 every time; losers' child ids (115, 118, 120, 123) → 404, nothing half-written.** Sequential sends still work (seq 1, 2; parent 4 → 2). |
| P | Non-array `lines` (`"abc"`, `{…}`, `7`) | each → 400 E-EXC-006 (was at risk of a 500) |
| P | Plain-text attribute value (`{"po":"123"}`) | child 95 got `{"po":{"value":"123","source":"parent #94"}}`; object values unchanged |
| P | `exception_targets` stage-label lookup | now prefixed `"k:"` (the `|get:""` trap) |

**#4 schema change (done, founder approved 2026-10-26):** table 140 gained `parent_seq int` (pushed via `updateTable` XanoScript; the `trim` validators survived). All 22 existing rows were backfilled to `parent_seq = -id` (scratch function, deleted), then the UNIQUE index (`parent_work_item_id`, `parent_seq`) was added. Additive only. **Rollback:** drop the index, then the column; 610's only use is the insert and the lost-race check.

**Found by the founder in the map editor (2026-10-27), fixed:** a link on an **Items-row** cell never showed. The grid's Items-cell markup skipped the link marker, and the cell panel's "Link to Map" section was create-only, so a saved link looked unsaved. The marker now renders on Items cells (unit test added), and the panel lists the cell's existing links with a click-through to the linked map. `npm test` 610 / 610, tsc clean.

**Still open from the review, not fixed:** `refresh_job_slots.xs:244-263` reads a var updated in the same loop pass (moved verbatim from EST-1; EST-1's to own). 558 and 559 count `child_count` differently (cosmetic).

**Tests after the fixes:** `npm test` **609 / 609** (+1 `isAlreadySent`), tsc clean, `e2e/exceptions.spec.ts` **3 / 3**. Fixtures: plans 38–41 (archived), jobs 90–124 from these runs (cancelled), probe notes on tasks 226 and 137. Scratch functions deleted. The #4 fix is backend-only (no frontend change), so the frontend suites were not re-run after it.

**Checked clean:** tenancy on 610, 611 and 554; inputs on every `function.run`; every object literal; rollback of `create_job`; the split twins; the readiness twins; the child title; input kept on refusal.

**Status:** built and tested; waiting for the founder.
