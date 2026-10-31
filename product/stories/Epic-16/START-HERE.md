# START HERE — Epic-16, for the AI session that builds it

**You are picking up work that was designed but not built.** Everything you need is in this
folder. Read this file end to end before you open anything else. The founder is one non-engineer
with no team: a session that guesses costs them a day they do not have.

**Written:** 2026-10-31, from the founder's own observations using the running app the same day.
**Status when written:** nothing in ROW-1 is built. No code, no test.
**Epic in this folder:** `EPIC-ROW-1-one-row-per-role-line.md` — that file is your spec.

---

## 1. What you are building, in five sentences

The Unscheduled list at the bottom of the planner currently spends two rows on each job: a
full-width row with the job's name, then the role line underneath it. The founder wants **one row
per role line**, with the job's name carried in the row itself, because a job with a single role
line is the common case in their plan and the header was costing a row nearly every time. Second,
clicking a job's name there currently opens the modal whose top half is the "+ New job" form —
it should open the **read-only** job view instead, which already exists in that same file.
**This is frontend only: no endpoint, no schema, no new state, no write path.** Everything else
about the grid — the Stages panel, the seam, the Place… flow, the drag to a day — stays exactly
as QUE-1 left it.

It is generic. "Moon bouncer repair" is the founder's test data, not the feature. Never write the
words repair, bouncer, canopy or rental into code, a column, a label or a message.

---

## 2. Read in this order

| # | Read | Why |
|---|---|---|
| 1 | `CLAUDE.md` (repo root) | How to work here and how to talk to the founder. This epic is frontend-only, so the XanoScript list barely applies — the **Response format** and **Safety rules** sections apply in full. |
| 2 | This file | Context, what is settled, what you must not do. |
| 3 | `product/stories/Epic-16/README.md` | Why the epic exists, with a before/after sketch. |
| 4 | `product/stories/Epic-16/EPIC-ROW-1-one-row-per-role-line.md` | **The spec**: three stories with Gherkin and status, decisions, test plan, gate. |
| 5 | `product/stories/Epic-15/EPIC-QUE-1-jobs-list-and-unscheduled-queue.md` — §2, §11 and US-QUE-1-02 | The grid you are changing, and the two e2e traps that session fell into with these exact specs. |
| 6 | `webapp/protype-2/src/planner/components/BacklogDrawer.tsx` | The file. Read the Unscheduled table and the `JobPeekSheet` wiring before writing. |

Nothing else. Do not open other epics, and do not touch `product/validation-publish-execution/`.

---

## 3. What is already settled — do not reopen these

1. **Flat, one row per role line, no group header.** The founder was asked directly — "always
   flat, or keep a group header only when a job has 2+ role lines?" — and chose flat.
2. **The job name opens the read-only job view**, not the new-job modal. Reuse `JobPeekSheet`,
   already imported and wired in that file for the exception chips.
3. **Job creation stays on the jobs list header.** Unscheduled is a queue of work to place.
4. **The job's name repeats on each of its role lines**, and those lines stay adjacent. Whether
   to dim the repeats is Q-1 — answered from the real screen afterwards, not guessed now.
5. **Plain ad-hoc backlog tasks are untouched.**

---

## 4. Hard limits

- **No backend.** No new endpoint, no schema change, no new status, no delete. If a story seems to
  need one, the story is wrong — stop and ask.
- **Keep the per-job `<tbody data-testid="unscheduled-job-group">`.** Remove only the visible
  header `<tr>` inside it. 26 e2e locators across three specs scope themselves to that `<tbody>`;
  it has no visual weight, and dropping it turns a small change into a three-spec rewrite. This is
  spec D-5 and it is the single most important line in this folder.
- **Put the flattening in `boardModel.ts`, not in JSX.** A pure function beside `groupCardsByJob`,
  with the unit tests from §7. That is how this repo tests logic.
- **Do not fabricate test results.** Every e2e spec skips without `E2E_AUTH_TOKEN`. Write them,
  say plainly they were never run, never report a skip as a pass.
- **Do not edit the Epic-15 files**, even though this epic supersedes that grid's group header.
  The supersession is already recorded in this epic's §10. Ask before touching Epic-15.
- **Delete `onOpenJob` if it ends up unused** — prop and `PlannerApp.tsx` wiring both. No shims.

---

## 5. Models, per story

| Story | Model | Why |
|---|---|---|
| US-ROW-1-01 | Sonnet 5.5 | A pure transform plus a markup change. The spec is detailed. |
| US-ROW-1-02 | Sonnet 5.5 | Swapping one click target to a handler that already exists. |
| US-ROW-1-03 | Haiku 5.5 is enough | Confirming locators still resolve; expect near-zero edits if D-5 held. |
| Review pass | **Not required** | No write path anywhere in this epic — the worst failure is a row rendering wrong. Tell the founder that is the reason, rather than skipping it silently. |

Tell the founder which model to switch to **before** writing code. You cannot switch models
yourself.

---

## 6. What "done" means

The gate is §8 of the spec. In short: three stories built, the five unit cases plus the full suite
and `tsc` and `build` green, `playwright test --list` clean with the three specs confirmed by
reading to still resolve, and **a founder browser pass on their real plan**.

That last one is not a formality here. Both defects this epic fixes were found by the founder
looking at the running app, on a day when every automated check was green. Ask them to look before
you call it done.

**Then stop and wait.** Do not start on requirements, task types or the optimizer — those are
Epic-15 §4 and need the founder's go-ahead of their own.
