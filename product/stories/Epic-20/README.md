# Epic-20 — START HERE. Manual start-time override (SCHED-2)

> ## ✅ BUILT AND LIVE (2026-11-05/06). See §7 for what is still open.
>
> Written 2026-11-05 (Sonnet 5) from a real support conversation (see §2) as documents only; the
> founder then said "push this and do the rest". Reviewed and built on Opus 5.5. Results are in the
> epic's §9, corrections to this plan in its §11, deviations in its §12.

| File | What it is |
|---|---|
| `README.md` | This file. Context, status, models, how to report. |
| `EPIC-SCHED-2-manual-start-override.md` | The spec. Stories with Gherkin, decisions, open questions, governance, test plan. |

---

## 1. Who you are working for

- **Product manager, not an engineer**, and the only support person. ADHD/INTP.
- **~5 short bullets per reply, one line each. No paragraphs.** `CLAUDE.md` 🔴 section.
- **A question is a question.** "Sounds good" is not approval to build.
- **Ask before any Xano push, schema change, delete, or anything outward-facing.**

---

## 2. Where this came from (2026-11-05)

Founder was checking the Nov 1-7 plan after TW-1 shipped. Sequence of findings, in order:

1. A job's time window (TW-1) doesn't show on the board card itself — only in the Jobs modal,
   once a row is expanded. (Answered — working as built, not a bug.)
2. Founder added a window to a real job. The chip showed correctly. But opening that job's
   **Planned Start** field showed 8am and couldn't be edited — "as a user it would be natural
   to open the job and edit." That field has **always** been read-only: it is computed from the
   day's timeline start time + step order (`SCHED-1`, confirmed in `EditModal.tsx` and
   `FT-SCHED-1-10`), never stored per task.
3. Founder asked for a story to let a job's/task's schedule be edited directly, in both the
   **Plan module** and the **Execution module**, "within the agent's workspace."
4. Clarified and agreed: **planner edits; performer views only** — performers log activity
   (started/done/blocked), never set schedule or report variance (PRD architecture rule). The
   Execution module's job here is to keep showing the real, possibly-overridden time — which it
   already does today, read-only (`TodayScreen.tsx`'s `plannedStartLabel`).

**Translated into scope:** a new, optional, per-scheduled-task override of the computed start
time. Nothing is removed — a task with no override behaves exactly as it does today.

---

## 3. Why this isn't in the product today (verified 2026-11-05)

- `planner_task` has no start-time column at all — PLN-7's derivation (`start_time` of the day
  + cumulative `duration_minutes` of everything scheduled before it) is the **only** source.
  `FT-SCHED-1-10` pins this on purpose: "slots take their planned start from the timeline's start
  plus the cumulative durations before them."
- `EditModal.tsx`'s "Planned Start" input is hardcoded `disabled readOnly` for a scheduled task,
  with the caption *"Computed automatically from the timeline's start time and step order."* This
  was a deliberate V1 choice in `SCHED-1`, not an oversight.
- This is a **different thing from TW-1's time window**. A window is an *allowed range*
  (soft, not enforced). This epic is the *actual clock time the job runs* — today fully derived,
  never overridden.

---

## 4. 🔴 The place this epic can hurt something

**The start-time rule is implemented THREE times** (corrected by the Opus review, 2026-11-05 —
the first draft said "four readers" and guessed wrong about which):

1. `functions/planner/derive_tasks.xs` — the planner side. Every planner endpoint (board 548,
   task list 546/547, place 543, reorder 544, PATCH 545, create 542) calls this one function.
2. `webapp/protype-2/src/perform/performerView.ts` — the performer side, computed in the browser
   from the frozen snapshot's `seq` + `scheduled_minutes` and the timeline's `start_time`.
3. `functions/variance/task_report.xs` — the variance "planned start", same inputs as #2.

**The publish snapshot stores no start time at all** (`live/build_publication` freezes order and
minutes only). So for the performer and variance to see an override, the override itself must be
frozen into each snapshot item — which changes the canonical hash line → **`publication|v3`**,
exactly the TW-1 pattern (server + TypeScript twin, both pinned). Old v1/v2 rows are never re-hashed.

**House rule (CLAUDE.md, LOG-1 precedent):** one shared rule. Server: a new pure function used by
#1 and #3. Browser: the same rule in `performerView.ts`, pinned to the server by shared golden
cases.

**Good news found while scoping this:** `plan_change_log.change_type` already has a `"moved"`
value. Logging a live-day override does **not** need TW-1's Health-page workaround — the real
table already fits.

Read **CLAUDE.md's XanoScript section** before any backend story, same as always.

---

## 5. Models

| Story | Model | Why |
|---|---|---|
| US-SCHED-2-01 — the side table | **Opus 5.5** | Schema push. |
| US-SCHED-2-02 — override CRUD + the shared "effective start" function | **Opus 5.5** | Touches the scheduling derivation and the publish-snapshot function (hash-sensitive). |
| US-SCHED-2-03 — planner UI (unlock the field) | Sonnet 5.5 | Form + save call. Low blast radius. |
| US-SCHED-2-04 — downstream reads (board, publish, performer) use the shared function | **Opus 5.5** | Same reason as -02 — multiple existing readers, one of them hash-sensitive. |
| Review pass after -01/-02/-04 | **Opus 5.5** | CLAUDE.md: review after risky backend work. |
| Fixtures, doc touch-ups | Haiku 5.5 | Mechanical — cheaper. |

---

## 6. How to report progress

- Edit each story's `**Status:**` line as you go, same convention as every other epic.
- Fill the Test Results section with a real result per ID. Not run = "not run," never "pass."
- Every deviation goes in the Notes section.
- Stage files **by name**.

---

## 7. Status

| Item | State |
|---|---|
| Epic written | ✅ 2026-11-05 (Sonnet 5), from the support conversation in §2 |
| Founder go-ahead to build | ✅ 2026-11-05 — "push this and do the rest" |
| US-SCHED-2-01 table | ✅ Live as table **142** (2026-11-05). Description added after push; trim validators confirmed intact |
| Opus review of the plan | ✅ 2026-11-05 (Opus 5.5) — corrections in the epic's §11 |
| US-SCHED-2-02, -03, -04 | ✅ Built, live, tested (Opus 5.5, 2026-11-05/06) — epic §9 |
| Real "Publish to live" with an override (performer screen) | ❓ Not run — needs a test day published |
| D-3 (what happens to later tasks) | ⚠️ Changed to **pin + flow** by the review — see epic D-3. Founder can reverse it |
