# EPIC REPEAT-2 — Choose what a repeat carries; archive and delete a plan

**Status:** 🚧 In build (2026-11-26)
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

_Filled in as each story is built._
