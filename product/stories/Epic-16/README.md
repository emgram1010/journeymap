# Epic-16 — One row per role line

**Folder index**

| File | What it is |
|---|---|
| `START-HERE.md` | Read first. Context, reading order, hard limits, what "done" means. |
| `README.md` | This file. Why the epic exists and where it sits. |
| `EPIC-ROW-1-one-row-per-role-line.md` | The spec. Three stories, decisions, test plan, gate. |

**Status:** ✅ All three stories built 2026-10-31, same session as the design. Green across
typecheck / 650 unit / build / 47-spec parse, and zero e2e edits were needed (spec D-5 held).
**Outstanding:** the founder browser pass. One deviation recorded in the spec's §10.
**Depends on:** QUE-1 (Epic-15 — the Unscheduled grid, built 2026-10-30/31), EXC-2 (`JobPeekSheet`).
**Default model:** Sonnet 5.5 for all three stories. No Opus review pass — no write path (spec §6).

---

## Why this exists — the founder on the running app, 2026-10-31

QUE-1 built the Unscheduled grid, and the founder used it. Two things came back the same day:

1. **A job costs two rows.** A full-width job-title row, then the role line underneath it. When a
   job has exactly one role line — the common case in their real plan — half the height is header.
   *"Should we have it just in one line, somehow squeeze the role in the same row that you already
   have the task and details?"*

2. **Clicking the job name offers to create a new job.** It opens `JobsModal`, whose top half is
   the "+ New job" form. *"Why would we need to create a new job in unscheduled?"*

Both were found by looking at the screen, not by any check. On the same day, four rounds of green
typecheck, 650 unit tests, production build and 47-spec parse had found neither.

---

## What changes

```
   Today                                  Wanted
   ┌─────────────────────────────┐        ┌─────────────────────────────┐
   │ Bounce V3 · Moon bouncer…   │        │ Bounce V3 · … · Repair Tech │  ← one row
   ├─────────────────────────────┤        ├─────────────────────────────┤
   │ Repair Tech   3  45m  ✓     │        │ Bounce V3 · … · QA      …   │
   └─────────────────────────────┘        └─────────────────────────────┘
   two rows for one role line             one row each, job name in the row
```

- The visible job-header row goes away; `Job · Role` moves into the Role / Task cell.
- The per-job `<tbody>` **stays** — it carries no visual weight and 26 e2e locators scope to it
  (spec D-5). This is what keeps the epic small.
- The job name opens `JobPeekSheet`, the read-only job view already wired into this file for the
  exception chips. Job creation stays on the jobs list header.

---

## Where this sits

- **QUE-1** (Epic-15) built this grid, including the group header this epic removes. That epic's
  file is deliberately **not edited**; the supersession is recorded in this spec's §10.
- **EXC-2** gave the app one read-only job view. This epic reuses it rather than adding a second.
- **BOARD-1** owns `groupCardsByJob` in `boardModel.ts`. The new flatten function goes beside it,
  and depends on its ordering.
- Nothing is blocked by this. It is polish on the surface QUE-1 just built — the requirements /
  task-type / optimizer work in Epic-15 §4 is still the next real feature.
