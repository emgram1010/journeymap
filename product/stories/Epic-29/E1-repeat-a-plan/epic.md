# REPEAT-1 — Repeat a plan for the next period

**Epic ID:** REPEAT-1 (E1 in this folder)
**Status:** 📋 Not built (docs only, 2026-11-25)
**Size:** L
**Model:** Sonnet 5.5 for stories 00–02 and 05–07. **Opus 5.5** for 03 and 04 (jobs pinned to versions, race guards, one large write). Then an Opus review.
**Depends on:** nothing in this folder. Built on PLAN-1/2/3, JOB-1, SCHED-1, TW-1, LIVE-1.
**Read first:** `../README.md`.

---

## 1. Goal

**Pain:** a planner builds a week by hand: the days, the jobs, the order, who does what. Next
week is mostly the same, and all of it is built by hand again.

**Win:** one action makes the next period from the last one. The planner reviews what changed
instead of rebuilding what did not.

## 2. What exists today (repo and live compared 2026-11-25: planner code identical; see README F-6, F-8, F-15–F-17)

| Fact | Where |
|---|---|
| A plan is a `planner_workspace` with a start and end date. Its name is unique per account | `static/tables/115_planner_workspace.xs` |
| A plan template copies **only** the window length, accepted maps and roster into a new plan | `apis/planner/551_template_template_id_instance_POST.xs` |
| A day is one person's `planner_timeline` for one date, unique per (person, date), with a start time and `draft`/`published` | `static/tables/117_planner_timeline.xs` |
| A person on a plan is a `planner_agent`, created fresh in every plan | `static/tables/116_planner_agent.xs` |
| A job (`work_item`) is pinned to one published map version; its steps (`work_task`) are pointers to that version | `static/tables/122_work_item.xs`, `123_work_task.xs` |
| Jobs are written in one place: `jobs/create_job`, with steps from `jobs/tasks_from_version` | `functions/jobs/` |
| A scheduled slot is a `planner_task`, linked to its step through `planner_task_work_task` (a step is scheduled at most once) | `static/tables/118_…`, `124_…` |
| A job may carry item lines, a time window and an outside-order origin | tables 139, 141, 175 |
| A slot may carry a manual start time | `static/tables/142_planner_task_start_override.xs` |
| Publish to live freezes one day into `plan_publication`; history hangs off that, never off a slot | `apis/planner/562_…publish_POST.xs` |

### 2a. Everything that hangs off a plan (story 00, 2026-11-25)

Found by searching every table in `static/tables/` for a reference to a plan, day, person, slot, job or step, then checking the live schema of the main ones. Live and repo agree on every table checked (115, 116, 117, 118, 119, 122, 123, 124, 125, 129, 130, 142, 175; planner code was compared the same day).

| Table | Hangs off | Repeat does |
|---|---|---|
| `planner_workspace` (115) | the plan itself. Has `plan_template_id` and `is_archived` | **new row**, not copied. `plan_template_id` is carried so the new plan remembers its template |
| `planner_workspace_map` (121) | plan | **copied** (accepted maps) |
| `planner_agent` (116) | plan | **copied** (roster), with REQ-1 story 03 adding the profile link |
| `planner_timeline` (117) | plan + person | **copied**, dates moved, always `draft` |
| `planner_task` (118) | plan + day + person | **copied**, marked needs review |
| `planner_task_start_override` (142) | slot | **copied** only if D-3 says a manual start carries over (decide in story 04) |
| `work_item` (122) | plan, pinned to a map version | **created fresh**, pinned to the map's current published version |
| `work_task` (123) | job | **created fresh** by `jobs/tasks_from_version`; status `not_started` |
| `planner_task_work_task` (124) | slot + step | **created fresh** (a step is scheduled at most once) |
| `work_item_line` (139), `work_item_time_window` (141) | job | **copied** (shape of the job) |
| `work_item_unmatched_line` (171) | job | **not copied (history)**: a fact about one order import |
| `work_item_origin` (175), `order_inbox` (177) | job | **not copied (one-off)**: an outside order is never duplicated (unique on account + source + external id) |
| `work_item_exception` (140) | parent + child job | **not copied (one-off)**: children of an exception are not repeated |
| `plan_publication` (125), `plan_change_log` (126), `live_day_addition` (179) | day | **not copied (history)** |
| `activity_log` (127) | job, step, person | **not copied (history)** |
| `order_route` (176), `order_route_live_day` (178) | plan, person | **not copied**: routing points at one plan; the owner re-points it. Listed in the preview so it is not a surprise |
| `ai_member_profile.plan_ids` (172, a json list) | plan | **not copied**: an AI member keeps access only to the plans it was given. A repeat never widens an AI's reach. Listed in the preview |

No table is marked unknown. Two things not in the epic before: `work_item.parent_work_item_id` (a plain int, no reference) and the json `plan_ids` on AI members, both of which a repeat must handle on purpose.

