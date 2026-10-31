# Epic-15 — One list of jobs, one queue of unscheduled work

**Folder index**

| File | What it is |
|---|---|
| `START-HERE.md` | Read first. Context, reading order, hard limits, what "done" means. |
| `README.md` | This file. Why the epic exists, the vocabulary, where it sits. |
| `EPIC-QUE-1-jobs-list-and-unscheduled-queue.md` | The spec. Builder brief, stories, tests, governance, decisions. |

**Status:** ✅ All 7 stories built 2026-10-30, same session as the design; **Opus 5 review pass done
2026-10-31** (4 findings, 4 fixes — epic file §11). See the epic file's §1 status line for the
remaining honest caveats (built on Sonnet 5.5 throughout, including the story marked for Opus; no
e2e run; the founder has now driven the running app, but the drag gestures and the confirmation
dialog still want a human pass; nothing committed yet).
**Depends on:** BOARD-1 (the Jobs column and card drag — built 2026-10-28, committed `59b6654`).
**Default model:** Sonnet 5.5. Opus 5.5 for US-QUE-1-05 (the release/unschedule wiring) and a
review pass before the completion gate.

---

## Why this exists — the founder's reasoning, 2026-10-30

BOARD-1 put a **Jobs column** on the left of the planner: every card still waiting for a day,
grouped under its job, draggable straight onto an agent's day. It works. The founder then looked
at it with the next two features in mind and found the shape wrong for where the product is going:

> *"We are also going to add requirements to the task in the future … This will enable in the
> future an optimizer to assign a task to an agent based on certain criteria. With this context, I
> want to create a list of all the jobs … and I could go ahead and be able to filter by any type
> of criteria. So that's what the left column is for."*

Two separate things are being asked for, and today one surface is doing neither well:

| | Today | Wanted |
|---|---|---|
| **Left column** | Only jobs that still have work waiting for a day. A job fully placed, done, or sent disappears. | **Every** job in the plan, filterable by any criteria — a registry you browse and search. |
| **Bottom drawer** | "Backlog" — plain ad-hoc tasks only. Collapsed by default. Empty in practice. | **"Unscheduled"** — the one queue of work ready to be placed, open by default, resizable. |

The optimizer is what makes the queue a *place* rather than a filter: it needs a pool to assign
from. That is the strongest argument for this shape, and it is why "just add a filter to the
existing column" is not the answer.

**Nothing about requirements, task types, agent capabilities or the optimizer is built here.**
This epic is the surface those features will land on. See §4 of the spec.

---

## The flow, settled 2026-10-30

```
   Jobs list (left)             Unscheduled (bottom)  ──drag──▶  Agent's day (right)
   every job, view-only    auto-shows what has no day           placed work
   (find it, read its steps)                         ◀──── drag back, with a warning ────
```

**One direction only.** The founder was explicit: *"keep it from left to right … the left column
can only drag to the unscheduled. And the unscheduled, the user can drag from the unscheduled over
to the agents section."* The direct left-column → day shortcut BOARD-1 built **goes away**. See
D-2 and the honest cost in §8 of the spec.

**Resolved mid-build, 2026-10-30 (Q-1):** a role line shows in Unscheduled **automatically** the
moment it has no day — not behind a drag. So the jobs list is **view-only**: no drag, no Place…
there at all. That alone is what enforces left-to-right — the only place a role line can be
dragged onto a day is Unscheduled. See the spec's Q-1 and US-QUE-1-05 for the full reasoning.

---

## Vocabulary — use these words, do not invent others

- **Job** — one real run of a map's work ("Bounce V3 · Moon bouncer repair"). A `work_item`.
  One row in the jobs list.
- **Step** — one stage of that job for one actor row. A `work_task`. Shown when a job row is
  opened; never dragged on its own.
- **Role line** — a job's steps for **one actor row**, the thing that actually gets placed
  (`work_item_id::lens_key`, what endpoint 559 calls a card and 583 schedules). Called a *card*
  in BLK-1/BOARD-1 code; **"role line" is the word for the founder and the UI**, because "card"
  means a rectangle on screen to everyone else.
- **Unscheduled** — every role line and ad-hoc task with no day yet. Shows automatically, not
  behind a release step (Q-1, resolved 2026-10-30). Replaces the word "Backlog" everywhere in the
  planner UI.
- **Scheduled** — on a specific agent's specific day.

**Not "Unassigned."** The founder first proposed that word, then corrected to "unscheduled" in the
same conversation. It is the right call and the reason matters: these lines already carry a role
from the map ("Repair Tech"), so they are not unassigned — they have no *day*. Keeping the two
words distinct leaves "assigned" free for what the optimizer will do later. See D-1.

---

## Where this sits

- **BOARD-1** built the column, the drag, the day sequence and `boardModel.ts`. This epic reshapes
  that surface; most of the model code is reused, not rewritten.
- **BLK-1** made the role line the schedulable unit (559 / 583). Unchanged. D-3 depends on it.
- **EXC-1 / EXC-2** gave jobs parents and children ("from #133", "N sent on"). Those chips move to
  the new job row as-is. A job's children are a *different* nesting from its steps — see D-5.
- **RPT-1** moved Plan vs Action out of the Jobs modal. This epic finishes that direction: the
  modal's job **list** becomes redundant once the column shows every job.
