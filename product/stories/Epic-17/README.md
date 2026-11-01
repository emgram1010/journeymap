# Epic-17 — Quantities, and where the units went

**Folder index**

| File | What it is |
|---|---|
| `START-HERE.md` | Read first. Context, hard limits, the one story that needs approval. |
| `README.md` | This file. Why the epic exists and where it sits. |
| `EPIC-QTY-1-quantities-and-where-the-units-went.md` | The spec. Three stories, decisions, test plan, gate. |

**Status:** ✅ **All three stories built.** -01/-02 on 2026-10-31 (frontend only; -02 needed no
backend at all). **-03 pushed live 2026-11-01** on the founder's explicit approval — endpoint 558
now returns `unit_total` / `units_moved_out`, with the tally logic proven on 21 real jobs in a
throwaway function *before* the live endpoint was touched. **Outstanding:** the founder reloading
the app, which is the only thing that confirms the column renders.
**Depends on:** ITEM-1 (`work_item_line`), EXC-1 (the exception spawn), EXC-2 (`JobPeekSheet`).
**Default model:** Sonnet 5.5 for the two frontend stories; **Opus 5.5** for the backend one.

---

## Why this exists — the founder, 2026-10-31

Having just worked out what a parent/child job split actually is, they asked the obvious next
question and the right one:

> *"I don't see no quantities on the job, so I don't know what units we're talking about. I also
> don't know which units are going on the parent path and what units are going on the sub job
> path. Rather than recreate the wheel, is there already a way of representing this?"*

**Yes — and it is already built.** `work_item_line` has stored quantity per item type per job
since ITEM-1, and EXC-1's split already records which units moved to the child and what the parent
kept. None of it reaches the planner's screen. **This epic is display only.**

It is also the standard **ERP work-order-split** pattern — a parent order keeps the good quantity,
a child rework order carries the defective units. The founder reached that model on their own, so
the epic borrows its conventional phrasing (`10 ordered · 8 here · 2 moved out`) instead of
inventing new words.

---

## The shape of the work

```
   Job detail panel (JobPeekSheet)        Jobs column rows
   ────────────────────────────────       ──────────────────────────
   US-QTY-1-01  units per job            US-QTY-1-03  unit count per row
   US-QTY-1-02  what moved, where to     🔴 needs a Xano push — ASK FIRST
   ✅ frontend only, endpoint exists
```

The asymmetry is the whole story: the detail panel opens **one** job, so it can just call
`getWorkItemLines`. The column renders **every** job, so the same trick becomes an N+1 on the
founder's main screen — refused (spec D-3). Quantities reach the column through the list endpoint
or not at all, and extending that endpoint is a Xano push.

---

## Where this sits

- **ITEM-1** owns `work_item_line` and `item_type`. Unchanged — this epic reads them.
- **EXC-1** owns the split and already computes `moved_lines` / `parent.lines_after`. Unchanged.
- **EXC-2** owns `JobPeekSheet`, the one read-only job view. Both frontend stories land there,
  rather than building a second place to look at a job.
- **QUE-1 / ROW-1** (Epic-15, Epic-16) built and reshaped the surfaces this displays into.
- Nothing is blocked by this epic.
