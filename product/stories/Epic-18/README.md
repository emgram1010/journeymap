# Epic-18 — START HERE. Handoff to a fresh session.

> ## ✅ DOCUMENTS ARE READY. YOU MAY START EXECUTING.
>
> Written 2026-11-01 by the previous session. The founder is out of pocket, so
> **nothing in this folder is waiting on them.** Read this file, then the epic
> file, then build. One open decision has a recorded default (D-3) — use it.

**This folder uses README as its only entry point** (no `START-HERE.md`, unlike
Epic-15/16/17) because the founder asked for one file to hand over, not two.

| File | What it is |
|---|---|
| `README.md` | This file. Context, status, how to work, models. |
| `EPIC-WIN-1-plan-window-enforcement.md` | The spec. Four stories with Gherkin, decisions, test plan, gate. |

---

## 1. Who you are working for — read this before anything else

- **The founder is a product manager, not an engineer**, and the only support person. ADHD/INTP.
- **Keep every reply to ~5 short bullets, one line each. No paragraphs. Ever.** This is in
  `CLAUDE.md` under a 🔴 heading and it has been asked for **six** times across sessions,
  including once in the session that wrote this file. Bullet *count* is not the measure — total
  reading load is. If they say "too long", they mean it.
- **Answer questions as questions.** A question mark means they want an answer, not a build. A
  short reply like "cool" or "sounds good" is **not** approval to start writing code.
- **Ask before: any Xano push, any schema change, any delete, anything outward-facing.** The one
  exception already granted is in D-4 of the epic file.
- Their examples are illustrations. "Moon bouncer repair" is test data, never a feature.

---

## 2. What this epic fixes

The founder created a plan called **"November 1-7"** with a planning window of
`2026-11-01 → 2026-11-07`, then found the UI had let them schedule a job onto **2026-10-27** —
five days before the window opens.

The cause is not a bug in one place. **The planning window has never been enforced anywhere:**

- Endpoint `538` (create timeline) computes `out_of_window` and **returns it as a flag**. It has
  never rejected anything.
- The frontend calls `isDateOutOfWindow` in six components. Every single use is a cosmetic badge
  or a count.
- The Place… date picker has no `min`/`max`, so the browser offers every date that exists.

Result: **17 of 38 timelines in the database violate their own plan's window.** The founder asked
for enforcement plus a cleanup of the bad rows.

---

## 3. Current state of the whole project — what the last session left behind

**Three epics shipped in the two sessions before this one.** You are not starting cold; you are
picking up a working app.

| Epic | What it did | State |
|---|---|---|
| Epic-15 (QUE-1) | Jobs list on the left, one "Unscheduled" queue at the bottom, confirm-before-unschedule | ✅ Built, Opus-reviewed, committed |
| Epic-16 (ROW-1) | One row per role line; job name opens the read-only job view | ✅ Built, committed |
| Epic-17 (QTY-1) | Unit quantities on a job, and what a split moved where. **Includes a live Xano change to endpoint 558** | ✅ Built, committed, **pushed live** |
| Epic-18 (WIN-1) US-WIN-1-02 | The UI stops offering out-of-window days: grid columns follow the real window, pickers bounded | ✅ Built on **Opus 5**, committed. Frontend only, **no Xano push**. Unverified in a browser (UI-01) |
| Epic-18 (WIN-1) -01 / -03 / -04 | Server refusal, shrink guard, cleanup of the 16 bad rows | 🔴 **Not started — need Opus 5.5.** Run `/model` first |

### 🔴 Things that are NOT done — do not assume otherwise

1. **`origin` has none of it.** Local `main` is **3 commits ahead of `origin/main`**. A
   `git push origin main` was attempted and **hung with no output** (almost certainly a
   credential prompt it could not display); it was stopped and no locks were left behind. **The
   founder has to run the push themselves** — suggest they type `! git push origin main` so the
   prompt lands in their terminal. Do not retry it blind in the background; it will hang again.
2. **An Opus 5.5 review of endpoint 558 is owed.** Epic-17's US-QTY-1-03 was built on Opus 5
   against a spec that required Opus 5.5. The founder agreed a review should happen and it never
   did. Logic was proven on 21 real jobs before the push (Epic-17 §9), so this is a verification
   debt, not a known bug.
3. **No e2e spec has ever been run, in any session.** All 47 skip without `E2E_AUTH_TOKEN`. Never
   report a skip as a pass.
4. **No founder browser pass on the drag gestures** or the unschedule confirmation dialog.
5. **`product/learning-fixes.md` lost ~1380 lines** (1823 → 443) *before* these sessions and was
   not touched by them. It is deliberately excluded from every commit. **Do not commit it and do
   not "fix" it** — ask the founder what happened.
6. **Uncommitted and deliberately so:** that file, `.obsidian/`, a 477 KB
   `webapp/protype-2/emgram1010-frontend.zip` build artifact, and several loose screenshots in
   `product/images/`. Keep excluding them; stage files **by name**, never `git add -A`.

### Where the code lives

