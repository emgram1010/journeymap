# Phase 11 — The execution app, redesigned (READ THIS FIRST, new session)

> **📝 DRAFT — waiting for the founder's review.** Do not build until the founder
> says go (e.g. "execute EXEC-1" or "start US-01"). Then follow **How to execute**.

## What this phase is

The performer's mobile app (`/perform`) works today, but it is plain. The founder had
a design tool mock up a better one from `product/design/execution-app-design-prompt.md`.
This phase brings that design into the real app and connects it to the real backend.

**The rule:** the prototype is a **picture to copy**, not code to paste. Its data is
fake (local storage, made-up reasons, made-up notifications). Every screen we build
reads and writes through the endpoints we already have, or small additions listed
in the epic.

## Where everything lives

| What | Where |
|---|---|
| Design prompt (what was asked for) | `product/design/execution-app-design-prompt.md` |
| Clickable prototype (the picture) | `product/prototype/app` → `npm run dev` → `http://localhost:3005` |
| Prototype screens to copy from | `product/prototype/app/src/components/*.tsx` |
| The real app (where code goes) | `webapp/protype-2/src/perform/` |
| The epic | `EPIC-EXEC-1-execution-app-redesign.md` (this folder) |

The original downloads in `product/prototype/*.tsx (1)` had their file names shuffled
by the export. `product/prototype/app` is the fixed copy. Don't use the originals.

## How to execute (step by step)

1. **Read, in order:** root `CLAUDE.md` (XanoScript traps + reply format), this README,
   the epic, then open the prototype in Chrome next to the real app.
2. **Tell the founder the model** for the story (table below). Wait if it doesn't match.
3. **Tests first**, as listed in each story, then the code.
4. Run `npx tsc --noEmit` and `npm test` in `webapp/protype-2`, then **open the screen
   in Chrome at phone size** (DevTools device mode, 390×844) and compare it with the
   prototype side by side. A story is not done until it has been seen in a browser.
5. Set the story **Done** with a dated Updates line and record the results in Test Results.
6. Report to the founder in **≤5 short bullets**, then continue in build order.
   Stop and ask before: any Xano push, any table change, anything that fails twice.

## Build order

| # | Story | Layer | Model | Can start when |
|---|---|---|---|---|
| 1 | US-01 Look and feel: shared status pill, colors, type, tap sizes | Frontend | **Sonnet 5.5** | Now |
| 2 | US-02 Today screen: time-first job cards | Frontend | **Sonnet 5.5** | After US-01 |
| 3 | US-03 Backend: job facts the new screens need | Backend | **Opus 5.5** (touches the performer's hot path) | Now (parallel with US-01) |
| 4 | US-04 Job screen: Overview tab with progress ring + Steps tab checklist | Frontend | **Sonnet 5.5** | After US-01, US-03 |
| 5 | US-05 Notes feed: job-wide Notes tab + preview on Overview | Frontend | **Sonnet 5.5** | After US-04 |
| 6 | US-06 Details tab | Frontend | **Sonnet 5.5** (Haiku fine) | After US-03, US-04 |
| 7 | US-07 Step screen redesign (Done when, timer, actions, reason sheet) | Frontend | **Sonnet 5.5** | After US-01 |
| 8 | US-08 States: loading skeletons, offline banner, keep-your-typing errors | Frontend | **Sonnet 5.5** | After US-02, US-04, US-07 |
| 9 | US-09 Bottom tab bar (Today / Profile) | Frontend | **Sonnet 5.5** (Haiku fine) | After US-02 |

After the last story: recommend an **Opus review pass** of US-03 and US-07 (they touch
the status engine's inputs and outputs).

## What stays exactly as it is (do not break)

- **Statuses are fixed:** `not_started`, `in_progress`, `blocked`, `done`, `skipped`.
- **Only `POST /work_task/{id}/event` moves a status** (LOG-1). The new screens call it
  the same way the current ones do: `recordEvent` in `performApi.ts`.
- **Blocked/Skip reason codes are fixed** in the database (`activity_log.reason_code`
  enum: `waiting_on_someone`, `missing_information`, `something_went_wrong`, `other`).
  The prototype's longer list is **not** used. See the epic's deferred list.
- **Performers never report time.** "Expected" comes from the pinned version and
  "Elapsed" from server `started_at`. The prototype's ticking local timer is display only.
- **The server decides what day it is** (APP-1, GAP-FIX W4/W8). Never use the device clock.
- **"Finish job" is navigation, not a server event** (D-1/D-2), gated by `canFinishSession`.
- The exception "Send to…" flow and "Came from" peek (`ExceptionSendPanel`,
  `JobPeekSheet`) keep working on the new Step screen.

## Deferred (not in this phase, listed so nobody builds them by accident)

| Idea from the prototype | Why it waits |
|---|---|
| Notifications tab | No notification backend exists. It needs its own epic. |
| Planner-managed Blocked/Skip reasons | The reason list is a database enum shared with the exception flow and the Health panel. Changing it is a table change plus three readers. Its own epic. |
| Job-level notes (a note not tied to a step) | Notes are stored as events on a step. A job-level note needs a new place to store it. For now the Notes tab gathers every step's notes. |
| Central quick-action button | It was "nice to have" in the brief. Revisit after real use. |
| Glove mode, dark mode | Cheap, but not needed to prove the design. Add after US-09 if wanted. |
| Photos and signatures | Out of scope in the brief. |
| "Reset demo data", style-guide modal | Prototype-only tools. |

## Founder preferences (from CLAUDE.md, enforce them)

- Replies: **5 short bullets max, no paragraphs, one question at the end.**
- Ask before any Xano push or table change (US-03 has one push, no table change planned).
- One story at a time. Record results in the epic's Test Results.
