# START HERE — Epic-15, for the AI session that builds it

**You are picking up work that was designed but not built.** Everything you need is in this
folder. Read this file end to end before you open anything else. The founder is one non-engineer
with no team: a session that guesses costs them a day they do not have.

**Written:** 2026-10-30, from a design conversation with the founder the same day.
**Status when written:** nothing in QUE-1 is built. No code, no test.
**Epic in this folder:** `EPIC-QUE-1-jobs-list-and-unscheduled-queue.md` — that file is your spec.

---

## 1. What you are building, in six sentences

The planner's left column today lists only work still waiting for a day; a job that is finished,
sent, or fully placed vanishes from it. The founder wants that column to become a **list of every
job in the plan**, which a filter bar will later let them slice by any criteria — because
requirements, task types and an auto-assigning optimizer are coming, and they need a registry to
act on. The bottom drawer, today called "Backlog" and collapsed, becomes **"Unscheduled"**: open
by default, resizable, and the single queue of work ready to be placed. Work now moves strictly
**left to right** — jobs list → Unscheduled → an agent's day — with a drag back down that
unschedules, behind a friendly confirmation. Opening a job row shows its details and its steps,
the way a Trello card shows its checklist or a Jira story its subtasks. **This epic is frontend
design only: no new endpoint, no schema, no requirements, no optimizer.**

It is generic. "Moon bouncer repair" is the founder's test data, not the feature. Never write the
words repair, bouncer, canopy or rental into code, a column, a label or a message.

---

## 2. Read in this order

| # | Read | Why |
|---|---|---|
| 1 | `CLAUDE.md` (repo root) | How to work here, how to talk to the founder, and the live-verified traps. This epic is frontend-only, so the XanoScript list matters less — the **Response format** and **Safety rules** sections still apply in full. |
| 2 | This file | Context, what is settled, what you must not do. |
| 3 | `product/stories/Epic-15/README.md` | The folder, the vocabulary, the flow diagram. |
| 4 | `product/stories/Epic-15/EPIC-QUE-1-jobs-list-and-unscheduled-queue.md` | **The spec**: builder brief, 7 stories with Gherkin and status, test plan, governance, decisions, completion gate. |
| 5 | `product/stories/EPIC-BOARD-1-planner-board-redesign.md` — sections 2, 4 and 9 | What BOARD-1 built two days earlier, which of its decisions still hold, and what it left untested. You are reshaping its surface. |
| 6 | The files in the epic's **Builder brief → Read first** list | The code you are changing. Read before writing. |

Nothing else. Do not open other epics, and do not touch `product/validation-publish-execution/`.

---

## 3. What is already settled — do not reopen these

The founder decided each of these in conversation on 2026-10-30. They are decisions, not options.

1. **The word is "Unscheduled," not "Unassigned."** They proposed "Unassigned" first and corrected
   themselves. A role line already carries a role; what it lacks is a day.
2. **One direction only.** Jobs list → Unscheduled → agent's day. The direct column-to-day drag
   that BOARD-1 shipped is removed. Asked and answered: *"for now, keep it from left to right."*
3. **A row is a job**, and opening it reveals its steps. The founder's own analogy: a Trello card
   opening to its checklist, a Jira story to its subtasks.
4. **A warning before unscheduling.** *"First go ahead and provide a friendly warning pop-up to
   inform the user that they're about to unschedule a job, and if they really want to move forward
   with it or cancel it."* Confirm first, act second.
5. **The bottom drawer is fixed and adjustable** — open by default, still resizable.
6. **Requirements, task types, agent capabilities and the optimizer are explicitly later.**
   *"Let's hold off on that one. For right now, let's go ahead and just do the refactoring."*
   Build no field, no column and no picker for them. §4 of the spec records the thinking so the
   next session does not have to re-derive it.

---

## 4. Hard limits

- **No backend.** Every story is served by endpoints that already exist: 559 (`listBacklogWork`),
  583 (`scheduleCard`), `listWorkItems`, `unscheduleWorkTask`. If a story seems to need a new
  endpoint, the story is wrong — stop and ask.
- **No schema change, no new status, no delete.** Unscheduled shows every role line with no day
  automatically — there is no "released" state to persist (Q-1, resolved mid-build; see D-8).
- **Do not invent a second rule for unscheduling.** `unscheduleWorkTask` already refuses a
  published day and work that has been recorded against. Render its sentence; never pre-judge it.
- **Do not fabricate test results.** Every e2e spec in this repo skips without `E2E_AUTH_TOKEN`.
  Write them, say plainly they were never run, and never report a skip as a pass.
- **Do not edit documents outside this folder** without asking — including the BOARD-1 epic, even
  where this epic contradicts it. Note the contradiction in your Notes instead.

---

## 5. Models, per story

| Story | Model | Why |
|---|---|---|
| US-QUE-1-01, -02, -03 | Sonnet 5.5 | Layout, rename, data-source swap. The spec is detailed. |
| US-QUE-1-04 | Sonnet 5.5 | Expand/collapse and the role-line rule. Pure, testable. |
| US-QUE-1-05 | **Opus 5.5** | The unschedule wiring — the one place this epic can lose a founder's real work. |
| US-QUE-1-06 | Sonnet 5.5 | The confirmation dialog. |
| US-QUE-1-07 | Haiku 5.5 is enough | A static filter-bar shell with nothing wired. |
| Review pass | **Opus 5.5** | Before the completion gate, per CLAUDE.md. ✅ Done 2026-10-31 on Opus 5 — 4 findings, 4 fixes, epic file §11. |

Tell the founder which model to switch to **before** writing code for each story. You cannot
switch models yourself.

---

## 6. What "done" means

The completion gate is §9 of the spec. In short: all seven stories built, the pure model unit
tests green, full suite + `tsc` + build green, the e2e specs written (and honestly reported as
unrun), and a founder browser pass on their real plan — create a job, find it in Unscheduled,
place it, take it back off with the warning.

**Then stop and wait.** Do not start smoothing rough edges, and do not begin requirements or task
types. The founder said those come after: *"then we could go ahead and start smoothing out the
rough edges."*
