# Phase 10 — Load what's on screen (READ THIS FIRST, new session)

> **✅ READY TO EXECUTE.** The stories in `EPIC-LOAD-1-load-what-is-on-screen.md` are
> written, checked against the code, and ready to build. Start when the founder says
> go (e.g. "execute LOAD-1" or "start US-01"), then follow **How to execute** below.

## How to execute (step by step)

1. **Read, in order:** root `CLAUDE.md` (XanoScript traps + reply format) → this README
   → `EPIC-LOAD-1-load-what-is-on-screen.md` → `product/performance/planner-load-time-audit.md` §5.
2. **Tell the founder the model** for the story you're starting (table below). If the
   session is on a different model, say so in one line and wait for them to switch
   (`/model sonnet` / `/model opus`) or say "continue".
3. **Measure the "before"** with the house method (below) for that story's endpoint.
4. **Build one story.** Set it **In progress** in the epic, then change the code, then
   prove the result is byte-identical (fingerprint), then run `npx tsc --noEmit` and
   `npm test` in `webapp/protype-2`, then open the screen in Chrome to check it.
5. **Measure the "after"**, then set the story **Done** with a dated Updates line and the
   numbers in Test Results.
6. **Report to the founder in ≤5 short bullets**, then move to the next story in the
   build order. Stop and ask only for: US-05's schema push, anything that fails twice,
   or a story whose "stop" condition triggers (US-01 and US-05 each have one).
7. After US-06, stop and report. Recommend an **Opus review pass** of US-05.

| Story | Model | Can start when |
|---|---|---|
| US-01 Board drops unused estimates | **Sonnet 5.5** | Now |
| US-02 Backlog waste + filtered link scan | **Sonnet 5.5** | Now (parallel with US-01 is OK) |
| US-03 Backlog summary first, steps on click | **Sonnet 5.5** | After US-02 |
| US-04 Board loads visible date range | **Sonnet 5.5** (switch to **Opus 5.5** if a view breaks twice) | After US-01 |
| US-05 Estimates stored at save time | **Opus 5.5** (new table; **ask founder before the push**) | After US-01–04 |
| US-06 Re-measure + record | **Sonnet 5.5** or **Haiku 5.5** | Last |

## The idea, in the founder's words (spirit, not literal)

"If you open a report, do you need every detail loaded? Or a summary first, and the
details when the user clicks 'details'?" Apply that to the planner: **load only what
the screen shows on arrival; load everything else when the user asks for it.**

## Why this matters more here than usual (measured, not assumed)

The Xano backend works through one account's requests **roughly one at a time**.
Timed live on 2026-11-02 from the signed-in page:

| Requests | Alone | Together (wall time) |
|---|---|---|
| board + backlog | 3.2s, 2.3s | **5.8s**: the sum, not the max |

So **parallel loading does not help** (it was tried, measured, and reverted in PERF-1).
Load time ≈ total server work, which means the only levers are **fewer requests** and
**less work per request**. This phase is about the second one.

## What you're inheriting (done already, uncommitted on branch `new-ui`)

| Epic | Where | State |
|---|---|---|
| REPUB-1 (republish a day until work starts) | `product/stories/phase-8/` | Done, verified live |
| PERF-1 (planner load fixes) | `product/stories/phase-9/` | US-01–04 done; its US-05 and US-06 are **folded into this phase**: see LOAD-1 US-02 and US-06 |
| Load-time audit | `product/performance/planner-load-time-audit.md` | Read §5. §2 ("14s freeze") is **retracted**: it was a measurement error |

Nothing from this session is committed yet. `git status` lists it all. The live Xano
workspace (1) already has every backend change pushed.

## What loads when the planner opens (the inventory this epic is based on)