- Planner frontend: `webapp/protype-2/src/planner/` (React + TS + Vite). A dev server may still
  be running on `localhost:3000`.
- Pure logic + unit tests: `src/planner/boardModel.ts`, `src/jobModel.ts` and their `.test.ts`
  twins. **Put logic in a tested pure function, not in JSX** — that is the house pattern.
- Backend: `apis/planner/*.xs` (XanoScript), workspace **1**, api_group **24** (`planner`).
- Verify with: `npx tsc --noEmit`, `npm test` (661 passing), `npm run build`,
  `npx playwright test --list`. All four were green at handoff.

---

## 4. 🔴 Read CLAUDE.md's XanoScript section before you touch the backend

Two of this epic's four stories change live XanoScript. That language has ~40 documented
**silent** failure modes in `CLAUDE.md` — things that push cleanly, return success, and quietly
do the wrong thing. The ones most likely to bite you here:

- A `conditional` inside a `foreach` whose **condition** reads a var updated earlier in the same
  iteration **discards every write in its branch**, with no error.
- `|get` with a **variable** key throws its default away and returns `null`. Pre-seed every key.
- `==`/`!=` against `null` is loose: `0`, `""`, `false` and `[]` all equal `null`. But `??` is
  **strict**, so `0 ?? 9` is `0`. The two cannot be reasoned about together.
- A `where` clause cannot call filters — hoist into a `var` first.
- `db.patch`/`db.del` by `field_name` touch only the **first** matching row.
- A ternary or an unwrapped `|filter:arg` inside an object literal **silently drops every key
  after it**. Wrap it in its own parens or hoist it.

**Always `getAPI` the live source and diff it against the local `.xs` before editing** — the live
workspace drifts from the repo. **After pushing, smoke-test with real non-empty data** via a
throwaway function and `runWorkspaceFunction`; a clean push is not evidence of correct logic. The
previous session did exactly this for 558 and it is why that change is trusted — copy the pattern.

---

## 5. Models — per story, and tell the founder when to switch

**You cannot switch models yourself. The founder runs `/model`.** They are out of pocket, so if
the current model is wrong for a story, **work on a story that matches instead** and say in your
notes which stories are waiting on a switch. Do not build a story below its required model and
hope; the last session did that once on US-QTY-1-03 and had to record the deviation.

| Story | Model | Why |
|---|---|---|
| US-WIN-1-01 — server refuses an out-of-window day | **Opus 5.5** | A live endpoint that is the **only** writer of `planner_timeline`. Break it and no day can be created at all. |
| US-WIN-1-02 — the UI stops offering bad dates | **Sonnet 5.5** | Date input bounds and column maths. Detailed spec, low blast radius. |
| US-WIN-1-03 — a window cannot shrink under scheduled work | **Opus 5.5** | A second live endpoint, and it is a guard. |
| US-WIN-1-04 — delete the 16 violating rows | **Opus 5.5** | Deletes across four linked tables. Orphan history and it is unrecoverable. |
| Review pass, after -01/-03/-04 | **Opus 5.5** | Required by CLAUDE.md after backend and guard work. |
| Doc touch-ups, test fixtures | Haiku 5.5 | Mechanical. Mention it to save them money. |

---

## 6. 🔴 How to report progress — the founder asked for this specifically

**Status every story in the epic file as you go. Do not batch it to the end.**

For each story, when you start and when you finish, edit its `**Status:**` line in
`EPIC-WIN-1-plan-window-enforcement.md`:

- `📋 Not started` → `🚧 In progress (model, date)` → `✅ Built (model, date)` or
  `🔴 Blocked — <reason>`
- On completion add 2-4 sentences: what you actually did, anything that differed from the spec,
  and **why**. Write it for someone who was not here.
- Fill in **§9 Test Results** with a real result per ID. If something was not run, say "not run",
  never "pass".
- Put every deviation in **§10 Notes**. The founder reads deviations; silently-correct work is
  worse than disclosed imperfect work.

Then update this README's §3 table so the next session inherits an accurate picture.

**If you find a mistake in Epic-15/16/17's documents, say so and ask — do not edit them.**

---

## 7. What "done" means

The gate is §8 of the epic file. In short:

1. All four stories built, or explicitly blocked with a reason.
2. New unit tests green, plus the full suite, `tsc`, `build`, and `playwright test --list`.
3. Backend changes smoke-tested live against real data, not just pushed.
4. The cleanup verified by re-querying — **count the rows, do not trust the function's own
   report.** A previous cleanup in this project reported success and changed nothing (CLAUDE.md's
   `db.patch`-on-json incident).
5. An Opus 5.5 review pass over the backend stories.

**Then stop.** Do not start the requirements / task-type / optimizer work in Epic-15 §4 — that
needs the founder's own go-ahead.

---

## 8. Two things to hand back to the founder when they return

- **The `git push origin main` they have to run themselves** (§3, item 1).
- **The window-shrink default (D-3).** It was the previous session's recommendation and they said
  "sounds good" without addressing it directly — so it is built as "refuse the shrink", which is
  the option that cannot strand a performer's day. Flag it as worth a one-line confirmation.
