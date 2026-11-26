# EPIC REPEAT-2 — Choose what a repeat carries; archive and delete a plan

**Status:** ✅ Built and tested live (2026-11-26). Waiting for the founder's check on the live site.
**Depends on:** REPEAT-1 (done, gate passed 2026-11-26)
**Model:** Fable 5.2 (asked for by the founder on 2026-11-26). The delete path is the risky part: it gets a live fixture test before it is trusted.
**Asked for by the founder, 2026-11-26**, after the first real repeat: "is there a reason I can't archive or delete the plan?" and "a check mark to carry the people, the jobs and the assignments".

## 1. Goal

1. When repeating a plan, the planner **chooses what comes along**: people, jobs, assignments. All three are ticked by default (today's behaviour).
2. A plan can be **archived and restored** from the screen (the server could already do it; the button was missing).
3. An **admin** can **delete** a plan that has no history. Deleting a repeated copy frees its date, so the plan can be repeated to that date again.

## 2. What exists today (checked 2026-11-26)

| Fact | Where |
|---|---|
| A repeat always copies people, days, jobs and slots | `functions/repeat/build_plan.xs`, `plan_work.xs`, `create_plan.xs` |
| A start date inside the source plan's range is already refused (E-REPEAT-003) | `functions/repeat/period_dates.xs` |
| Archive and restore exist on the server, with no button | `apis/planner/527_workspace_workspace_id_archive_POST.xs` |
| The plan list hides archived plans unless asked (`include_archived`) | `apis/planner/524_workspace_GET.xs` |
| A plan delete was written in PLN-3 and **never pushed**; it only knows 3 of the 13 tables a plan now owns | `functions/planner/delete_workspace_cascade.xs` |
| "Has history" counts **any job** as history, so a repeated copy could never be deleted | `functions/planner/workspace_has_history.xs` |
| A repeat to a date that was already made answers "already there", even if that copy is archived | `plan_repeat` unique (source plan, start date) |
| The founder's first live repeat (plan 145 → 204) copied 0 people and 0 jobs because plan 145 is empty. Not a bug | `plan_repeat` row 36 |

## 3. Rules

**Choices**
- Three choices: **people**, **jobs**, **assignments** (the days and the scheduled slots). Leaving a choice out is the caller's explicit "skip"; saying nothing copies everything, exactly as before.
- No people means no assignments (a slot needs someone's day). The server enforces it; the screen greys the box.
- Jobs without assignments: the jobs are made and every step waits in Unscheduled.
- The preview and the copy use the same rule (`repeat/build_plan`), so they cannot disagree.

**Archive**
- Any planner may archive or restore. Archiving hides the plan and stops edits; nothing is removed.

**Delete**
- **Admin person only.** A member, or any AI identity, is refused.
- **Only a plan with no history.** A plan is refused (and the answer says "archive it instead") when any of these is true:
  - one of its days was ever published to live;
  - any work was recorded on its jobs;
  - it holds a job from a customer order, an exception link or an unmatched order line;
  - customer orders are routed into it.
- A draft plan with jobs and slots that nobody published **can** be deleted. That is the "wrong repeat, do it again" case.
- Delete removes the plan and everything that hangs off it in **one all-or-nothing write**, children first, each row by its own id.
- Deleting a repeated copy also removes its `plan_repeat` row, which **frees the date**.
- Plans that were repeated **from** the deleted plan keep working; their history says the original no longer exists (REPEAT-1 story 06 already handles this).
- The screen asks first and names what will be removed.

## 4. Do not break

- A repeat with nothing unticked behaves exactly as REPEAT-1 (same counts, same rows, same marks).
- The AI tool `plan_repeat` is unchanged: it copies everything and cannot skip, archive or delete.
- No published day, publication or activity-log row is ever deleted.
- No other plan's rows are touched by a delete.
- No column is added to an existing table. No new table.

## 5. Non-goals

- Deleting a plan that has history. Archive is the answer.
- "Undo" for a copy that was already published.
- Deleting from an AI tool or the connector.
- Bulk delete.

## 6. Governance

| Item | Decision |
|---|---|
| Tables | None added or changed. Rows are deleted from: `planner_task_review`, `planner_task_start_override`, `planner_task_work_task`, `planner_task`, `planner_timeline`, `work_item_line`, `work_item_time_window`, `work_task`, `work_item`, `planner_agent`, `planner_workspace_map`, `plan_repeat` (the copy's own row), `planner_workspace` |
| Validation | Delete refused with a plain sentence that says what to do instead. The user's typing is never lost (there is none: delete is a confirm) |
| Error codes | `E-P3A-001` (existing: work recorded, archive instead) · new `E-P3A-004` (customer orders or exception work) · new `E-P3A-005` (orders are routed into this plan) · `E-USR-*` for a non-admin (existing) · `E-COP-025` for an AI (existing) |
| Events | `plan.deleted` success (with the counts of rows removed) · `plan.delete_refused` rejected (with the code) · `plan.delete_failed` failure · existing `archive_workspace` / `restore_workspace` · the repeat event carries the three choices |
| Re-count | After the delete, the endpoint counts what is left under the plan id; anything above 0 is logged as a failure (never trust the function's own tally) |

## 7. Stories

| File | Story |
|---|---|
| `US-REPEAT-2-01-choose-what-comes-along.md` | People, jobs and assignments boxes on the repeat window; the server applies them |
| `US-REPEAT-2-02-archive-and-restore.md` | Archive a plan and bring it back, from the screen |
| `US-REPEAT-2-03-admin-deletes-a-plan.md` | An admin deletes a plan that has no history; refused otherwise |
| `US-REPEAT-2-04-delete-then-repeat-again.md` | Deleting a copy frees its date; the screen confirms and names what goes |

## 8. Completion gate

- A repeat with all three ticked equals a REPEAT-1 repeat (same counts).
- Jobs unticked: people and days come, no jobs. People unticked: no people, no days, no slots; jobs still come.
- Archive hides a plan; restore brings it back.
- A member cannot delete; an admin can.
- A plan with a published day is refused with "archive it instead".
- A deleted plan leaves **zero** rows behind in every table listed in §6, and no other plan lost a row.
- After deleting a copy, the same plan repeats to the same date again.
- Existing suites green. Test Results filled in.

## 9. Test Results

### All four stories (2026-11-26, Fable 5.2)

- **Tests written first:** `repeatChoicesModel.test.ts`, 8 tests: the three boxes and their request, "no people means no assignments", the plain line, the archived filter, the admin-only rule, the confirm's sentences, and two tests that read the server source (skip flags decided in one place; delete = admin person + no history + one transaction + every table, history tables never deleted).
- **Built (backend, all live):**
  - `repeat/build_plan` (459), `repeat/plan_work` (472), `repeat/preview` (515), `repeat/create_plan` (465), endpoints 682 and 683: three **skip** flags. People off forces assignments off on the server. The choices are returned by the preview and stored with the repeat's counts.
  - `planner/delete_check` (524, read-only): may this plan be deleted, what would go, and does it free a repeat date.
  - `planner/delete_workspace_cascade` (525): the PLN-3 draft rewritten for all 13 tables, one transaction, every row by its own id.
  - `DELETE workspace/{id}` (688) and `GET workspace/{id}/delete-check` (689).
  - Catalog: `E-P3A-004`, `E-P3A-005`, `E-P3A-006`; `E-P3A-001`'s explanation updated (a job alone is no longer "history").
- **Built (app):** three boxes on the repeat window ("What comes along"); "Show archived" in the plan list with an "(archived)" label; "Archive plan" / "Restore plan" in Workspace Settings; "Delete plan" for admins only, with a confirm that shows the server's own counts or its reason for refusing.
- **Live test:** `tests/repeat2_probe.py` over real HTTP in the test account, as an admin and as a member. Phase 1: 23 of 23. Phase 2: 14 of 14.

| Test | Result |
|---|---|
| T-REPEAT2-01-1 all ticked = REPEAT-1 | ✅ copy of plan 115: same people, days, jobs (14) and slots (7) as the preview |
| T-REPEAT2-01-2 jobs unticked | ✅ preview and copy: 0 jobs, people and days kept, no "no jobs" warning |
| T-REPEAT2-01-3 assignments unticked | ✅ preview and copy: 14 jobs, people kept, 0 days, 0 slots; the new board has no days, slots or review marks |
| T-REPEAT2-01-4 people unticked | ✅ sent with assignments still on: server made 0 people, 0 days, 0 slots and reported assignments off; nobody named as "left out" |
| T-REPEAT2-01-5 preview equals copy | ✅ for each of the four choices |
| T-REPEAT2-02-1 / 02-2 archive, restore, list | ✅ archived plan leaves the list, appears with `include_archived`, keeps its people and days, returns on restore |
| T-REPEAT2-03-1 full delete | ✅ plan 205: 1 person, 1 day, 14 jobs, 28 steps, 7 slots, 7 slot links, 7 review marks, 1 map link, 1 repeat row deleted; `left_behind: 0` |
| Independent re-count | ✅ every row id of plan 205 was recorded before the delete (14 jobs, 28 steps, 7 slots); a separate count by those ids afterwards found 0 in all 13 tables |
| T-REPEAT2-03-2 neighbour untouched | ✅ plan 115's counts identical before and after 6 deletes |
| T-REPEAT2-03-3 member refused | ✅ 4xx "Only an account admin can do that. (E-USR-001)"; nothing deleted |
| T-REPEAT2-03-4 AI refused | ⚠️ not run live (no AI login was set up for this run). Covered by the source test: the endpoint calls `copilot/assert_person_only`, the same guard proved live in REPEAT-1 story 05 |
| T-REPEAT2-03-5 published plan refused | ✅ plan 115: 400 "This plan has work recorded against it. Archive it instead. (E-P3A-001)", logged as `plan.delete_refused` with what was found |
| T-REPEAT2-03-6 orders / order route | ⚠️ the check counted plan 115's 9 order jobs and 2 unmatched lines, but E-P3A-001 outranks them, so E-P3A-004 and E-P3A-005 were never the answer shown. Not proved alone |
| T-REPEAT2-03-7 other account | ✅ delete and delete-check both 404 |
| T-REPEAT2-04-1 delete, then repeat again | ✅ same plan, same date: a new plan was made |
| T-REPEAT2-04-2 original deleted | ✅ the copy's board loads; its history says `exists: false` |
| T-REPEAT2-04-3 delete check | ✅ draft copy: allowed, counts, frees the date. Plan 115: not allowed, E-P3A-001 |
| Events | ✅ `plan.deleted` (warn, with the counts and `left` all 0) and `plan.delete_refused` in the log |
| Browser | ✅ member: Archive shown, Delete not shown. Admin: Delete shows the confirm ("This removes 2 people, 1 day, 0 jobs and 0 slots. This cannot be undone."). Repeat window: unticking People greys Assignments and the preview drops to 0 people, 0 days. Confirming a delete and an archive was not clicked in the browser (proved over HTTP) |
| Suites | ✅ `npm test` 1,144 of 1,144 · `tsc` clean. Playwright and workflow tests not run |

- **Differences from the stories:**
  - The repeat window does not show a per-job list when Jobs is unticked, and no "left off" list when People is unticked: it was a choice, not a loss.
  - Unticking Jobs with Assignments on still copies the days and any free-standing slot; slots that belonged to a job are named as not created.
  - The AI tool `plan_repeat` was not changed: it sends no choices, so it copies everything.
- **Cleaned up:** every plan the probe made was deleted by the new endpoint itself (6 plans, nothing left behind); the scratch function is deleted. Event-log rows kept.
- **Known gaps:** E-P3A-004 and E-P3A-005 and the AI refusal are not proved live on their own. `planner/workspace_has_history` (any job = history) is now unused by the plan delete and still used by nothing else; left in place.
- **Founder's first repeat explained:** plan 145 "Item Turn Around" has no people and no jobs, so its copy (204) is correctly empty.