| Request | Server time | What the screen actually shows | Verdict |
|---|---|---|---|
| plan list `GET /workspace` | ~0.9s | plan picker | Needed. Leave it |
| board `GET /workspace/{id}/board` (548) | ~2–3s | the visible day/week | **Too much**: every day of the plan, plus step estimates **nothing displays** → US-01, US-04 |
| jobs `GET /workspace/{id}/work_item` (558) | ~0.8s | title, status, step counts, units, chips | Needed as-is (the earlier "only title/status" guess was wrong; checked the code). Leave it |
| backlog `GET /workspace/{id}/backlog_work` (559) | ~1.6–3.8s | one summary row per card (total minutes + badge) | **Too much**: every card's full step list (only shown on click), estimates for jobs with nothing waiting, and an **unfiltered scan of every account's schedule links** → US-02, US-03 |

## Build order

| # | Story | Win | Risk | Model |
|---|---|---|---|---|
| 1 | US-01 Board stops computing step estimates nothing displays | High, scales per scheduled job | Low | Sonnet |
| 2 | US-02 Backlog stops wasted estimates + filters its link scan | High, scales with the whole customer base | Low–med | Sonnet |
| 3 | US-03 Backlog summary first, a card's steps on click | Medium | Med (UI + new endpoint) | Sonnet |
| 4 | US-04 Board loads the visible date range only | Grows with plan length | Med (several views) | Sonnet; Opus if a view breaks twice |
| 5 | US-05 Estimates stored when they change, not recalculated on every read | Highest structural | **High**: new table, staleness | **Opus**; **ask founder before schema push** |
| 6 | US-06 Re-measure everything and record before/after | Proof | None | Sonnet (Haiku fine) |

US-01 and US-02 touch different files and can run in parallel. US-03 needs US-02.
US-05 goes last before US-06 so the cheaper wins are measured on their own first.

## How to measure (reuse exactly; this is the house method)

1. In Chrome on `localhost:3000/architectures`, wait for it to settle, then run:
   ```js
   window.__perf = {click: null};
   document.addEventListener('click', () => { if (window.__perf.click == null) window.__perf.click = Math.round(performance.now()); }, true);
   performance.clearResourceTimings();
   ```
2. Click **Planner** in the left nav, wait ~10s, then read
   `performance.getEntriesByType('resource')` filtered to `fetch`, **relative to
   `window.__perf.click`**.
3. Run it **twice**. Xano varies ±1.5s run to run.
4. For one server function's own time, call it with `runWorkspaceFunction`; the
   result includes `timing`.

## Traps this project already hit (don't repeat them)

- **Never measure a gap across your own tool calls.** The "14s freeze" was the
  auditor's pause before clicking. Always record the click time inside the page.
- **Prove backend refactors byte-identical.** Write a throwaway function that runs
  the old and the new code for **every** plan with data and compares
  `sha256(json_encode(output))`. PERF-1 did this for 14 plans. Delete it afterwards.
- **An endpoint can't be called with `runWorkspaceFunction`.** For HTTP, get a token
  without a password: `Getting Started Template/generate_magic_link` →
  `POST api:RPonubWS/reset/magic-link-login` with `{magic_token, email}`.
- **Slow-network test without a throttling tool:** patch `window.fetch` in the page
  to delay one URL, then restore `window.__origFetch`.
- **React hooks must stay above any early `return`** (e.g. `if (!isOpen) return null`).
  A hook placed below one crashed `JobsModal` to a blank screen, and the typechecker
  doesn't catch it. Always open the screen in a browser before calling a story done.
- **Vite HMR after editing a component's hooks** can show "Rendered more hooks…".
  Hard-reload before deciding it's real (it was real once, see above).
- All XanoScript traps are in the root `CLAUDE.md`. Read it before any `.xs` change.
  The relevant ones here: a `where` can't call filters, branch only on loop items,
  `db.patch` touches the first match only, seed `in` arrays with `-1`.

## Founder preferences (from CLAUDE.md, enforce them)

- Replies: **5 short bullets max, no paragraphs, one question at the end.**
- Ask before any Xano schema push or table change (US-05 needs this).
- One story at a time; record results in the epic's Test Results.