**Frontend:** the planner in use is `webapp/protype-2/src/planner/PlannerApp.tsx` (routed at `/planner`). `webapp/planningFrontendv2` was last changed 2026-10-03 and is not routed. The "from template" flow (`TemplatesModal`, `createWorkspaceFromTemplate`) is where a "Repeat" action sits beside it; the preview (story 01) opens from the plan list and the board header.

## 3. Rule

**A repeat makes a new plan. It never changes the old one, and it never copies history.**

- The new plan is its own plan from the moment it exists (the same rule the template follows).
- Every date moves forward by the same number of days.
- **Shape is copied** (days, order, who). **Facts are not** (statuses, the activity log, published days).
- **Definitions are read fresh**: every repeated job is pinned to its map's current published version.
- Every copied assignment is marked **needs review** (D-2).
- Anything that could not be copied is **named with a reason**. Nothing is dropped quietly.

## 4. Do not break

- Creating a plan from a template works exactly as it does today.
- The source plan is not written to: no row in it changes (checked before and after by counts and a hash of its board).
- No published day, publication or activity-log row is copied or changed.
- An outside order is never duplicated (`work_item_origin`'s unique index is never hit).
- No column is added to an existing table.

## 5. Non-goals

- A plan that repeats by itself on a schedule, with no click (D-14).
- Repeating into the **same** plan (extending a plan's window).
- Copying a plan to another account.
- Merging a repeat into a plan that already has work.
- Smart rebalancing of who does what. That is MATCH-1.

## 6. New tables (additive)

| Table | What it holds | Guard |
|---|---|---|
| `plan_repeat` | One row per repeat: source plan, new plan, days moved, who, when, state (`building`, `ready`, `failed`), the counts and the list of what was left out | Unique on (source plan, new start date): two clicks cannot make two copies |
| `planner_task_review` | One row per slot that needs a person to look at it: slot, reason, raised when, cleared when and by whom | Unique on slot; absence of a row means nothing to review |

## 7. Stories

| File | Story |
|---|---|
| `US-REPEAT-1-00-check-what-is-live.md` | Read-only: compare live to the repo, list everything that hangs off a plan, measure one large write |
| `US-REPEAT-1-01-preview-a-repeat.md` | See what will be copied and what will not, before anything is written |
| `US-REPEAT-1-02-new-plan-people-and-days.md` | Create the new plan, its people and its days |
| `US-REPEAT-1-03-jobs-read-the-current-version.md` | Repeat the jobs, pinned to the current published version |
| `US-REPEAT-1-04-order-and-people-carry-over.md` | Carry the order and the assignments, drop who cannot be carried |
| `US-REPEAT-1-05-needs-review.md` | Show, clear and publish-through the "needs review" marks |
| `US-REPEAT-1-06-several-periods-and-history.md` | Repeat several periods at once; see where a plan came from |
| `US-REPEAT-1-07-ai-can-draft-a-repeat.md` | A connector and copilot tool that drafts a repeat and never publishes |

Stories 02, 03 and 04 are one user action and one all-or-nothing write. They are split so each
can be tested alone.

## 8. Completion gate

- A plan with 3 people, 5 days and 10 jobs is repeated; the new plan shows the same shape 7 days later.
- The source plan is byte-for-byte unchanged.
- A job whose map got a new published version reads the new version; the summary names it.
- An outside order, an exception child and a cancelled job are not in the new plan, and the summary says so.
- An inactive person's work is in the backlog with the reason.
- Every copied slot is marked needs review; publishing a day clears that day's marks.
- Two clicks at once make one plan.
- A second account cannot repeat, preview or see the first account's plan.
- Existing suites green. Test Results filled in.

## 9. Test Results

### Story 00 — check what is live (2026-11-25, branch `epic-29-repeat-1`)

| Test | Result |
|---|---|
| T-REPEAT-00-1 live compared | ✅ every table in section 2 fetched live or compared by the same-day planner pull; no differences |
| T-REPEAT-00-2 no table unknown | ✅ see section 2a |
| T-REPEAT-00-3 large-write timing | ✅ one transaction, jobs × 10 steps: 110 rows 1.2 s · 275 rows 3.1 s · 550 rows 5.9 s. All finished |

- **Timing reads as about 11 ms per row, in a straight line.** One transaction holds 550 rows without trouble. A real week also writes days, slots, links, item lines and time windows, so a 50-job week is roughly 1,200–1,500 rows: 13–17 s. That works but is slow enough to need a "building" message on screen, and 8 periods at once must be 8 separate writes, never one (story 06 already says so).
- **Decision for story 02:** one all-or-nothing write per period is fine. The staged `building` state stays as the fallback for plans above about 150 jobs; the preview (story 01) shows the row estimate so a very large plan is warned before it starts.
- **How it was measured:** a scratch function wrote the rows inside a transaction and then forced a rollback; a count afterwards found 0 rows left each time. The scratch function was deleted. Nothing else was written to Xano.
- **Learned on the way:** `work_task` refuses two steps with the same job, stage and row (the first run stopped at the second step). A repeat gets this for free from `jobs/tasks_from_version`. Also confirmed live: `while` loops nest, a `throw` inside `db.transaction` rolls it back, and a `var.update` made inside the transaction before the throw is still readable after the `try_catch`.
- One thing from the same-day review still matters here: `live/build_publication` loads the whole link table on every publish (README F-15). Each repeated week makes publishing slower, so measure it with the large write.

### Story 01 — preview a repeat (2026-11-25: built, hidden until the copy exists)

**Built:** `functions/repeat/build_plan.xs` (live id 459), endpoint `POST workspace/{id}/repeat-preview` (live id 682), `webapp/protype-2/src/planner/repeatPreviewModel.ts` with its tests, `previewRepeat` in `plannerApi.ts`, and three entries in `errorCatalog.json`.

| Test | Result |
|---|---|
| T-REPEAT-01-1 offered start and name | ✅ live: 7-day plan 145 offers 2026-11-28; 14-day plan 115 offers 2026-12-15; name "<plan> (<start>)" is free. Unit: 3 cases |
| T-REPEAT-01-2 counts | ✅ live on plan 115: 26 jobs = 12 repeat + 2 left out + 12 will not; steps, slots and backlog add up |
| T-REPEAT-01-3 one-off jobs | ✅ live: 9 outside orders, 2 exception children and 1 cancelled job on plan 115 all `will_not_repeat` with the right reason. Unit: not tickable |
| T-REPEAT-01-4 inactive person | ✅ live on plan 42: Tony (login switched off) is left off, 1 slot goes to the backlog |
| T-REPEAT-01-5 map versions | ✅ "newer version" live (plan 42: 3 jobs move from version 27 to 29). ✅ archived map: test map 261 archived inside a transaction that was then rolled back; all 14 jobs became `cannot_repeat`, the 12 one-offs stayed `will_not_repeat`, and the map was `active` again afterwards. "No published version" cannot happen with real data (a job is always pinned to a version that exists, so its map always has one); the branch stays as a guard |
| T-REPEAT-01-6 weekday warning, overlap | ✅ live: shift of 9 days gives `weekdays_align: false`; start inside the window returns E-REPEAT-003. Unit: 5 cases |
| T-REPEAT-01-7 writes nothing | ✅ by construction: the function has no add, patch or delete (checked by search). Row counts were not compared |
| T-REPEAT-01-8 second account | ✅ live: account 13 asking for account 2's plan 42 gets "Not Found" |
| Bad dates (E-REPEAT-002) | ✅ live: "tomorrow", "2026-13-45" and "2027-02-31" all refused with the plain message |

- Unit: `repeatPreviewModel.test.ts` 16 of 16. Full `npm test` 1,108 of 1,108. `tsc` clean.
- **Over real HTTP** (test user 21, account 13, one-time magic link): own plan 200 with the right counts; unticked job counted as left out; overlap 400 E-REPEAT-003; impossible date 400 E-REPEAT-002; another account's plan 404 "Plan not found"; no token 401; a user without planner access 403 E-USR-006. Both refusals were written to `event_log` as `plan.repeat_preview` / `rejected`.
- **Screen** (`components/RepeatPlanModal.tsx`, checked in the browser on the test account): opens from the plan menu, shows the server's counts and lists, unticking a job updates the counts (14 → 13), an overlapping date shows the E-REPEAT-003 message and keeps the typed date, a later date clears it and shows the weekday warning. Phone width 375 px: no sideways scroll. No console errors.
- **Found and fixed in the browser:** the tickable job list was capped at 8, so jobs 9+ could not be unticked. The list a planner ticks is now never capped.
- **Hidden:** the menu item only appears when `VITE_REPEAT_PLAN_UI=1` (launch entry `protype-2-repeat-ui`, file `webapp/protype-2/.env.repeatui`, git-ignored). It is switched on for everyone when the copy (stories 02–04) lands.
- Workflow tests and Playwright were not run (no workflow test can be run from a session; no Playwright spec covers this yet).

**Differs from the story, and why**
- The endpoint is a POST, not a GET: it carries the list of unticked jobs, and optional list inputs on a GET are unreliable here. It still writes nothing.
- Lists are returned whole, not capped; the screen caps them ("and N more"). The real copy needs the whole list from the same function.
- E-REPEAT-001 is in the catalog but the server returns the planner's usual "Plan not found", so another account's plan looks exactly like a missing one.
- The three codes were added to `errorCatalog.json` only. The server copy (`functions/ops/error_catalog.xs`) holds 55 of 324 codes and has someone's unpushed edit, so it was left alone.
- `errorCatalog.json` and `package.json` also hold uncommitted edits from other work (BRIEF-1). Only this story's lines were committed (the three codes, and the test in `npm test`); the BRIEF-1 lines are still uncommitted in the working tree.

**Learned (XanoScript, confirmed live)**
- `to_timestamp` throws on a month or day that cannot exist ("2026-13-45") and rolls over a day that is only too large ("2027-02-31" becomes 3 March). Validate the shape, catch the throw, and compare the round trip.
- `output = [...]` works on a `list` query and keeps the rows loopable.
- `%` gives the remainder; `sort = {table.field: "asc"}` works on a list query.
- A chain of `var.update $x { value = ((cond) ? "a" : $x) }` lines inside a `foreach` works, including when the condition reads variables set earlier in the same pass. It is the safe replacement for a `conditional` there.

### Story 02 — new plan, people and days (started 2026-11-25)

- **Tests written first:** T-REPEAT-02-1 (dates move across a month end, a year end and a leap day; 7, 14 and 31-day plans keep their length) — 3 unit tests, passing against `shiftDate` in `repeatPreviewModel.ts`.
- **Table pushed 2026-11-25 (founder's yes):** `plan_repeat`, live table id 181, from `static/tables/181_plan_repeat.xs`. New table only; no existing table changed. Live schema read back: every field and all 4 indexes present (unique source+date, unique new plan, account btree).
- **Race guard proved live:** a scratch function inserted two rows with the same (source plan, start date) in one transaction → refused ("Duplicate record detected"), whole transaction rolled back. Two different start dates for the same source → both accepted (then rolled back on purpose). Table read back empty afterwards; scratch function deleted.
- **Built:** `repeat/create_plan` (live function 465) and `POST workspace/{workspace_id}/repeat` (live endpoint 683, planner group). Not wired into the app yet: the button arrives once stories 03–04 add jobs and slots to the same write.
- **Fixture:** a throwaway plan in test account 13: 3 people (Ana with a login and 7.5 hours; Bot, an AI with a model and hidden; Old, inactive), 4 days (one published), 2 accepted maps (one belonging to another account, so unusable). Deleted afterwards with all copies, `plan_repeat` rows and scratch functions. Event-log rows were kept as history.

| Test | Result |
|---|---|
| T-REPEAT-02-1 dates | ✅ unit (3 tests). Live: 7-day plan moved by 7 and by 14 days; window and every day landed right |
| T-REPEAT-02-2 maps from the plan | ✅ live: the plan's usable map copied; the other account's map left out and named `map_unavailable` |
| T-REPEAT-02-3 people, every field | ✅ live: name, kind, colour, daily hours, login, hidden flag and AI model all equal to the source |
| T-REPEAT-02-4 left off and named | ✅ live: inactive person not copied, named with `inactive`; `plan.repeat_skipped_person` (warn) logged. Login-off path is build_plan's rule, proven live in story 01 (Tony) |
| T-REPEAT-02-5 days | ✅ live: 3 of 4 days copied (the left-off person's day is not), start times 07:30 / 08:00 / 09:15 kept, all `draft`, including the one that was published |
| T-REPEAT-02-6 parallel confirms | ✅ real HTTP, 3 identical confirms at once: 1 created, 2 answered `exists` with the same plan id. One loser was a true overlap (`lost_race: true`: the unique index refused it mid-write and it rolled back). Exactly 1 plan and 3 days in the database |
| T-REPEAT-02-7 forced failure | ✅ live (`test_fail_at = 1`, throws after every row is written): no plan, day, person or `plan_repeat` row left; `plan.repeat_failed` / E-REPEAT-006 logged with the counts |
| T-REPEAT-02-8 source unchanged | ✅ a hash of the source's plan, maps, people and days was identical before and after 9 calls |
| T-REPEAT-02-9 second account | ✅ function: "Not Found". HTTP: another account's plan → 404 "Plan not found" |
| Refusals over HTTP | ✅ empty name 400 E-REPEAT-004 · empty date 400 E-REPEAT-002 · overlap 400 E-REPEAT-003 · taken name 400 E-PLN-001 · second click 200 `exists` · no token 401. Each refusal logged as `plan.repeat` / rejected |
| Suites | ✅ `npm test` 1,112 of 1,112 (after the fix below) · `tsc` clean. Workflow tests and Playwright not run |

- **The governance audit caught two gaps in `plan_repeat`** (FT-GOV-1-01): no `updated_at`, and `created_by` not indexed. Fixed locally: marked append-only in the audit manifest (the row is written once) and added a `created_by` index to `181_plan_repeat.xs`. **Index added live 2026-11-25 with the founder's yes** (index `38fa90fd`); live indexes now match the repo file exactly.
- **Differences from the story:** "already repeated" answers 200 with `outcome: "exists"` and the plan id, not an error, so the screen can link to it. "Profile off the roster" cannot be checked yet: a plan person has no profile link until REQ-1 story 03. Hidden people are copied, still hidden. A race on the same NAME but different start dates would surface as E-REPEAT-006 instead of E-PLN-001 (rare; noted for the Opus review).
- **Learning:** a `db.query { where = … return = … }` written on ONE line returned empty results with no error. Multi-line blocks work. `throw` inside a transaction gives `$error.message` = "Throw Error Statement", not its value.
- **Learning:** `db.query … return = {type: "count"}` on a query matching nothing came back as `[]`, not `0`. Treat a zero count as "empty or 0" (`|count` or a loose `== 0`), not a strict int.
- **Design decided from story 00's timing:** one all-or-nothing write, so the row is written as `ready`; no plan is ever visible half-built, and no existing plan list needs a "hide building plans" change.
- **Known limit:** the race guard is unique on (source plan, start date). Plans are archived, never deleted, so once a repeat to a date exists, repeating the same plan to the same date again is refused with a link to the existing plan.

### Stories 03–04 — jobs, slots and order (2026-11-25, Opus 5.5)

- **Tests written first:** reason wording for every new "left out" reason, step changes grouped per job (T-REPEAT-03-2), and the Health rule "more slots to the backlog than placed" (story 04): `repeatPreviewModel.test.ts`, 23 of 23.
- **Built:**
  - `repeat/plan_work` (live 472): read-only, decides every job, line, window and slot before the write.
  - `jobs/step_expected_minutes` (live 471): SCHED-1's "how long is this step" rule, taken out so a copied slot is sized the way a person's click sizes it.
  - `repeat/create_plan` (465): now writes jobs (through `jobs/create_job`), windows, slots, step links and manual start times in the same transaction, then re-reads the counts.
  - `repeat/build_plan` (459): a job whose map the plan no longer accepts is now `cannot_repeat` / `map_not_accepted`.
  - `E-REPEAT-007` in the catalog.
- **Table pushed 2026-11-25 (founder's yes):** `planner_task_review`, live table id 182, from `static/tables/182_planner_task_review.xs`. New table only; every field and all 5 indexes read back (unique slot; workspace, account, cleared_by). Added to the governance audit manifest.
- **Review marks:** written in the same transaction, one per slot the repeat puts on a day (`copied from <plan>`), plus one per slot it sends to the backlog for a reason (`<name> is no longer on the plan`, `new step in this version`). Slots that were already in the source backlog are not marked.
- **Fixture (deleted afterwards with every copy, map, version, rate, item and scratch function; event-log rows kept):** plan 156 in account 13, with 3 people (Old inactive) and 5 days (one published). It has 8 jobs:
  - "Monday run" on map A v1, where v2 drops step s2 and adds s4. It has a window from 22:00 to 02:00 the next day and an attribute.
  - "Chairs" on map B, with 3 lines: one good, one switched-off item, one item not in the version's rates.
  - One job each that is cancelled, an exception child, an outside order, on an archived map, on a map the plan no longer accepts, and unticked.
  - 11 slots: tweaked, a manual start, free-standing, given to another person, on the inactive person's day, backlog, and on dropped jobs.

| Test | Result |
|---|---|
| T-REPEAT-03-1 same version | ✅ "Chairs" kept version 42; every new step `not_started`; job `open` |
| T-REPEAT-03-2 newer version | ✅ "Monday run" pinned to v2 (41), steps s1 · s3 · s4; change list = s4 added, s2 gone |
| T-REPEAT-03-3 newer draft ignored | ✅ by construction: a `journey_map_version` row is only ever written by Publish version (checked in `create_work_item`'s header: 0 of 26 rows without `published_at`); a map's draft is never a version |
| T-REPEAT-03-4 lines | ✅ item 21 × 5 copied (flagged 2 → 0); switched-off item named `item_inactive`; item not in rates named `item_not_in_version` |
| T-REPEAT-03-5 time window | ✅ 2027-03-01 22:00 → 03-02 02:00 became 03-08 22:00 → 03-09 02:00, note kept |
| T-REPEAT-03-6 one-off jobs | ✅ cancelled, exception child, outside order: not repeated, each with its reason; no `work_item_origin` row on the copy |
| T-REPEAT-03-7 unusable maps | ✅ archived map `map_unavailable`; map no longer accepted `map_not_accepted` (new rule) |
| T-REPEAT-03-8 no history | ✅ new jobs: no parent, no start/finish, status `open`; attributes kept, marked `source: repeat` |
| T-REPEAT-03-9 / 04-10 forced failure | ✅ `test_fail_at = 1` reached the throw after every row ("Throw Error Statement" in `plan.repeat_failed`); a re-count found no new plan, job, step, slot, line, day or person |
| T-REPEAT-03-10 50 jobs | ⚠️ works, but slow. 50 jobs, 150 steps and 150 slots took 26 s in total: about 8 s writing (`duration_ms` 8,120) and about 18 s planning. Within the limit, but see the finding below |
| T-REPEAT-04-1 day and position | ✅ every kept slot landed on its person's day 7 days later, in source order; positions 1..n |
| T-REPEAT-04-2 given to another person | ✅ "Sweep yard" (Ben's day, given to Ana) → new Ben's day, given to new Ana |
| T-REPEAT-04-3 free slots and backlog | ✅ title, length, notes and `needs_info` reason copied; backlog order kept (Call customer 1, Chairs s2 2) |
| T-REPEAT-04-4 review marks | ✅ second repeat (to 03-15): 7 marks: 4 `copied` on the placed slots, 2 `person_left_off` with "Old is no longer on the plan", 1 `new_step`; the 2 plain backlog copies unmarked; re-read count `reviews: 7`. A forced failure after this change also left no plan, slot or mark |
| T-REPEAT-04-5 left-off person | ✅ Old's own slot and the slot given to Old both went to the backlog (positions 3, 4) with "Old is no longer on the plan" |
| T-REPEAT-04-6 step gone / new | ✅ s2's slot not created and named `step_gone`; new s4 in the backlog (position 5), reason "new step in this version" |
| T-REPEAT-04-7 lengths | ✅ the tweaked 99-minute slot came back at the new estimate (22); `lengths_reset: 1` |
| T-REPEAT-04-8 manual start | ✅ 10:00 carried on the placed slot |
| T-REPEAT-04-9 order audit | ✅ `planner/audit_sequences` on account 13: no violations |
| T-REPEAT-04-11 counts re-read | ✅ `written` (re-queried) = 2 jobs, 11 steps, 1 line, 1 window, 4 placed, 5 backlog, matching the planned counts |
| Source unchanged | ✅ fingerprint of plan 156 `621c4ad0…` identical before and after both runs |
| Suites | ✅ `npm test` 1,115 of 1,115 · `tsc` clean. Workflow tests and Playwright not run; endpoint 683 unchanged and not re-run over HTTP |

- **Findings for the Opus review:**
  - **Speed:** planning is about 18 s for 50 jobs, because each job and step runs its own function call. Fix: work out steps and lengths once per version for jobs with no lines. Writing is about 22 ms a row, against story 00's 11.
  - **Preview gap:** the preview counts only slots on a left-off person's DAY as "to backlog". The copy also sends a slot GIVEN to a left-off person there (fixture: preview 1, copy 2). `build_plan` needs the same assignee check.
  - **One copy of the length rule:** `planner_ops/schedule_work_task` still has its own copy. Switch it to `jobs/step_expected_minutes`, with a before/after replay.
- **Differences from the story:**
  - Slots are written straight with dense positions, not through `planner/place_task`. That function opens its own transaction and reorders other slots; the copy writes into an empty plan, and the audit proves the order.
  - "New step" and "step gone" count only when a job moves to a newer version.
  - A new step goes to the backlog only if its job had a slot at all.
- **Learning (new trap, live):** inside a MULTI-LINE object literal, a bare number value (`src_id : 0`) turned into `null` and swallowed the next key, with no error. Values from a variable (`$zero`) are safe. Inline `{a: 0, b: 1}` literals were fine.

### Opus review of stories 02–04 (2026-11-25)

Read again end to end: `build_plan`, `plan_work`, `create_plan` and the preview and repeat endpoints. Each fix was pushed, then proven live on a rebuilt fixture and over real HTTP. The fixture was deleted afterwards.

| # | Finding | Fix | Proof |
|---|---|---|---|
| R1 | Preview and copy disagreed on slots: a slot GIVEN to a left-off person, and a step the new version dropped, were counted as copied | Preview (endpoint 682) now runs `repeat/plan_work`, the same function as the copy, for every slot, line and window count and for each person's "to backlog" | HTTP preview: 2 to backlog (was 1), Old 2, 3 not created (was 2), matching the copy exactly |
| R2 | Same name, different start dates, at the same moment: the loser got E-REPEAT-006 "couldn't be created" | After a failed write with no winner, the name is checked again; a taken name is answered with E-PLN-001 and logged with `lost_race: true` | Two parallel HTTP repeats (both about 8.8 s, overlapping): one created, one 400 E-PLN-001, `lost_race: true` |
| R3 | Slow: every job re-ran steps and lengths | Steps and lengths are worked out once per (version + lines) signature | 50 jobs: planning 18 s → 10 s (build_plan 3.2 s + plan_work 6.8 s); save 8.8 s including 150 review marks; 19.6 s in total, was 26 s |
| R4 | A day whose person is not on the plan would put its slots in a backlog position already taken | Such a slot now counts as "person left off" and goes to the backlog in order | Covered by the order audit (`audit_sequences` clean); no live data has this shape |
| R5 | Slots left out for a job step had an empty name | Named after their job | HTTP preview names "Monday run", "Unticked run", "Cancelled run" |

- **Regression:** the rebuilt fixture copied exactly as before: 2 jobs, 11 steps, 1 line, 1 window, 4 placed, 5 backlog and 7 review marks. The order audit is clean.
- **Not fixed, recommended:**
  - (a) The rest of the time is Xano's per-statement cost, about 1.5 ms per step of work, so 100 jobs is about 40 s. The screen needs a "building…" state (story 06 or the button), and the preview should warn above about 100 jobs.
  - (b) `planner_ops/schedule_work_task` still holds its own copy of the length rule. Switch it to `jobs/step_expected_minutes`, with a before/after replay. Not done here: it changes a live endpoint outside this epic.
  - (c) Deleting a slot leaves its review mark behind until story 05 adds it to `planner/delete_task`. No slot can be deleted in a repeated plan before the button ships.
- **Verdict:** stories 02–04 pass review, with (a)–(c) carried forward.

### Story 05 — "needs review" marks (2026-11-26, Sonnet 5.5)

- **Tests written first:** `reviewModel.test.ts`, 5 tests: each slot's mark and reason, counts per day and for the plan (a backlog mark counts for the plan, not for a day), nothing shown when there are no marks, the publish sentence (singular and plural), plain wording for every reason. They now run in `npm test`.
- **Built (backend, all live):**
  - `review/clear_marks` (function 493): the one place a mark is cleared; the cleared row is kept as history (when, who, how).
  - `POST planner_task/{id}/review-clear` (684) and `POST timeline/{id}/review-clear` (685): person only, own account only, logged as `plan.review_cleared`. The day endpoint re-counts and answers `still_open`.
  - Board `GET workspace/{id}/board` (548): now returns `reviews[]`, still-open marks only.
  - Publish to live (562): clears the day's marks inside the same transaction, `how: publish`, and answers `reviews_cleared`. It never blocks.
  - Move a slot (543) and give a slot to someone else (545): clear its mark (`how: moved`) when a person does it; reordering inside one day does not.
  - Unschedule (function 169): the mark is deleted with the slot. The same change is in the held `planner/delete_task`, not pushed.
  - `planner/audit_reviews` (501), added to `planner/integrity_audit` (118): reports `ORPHAN_REVIEW`.
- **Built (app):** a "REVIEW" sign on each marked card and backlog row (click = reviewed, hover = the reason), "N to review" and a "Reviewed" button on each day, "N to review" for the whole plan next to Publish day, and one plain sentence before publishing: "4 items were copied and not yet reviewed. Publish anyway?" (one day, or Publish day for several). Marks load through `adaptBoard`.

| Test | Result |
|---|---|
| T-REPEAT-05-1 board returns marks and reasons; counts per day and plan | ✅ HTTP: 7 open marks listed with their reasons; the already-cleared one hidden. Unit: counts per day and plan. Browser: "3 to review" for the plan, "2 to review" for Ana's day |
| T-REPEAT-05-2 clear one, clear a day | ✅ HTTP: clear one → `cleared: 1`; again → `cleared: 0`; clear a day → `cleared: 1`, `still_open: 0`. Browser: A1 cleared (day 2 → 1), then the day cleared, then the backlog sign cleared; each chip disappeared at zero |
| T-REPEAT-05-3 moving a slot clears its mark | ✅ HTTP: moved to another person's day → mark gone; reassigned a backlog slot → mark gone; reordered inside one day → mark stays |
| T-REPEAT-05-4 publish | ✅ HTTP: day with 2 open marks → 200, `reviews_cleared: 2`, the other day's mark untouched; event `plan.review_cleared` / `publish`. The sentence wording is unit-tested; the browser confirm box itself was not clicked |
| T-REPEAT-05-5 hash equal with and without marks | ✅ `live/build_publication` on a day: identical `snapshot_hash` with no mark, with an open mark and after clearing (`0e3bf6f7…`) |
| T-REPEAT-05-6 delete removes the mark; audit finds no orphan | ✅ unscheduling a linked slot removed its mark (the other marks stayed). The audit flagged a planted mark with no slot as `ORPHAN_REVIEW` and was clean once it was removed. The held `delete_task` change is written, not run |
| T-REPEAT-05-7 AI caller, second account | ⚠️ second account: `review/clear_marks` for account 2 cleared 0, for account 13 cleared 1; unknown slot or day → 404 "Task not found" / "Timeline not found"; no token → 401. AI refusal is the shared `copilot/assert_person_only` (E-COP-025, already proved by COP-5); no AI identity was used here |
| History kept | ✅ cleared rows hold `cleared_by` 21, `cleared_at` and `cleared_how` one / day / moved / publish; a pre-cleared row stayed hidden from the board |
| Suites | ✅ `npm test` 1,120 of 1,120 · `tsc` clean · no console errors in the browser. Workflow tests and Playwright not run |

- **Differences from the story:**
  - No new error codes: a missing slot is the standard "Task not found", and "a person must clear" is the shared E-COP-025 (one code means one thing). E-REPEAT-008 and E-REPEAT-009 are not used.
  - There is no server-side publish preview (the old header comment mentions one that was never built), so the sentence is a confirm box in the app, shown before the publish call.
  - A mark is also cleared when a slot is given to someone else (not only moved), because that is the same "a person looked at it".
- **Cleaned up:** the test plan, its map and version, publication, 7 marks and every scratch function deleted. Event-log rows kept.
- **Learning:** publishing a day needs every person on it to have a login (`Ben doesn't have a login yet`), so a fixture used for a publish test must give each person a user.

### Story 06 — several periods and history (2026-11-26, Sonnet 5.5)

- **Tests written first:** `repeatPeriodsModel.test.ts`, 7 tests: the 1 to 8 limit, periods made in order each from the same source, an existing period skipped and named, a lost race counted as a skip, a failure on period 3 keeping 1 and 2 and not trying 4, plain words for a failure that is not an Error, the "repeated from" / "repeated to" wording including a deleted source. They now run in `npm test`.
- **Design:** the server works out the periods; the app makes each one with its own request. A single request for 8 plans of a big plan would time out (one 50-job plan alone took 20 s), and a failure partway would be hard to report. One correlation id is shared by every period's events. Period n starts at the first start + (n-1) x the plan's length, computed from the first date each time.
- **Built (backend, all live):**
  - `repeat/period_dates` (503) and `repeat/free_name` (504): the date rules and the name rule taken out of `repeat/build_plan` (459, now calls them), so the preview and the period list can never disagree.
  - `repeat/list_periods` (506) and `POST workspace/{id}/repeat-periods` (686): dates, own free name and "already made" for each period; refuses outside 1 to 8 with E-REPEAT-010.
  - `repeat/history` (507) and `GET workspace/{id}/repeat-history` (687): where a plan came from (`exists: false` when that plan is gone) and the plans made from it, with how many of their copied slots still need a look.
  - `E-REPEAT-010` in the error catalog.
- **Built (app, still behind `VITE_REPEAT_PLAN_UI`):** the repeat window now makes plans: a "How many periods (1 to 8)" field, "Create plan" / "Create N plans", a result list ("3 made, 1 already there…", each with Open), and a History section. A line under the header says "Repeated from <plan>" (with Open) and "N plans repeated from this one".

| Test | Result |
|---|---|
| T-REPEAT-06-1 4 periods: dates, no gap, no overlap, all from the source | ✅ HTTP: starts 06-14, 06-21, 06-28, 07-05, each 7 days, no gap, shift 7 / 14 / 21 / 28 days from the source, names all distinct. Browser: 3 periods made 08-09, 08-16, 08-23 |
| T-REPEAT-06-2 limit of 8 | ✅ HTTP: 0, 9 and 100 periods → 400 "You can repeat a plan for 1 to 8 periods at a time. (E-REPEAT-010)"; a start inside the source → E-REPEAT-003; 2027-13-45 → E-REPEAT-002. Each refusal logged |
| T-REPEAT-06-3 existing period skipped and named | ✅ HTTP: period 2 made first, then the list marked it `exists` with its plan; the run skipped it and made 1, 3 and 4 |
| T-REPEAT-06-4 failure on a period | ✅ 5 and 6 made, then a forced failure on 7 (`test_fail_at = 1`): E-REPEAT-006, no plan for that date, 5 and 6 stayed. "Period 4 is not tried" is the app's runner, proved in the unit test (the server makes one period per request) |
| T-REPEAT-06-5 "repeated from" / "repeated to", deleted source | ✅ HTTP and browser: the source lists its 4 plans with dates and open-mark counts; a copy says "Repeated from <plan>" and opens its source; after the source was deleted the copy's history answered `exists: false` |
| Preview unchanged by the refactor | ✅ default start 2027-06-14; a taken name gets " 2"; overlap and bad date refused with the same codes and words as before |
| Other account / unknown plan / no token | ✅ other account: "Not Found"; unknown plan 404 "Plan not found"; no token 401 |
| Suites | ✅ `npm test` 1,127 of 1,127 · `tsc` clean · no console errors. Workflow tests and Playwright not run |

- **Differences from the story:**
  - "The plan list shows each plan's needs-review total": done in the History list (`N to review` per plan), not in the main plan switcher, which still shows names only.
  - The 8-period limit is enforced by the period-list endpoint, not by the single-plan endpoint (683), which stays one period.
  - One shared correlation id covers the events of a batch; there is no single "batch" event.
- **Cleaned up:** all test plans, marks and `plan_repeat` rows, and every scratch function deleted. Event-log rows kept.
- **Learning:** a `where` using `~` (text match) failed with "Not Found" in this workspace; and a sentinel `-1` kept in an id list must never be looped over by a `db.del` (it was deleted as if it were a real id and failed). Delete from the query's own result list.
