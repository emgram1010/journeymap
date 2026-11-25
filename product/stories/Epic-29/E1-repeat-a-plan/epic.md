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

