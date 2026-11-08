# Epic-19 — START HERE. Time windows (V1: one window per job)

> ## 📋 DOCUMENTS ONLY. NOTHING IS BUILT. DO NOT EXECUTE WITHOUT THE FOUNDER'S GO.
>
> Written 2026-11-04 (Opus 5.5). The founder asked for the epic and stories and said, in so many
> words, **"no execution, just the epics."** The next session must get an explicit go-ahead before
> writing code, and a separate one before any Xano push.

| File | What it is |
|---|---|
| `README.md` | This file. Context, status, models, how to report. |
| `EPIC-TW-1-time-windows.md` | The spec. Five stories with Gherkin, decisions, open questions, governance, test plan, gate. |

---

## 1. Who you are working for

- **Product manager, not an engineer**, and the only support person. ADHD/INTP.
- **~5 short bullets per reply, one line each. No paragraphs.** `CLAUDE.md` 🔴 section. Asked for six-plus times.
- **A question is a question.** "Cool" / "sounds good" is not approval to build.
- **Ask before any Xano push, schema change, delete, or anything outward-facing.**
- Examples are illustrations. Never build for "a delivery between 9 and 11" — build the generic window.

---

## 2. What the founder asked for (2026-11-04)

> *"Create the stories to enable time windows … two types, one soft and one hard … for right now,
> version one, let's just put one time window, we can add the [other] later … enable that on the
> planning and the execution, it's editable CRUD."*

Translated into scope:

- **V1 = one time window per job.** No soft/hard type yet. The type is **V2** and is written up as
  deferred in the epic (§5), so V1's table is shaped to take it without a migration.
- **Editable (create / read / update / delete) in planning**, and **still editable once the day is
  live (execution)**, with the change logged and visible to the performer.
- **Visible to the performer** in the execution app.

---

## 3. Why this is not in the product today (verified 2026-11-04)

- PRD **D-13**: time windows are an **optional attribute**, never core. Nothing violates that here —
  a job without a window behaves exactly as today.
- PRD §4 scheduling shape lists *Time window* as optional; VAR-1 deferred *window adherence* (VA-2).
- **Nothing stores a window anywhere.** Grep for `time_window` / `timeWindow` across `apis/`,
  `functions/`, `webapp/protype-2/src` returns nothing. The only "start time" is
  `planner_timeline.start_time` (one `HH:MM` per day); task starts are derived from it.
- **Do not confuse this with WIN-1 (Epic-18).** WIN-1 is the **plan's** date range
  (`planning_window_start/end`). This epic is a **job's** time window — when *this piece of work*
  may happen. Different object, different table, different word in the UI ("Plan window" vs
  "Time window").

---

## 4. 🔴 The two places this epic can hurt something

1. **The publish snapshot hash (US-TW-1-04).** `live/build_publication` hashes a canonical string
   that has a byte-identical TypeScript twin in `webapp/protype-2/src/liveModel.ts`, tagged
   `publication|v1`. Adding the window to the snapshot changes that string. Done wrong, **every
   existing publication stops verifying.** The epic's answer is a new `publication|v2` for new
   publications only. Opus 5.5, both sides pinned by test.
2. **Dependency on WIN-1.** Epic-18's US-WIN-1-01/-03/-04 were still 📋 at last handoff. TW-1's
   "window must sit inside the plan's window" rule (D-5) reads the same plan columns. Check
   Epic-18's status before starting; if WIN-1 is unfinished, say so to the founder — do not finish
   it as a side quest.

Read **CLAUDE.md's XanoScript section** before any backend story. The traps most likely to bite
here: optional `date`/`text` inputs (`""` not `null`), `|` inside a string literal, ternaries inside
object literals, `|get` with a variable key, and the static-path routing shadow.

---

## 5. Models

The founder runs `/model`. If the current model is wrong for a story, build a story that matches
instead and record which are waiting.

| Story | Model | Why |
|---|---|---|
| US-TW-1-01 — the table | **Opus 5.5** | Schema push; shapes V2. |
| US-TW-1-02 — CRUD API + reads | **Opus 5.5** | New live endpoints, guards, tenancy, live-day change logging. |
| US-TW-1-03 — planner UI | Sonnet 5.5 | Form, chip, warning badge. Detailed spec, low blast radius. |
| US-TW-1-04 — window in the publish snapshot | **Opus 5.5** | Changes the canonical hash format. |
| US-TW-1-05 — performer sees it; live-day edits | Sonnet 5.5 | Read-only display + republish prompt. |
| Review pass after -01/-02/-04 | **Opus 5.5** | CLAUDE.md: review after risky backend work. |
| Fixtures, junk-input list, doc touch-ups | Haiku 5.5 | Mechanical — cheaper. |

---

## 6. How to report progress

- Edit each story's `**Status:**` line as you go: `📋 Not started` → `🚧 In progress (model, date)`
  → `✅ Built (model, date)` or `🔴 Blocked — reason`. Add 2–4 sentences on what differed and why.
- Fill §10 Test Results with a real result per ID. Not run = "not run", never "pass".
  **Every e2e spec skips without `E2E_AUTH_TOKEN`** — a skip is not a pass.
- Every deviation goes in §11 Notes. Then update §7 below.
- Stage files **by name**. Never commit `product/learning-fixes.md`, `.obsidian/`, the frontend zip,
  or loose screenshots (see Epic-18 README §3).

---

## 7. Status

| Story | State |
|---|---|
| US-TW-1-01, -02, -04 | ✅ Live (Opus 5.5, 2026-11-04). Opus review pass due |
| US-TW-1-03, -05 | ✅ Built + browser-verified (Sonnet 5, 2026-11-05) |
| Push to Xano | ✅ Done 2026-11-04 (founder go). Real publish of a test day with a v2 window still pending |
| Opus review pass over -01/-02/-04 | ❓ Not yet run |
| Q-1 (epic §6) | ✅ Answered 2026-11-04: planner only, for now |
| Q-2, Q-3 (epic §6) | ❓ Waiting on the founder. Defaults recorded |
