# Epic-14 — Follow the work you sent

**Folder index**

| File | What it is |
|---|---|
| `START-HERE.md` | Read first. Context, reading order, models, hard limits, what "done" means. |
| `README.md` | This file. Why the epic exists, the vocabulary, where it sits. |
| `EPIC-EXC-2-follow-sent-work.md` | The spec. Builder brief, stories, tests, governance, decisions. |

**Status:** 📝 Designed 2026-10-27. Nothing built.
**Depends on:** EXC-1 (phase 7) — built, Opus-reviewed, all four review findings fixed, but
**not yet committed** when this was written (see START-HERE §3).
**Default model:** Sonnet 5.5 (see START-HERE §5 for the per-story table).

---

## Why this exists — the founder's test, 2026-10-27

The founder ran EXC-1 end to end on their own maps:

1. Linked `item-turnaround` → *Triage Damages* to a new map, `Moon bouncer repair` (6 stages).
2. Created a job ("TurnAround", #125) with one Moonbouncer and put it on a teammate's day.
3. From the planner, sent the Moonbouncer to repair → child job #126 was created correctly
   (1 Moonbouncer, 6 steps, a note on the parent step, every event logged, no errors).
4. Then asked: *"once I executed the exception … I wasn't able to see its stages. Is that
   currently supported?"*

It was not. What EXC-1 left behind:

| Where | Today | Gap |
|---|---|---|
| **Execution** — the performer's step screen | A chip "1 → #126" under *Send to…* | It is a `<span>`. Tapping does nothing. No way to see the child's steps or progress. |
| **Execution** — a child job's own steps | Nothing | The performer working the child sees no "came from #125 · Triage Damages". |
| **Planner** — the job detail's *Exceptions* panel | The same label chip, plus the stage it was sent from | Not clickable; no progress. |
| **Planner** — the job row | "from #125" / "N sent on" chips | "from" works. **"N sent on" opens the parent itself**, not the child (`showJob(job.id)`), so it only re-shows the label chips. |
| **Planner** — the child's own row | "Not started · 0 of 6 steps done" | Works, but only if you find the row yourself. |

The data is all there already: `GET work_item/{id}` (endpoint 555) returns any job's steps with
their status and the step text from the pinned version, and `GET work_item/{id}/links` (611)
returns parent and children. **This epic is almost entirely a read path and UI.**

---

## Vocabulary (same as phase 7 — do not invent new words)

- **Parent job** — the job work was sent *from*.
- **Child job** — the job created by a send (`work_item.parent_work_item_id` = parent). It runs on
  the **linked map**, pinned to that map's version at send time.
- **Sent work** — plain-language name for a child job, as seen from the parent. Use it in UI copy:
  "Sent work", not "child", not "exception job".
- **Came from** — plain-language name for the parent, as seen from the child.
- **Step** — one `work_task` (a stage × owner row). **Stage** — the map column it belongs to.
- **Progress** — finished steps ÷ all steps; finished = `done` or `skipped` (D-4).
- **Job view** (`JobPeekSheet`) — the read-only sheet this epic adds. One component, both modules.

---

## What is out of scope

- Doing the other job's work from the view (D-1 — read-only).
- A Health page change (Q-2 — proposed, not in scope unless the founder says so).
- Grandchildren trees (a child's own children are listed as chips in its view, one level at a
  time — no nested tree).
- Notifications ("your sent work finished") — a later epic.
- Any change to how sends are made (610), to table 140, or to statuses.
