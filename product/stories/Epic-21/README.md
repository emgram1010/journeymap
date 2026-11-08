# Epic-21 — START HERE. Planner UX: see it, place it, trust it (PUX-1 to PUX-4)

> ## ✅ BUILT (2026-11-07, Opus 5.5). Frontend only, no Xano change. See §6.
>
> Written after a walkthrough of the live planner with the founder; reviewed, then the founder said
> "execute". Each epic's §6 has its results and its last section its deviations.

| File | What it is |
|---|---|
| `README.md` | This file. Why, order, models, status. |
| `EPIC-PUX-1-one-job-panel.md` | Click a job anywhere → one panel for that job. |
| `EPIC-PUX-2-time-windows-everywhere.md` | See a job's time window wherever you decide. |
| `EPIC-PUX-3-week-at-a-glance.md` | Board opens on the right day; nothing hidden; names, not counts. |
| `EPIC-PUX-4-who-is-free.md` | Free hours while placing; a status on every job. |

---

## 1. Who you are working for

- Product manager, not an engineer, and the only support person. **ADHD, thinks visually.**
- **~5 short bullets per reply, one line each.** Pain → fix → win framing lands best.
- A question is a question. "Nice" is not a go. Ask before any Xano push.

---

## 2. Where this came from (2026-11-07)

The founder opened job "E2E card 1793637936807" on Jav's day and could not find its time window.
Walking the planner as a planner, four pains came out — each is one epic:

| # | Planner's pain | Epic |
|---|---|---|
| 1 | "Where's my job?" — clicking a job opens a list of **every** job; the board's step editor shows nothing about the job | PUX-1 |
| 2 | "When can this happen?" — a time window is only visible once it's already broken | PUX-2 |
| 3 | "Is my week right?" — board opens on Oct 27 for a Nov 1–7 plan; that job is invisible in the week view; week view shows counts only | PUX-3 |
| 4 | "Who's free?" — overload (Jav 11h 50m / 8h) only shows **after** assigning; no "what's left to schedule" at a glance | PUX-4 |

---

## 3. Verified facts the stories rely on (2026-11-07 — re-verify before building)

- **Two unrelated "job" screens today.** `JobsModal.tsx` is a list of all jobs; a Jobs-column click
  opens it with `focusJobId`, which only expands one row inside the list (BOARD-1 shortcut).
  `EditModal.tsx` ("Edit Step") edits the scheduled **slot** (`planner_task`) and knows nothing about
  the job beyond a provenance banner.
- **Everything the job panel needs already has an endpoint:** 555 `getWorkItem` (steps), lines
  (`getWorkItemLines`), activity (577), exception links, TW-1 time window (613–616). Where each step is
  scheduled can be derived from the board payload already in memory (`tasks` + `linked_steps` +
  `timelines`). **No backend change is expected in any of the four epics** — if one turns out to be
  needed, stop and ask.
- **Board start day:** `PlannerApp.tsx` sets `activeDay` from the plan's **first timeline** (line ~160 /
  ~258), and several fallbacks hard-code `'2026-10-13'`. The plan window
  (`planningWindowStart/End`) is never consulted.
- **Week view:** `ScheduleGrid.tsx` shows per-cell counts and load ("1 task", "11h 50m /8h"), only for
  days inside the plan window — a timeline outside it never appears.
- **Capacity data exists:** `planner_agent.daily_capacity_hours` → `agent.dailyCapacityHours`, and a
  per-day `dayLoad` is already computed for both views.
- **Time windows:** `listTimeWindows(workspaceId)` already loads every window in the plan once
  (`windowsByJob` in `PlannerApp`), so every surface can show them with no new request.

---

## 4. Build order and models

| # | Epic | Depends on | Model |
|---|---|---|---|
| 1 | PUX-1 One job panel | TW-1, SCHED-2 (live) | **Sonnet 5.5** — UI only, but it touches the busiest screen; Opus review after |
| 2 | PUX-2 Time windows everywhere | PUX-1 (the panel is where you edit) | Sonnet 5.5 |
| 3 | PUX-3 Week at a glance | none — can run in parallel with 1–2 (different files) | Sonnet 5.5 |
| 4 | PUX-4 Who's free | PUX-3 (same week view) | Sonnet 5.5 |

All four are **frontend only** in `webapp/protype-2/src/planner/`. Pure logic goes in model files
with tests (house rule: `boardModel.ts` / `timeWindowModel.ts` pattern), components stay thin.

---

## 5. How to report progress

- Edit each story's `**Status:**` line: `📋 Not started` → `🚧 In progress (model, date)` →
  `✅ Built (model, date)` or `🔴 Blocked — reason`.
- Every story is seen in Chrome on real data before it is called done (CLAUDE.md, UI rule).
- Fill each epic's Test Results with real results. Not run = "not run".
- Stage files by name. Never commit `product/learning-fixes.md`, `.obsidian/`, the frontend zip,
  or loose screenshots.

---

## 6. Status

| Item | State |
|---|---|
| Epics + stories written | ✅ 2026-11-07 (Opus 5.5) |
| Founder review | ✅ "execute" (2026-11-07) |
| PUX-1 … PUX-4 | ✅ Built + browser-verified on the real Nov 1–7 plan (Opus 5.5, 2026-11-07) |
| Not browser-verified | ⚠️ the drag-only hints (window fit, free hours) — native drag can't be driven by the test browser; logic unit-tested |
| Opus review pass | ✅ Done 2026-11-07 — 4 bugs found and fixed, see §7 |
| e2e specs | Two updated for the panel (`exceptions`, `follow-sent-work`); they compile but skip without `E2E_AUTH_TOKEN` |

---

## 7. Opus review pass (Opus 5.5, 2026-11-07)

Re-read every PUX change looking for real bugs. Four found, all fixed, `npm test` 784/784, `tsc`, build clean.

| # | Bug | Severity | Fix |
|---|---|---|---|
| R-1 | Switching jobs inside the panel (exception chip, parent link, another Jobs-column click) kept the child editors mounted: a time window mid-edit stayed open **and its Save would write to the NEW job**. Same risk for an open exception sheet. | 🔴 data | `JobPanel` keyed by job id → everything remounts per job. Browser-verified: editing job 6807's window, then opening 1793645330844, shows a clean "Add time window". |
| R-2 | "Today" came from `toISOString()` — UTC. In the US evening the board would open on tomorrow. | 🟠 | `localToday()` in `boardModel.ts`, unit-tested with a 21:30 case. |
| R-3 | Esc closed the whole panel even while Edit Step, the overload question or the exception sheet was open on top — losing what was typed in the panel. | 🟠 | Esc is ignored while a modal / alert dialog / exception sheet is open. |
| R-4 | While dragging an existing card, its own day counted it twice, so that column showed "over" falsely. | 🟡 | The dragged card is subtracted from its own column's load. |

Looked at and left as is: a second overload question arriving before the first is answered would
replace it (the dialog's backdrop blocks the board, so it can't happen by hand); the ExceptionSendPanel
`links` request shows twice in dev (React StrictMode — same as before PUX-1).
