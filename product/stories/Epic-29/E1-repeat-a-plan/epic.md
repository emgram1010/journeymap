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
