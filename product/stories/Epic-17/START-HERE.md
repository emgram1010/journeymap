# START HERE — Epic-17, for the AI session that builds it

**Read this file end to end before opening anything else.** The founder is one non-engineer with
no team: a session that guesses costs them a day they do not have.

**Written:** 2026-10-31, from a design conversation the same day.
**Status when written:** nothing built. Two stories ready; one blocked on approval.
**Epic in this folder:** `EPIC-QTY-1-quantities-and-where-the-units-went.md` — that is your spec.

---

## 1. What you are building, in five sentences

A job in this system is a real run of some work, and it carries **lines** — how many units of
which item type. When something goes wrong mid-run, an exception **splits** the job: the parent
keeps the good units, and a child job carries the ones that need a different path. All of that is
already stored and already returned by endpoints that exist; **the planner's screens simply never
show it**, so the founder cannot tell whether a job means 2 units or 200, nor which units went
down which path. You are putting those numbers on screen, in the read-only job view, and nowhere
else. **You are not building a write path, a table, or a new endpoint** — except the one additive
response field in US-QTY-1-03, which is gated (§4).

It is generic. "Moon bouncer repair" is the founder's test data, not the feature. Never write the
words repair, bouncer, canopy or rental into code, a column, a label or a message.

---

## 2. Read in this order

| # | Read | Why |
|---|---|---|
| 1 | `CLAUDE.md` (repo root) | How to work here, how to talk to the founder, and the live-verified XanoScript traps. If you touch US-QTY-1-03, that trap list is not optional reading — several of them fail **silently**. |
| 2 | This file | Context, limits, the gate. |
| 3 | `product/stories/Epic-17/README.md` | Why the epic exists; the detail-vs-column asymmetry. |
| 4 | `product/stories/Epic-17/EPIC-QTY-1-quantities-and-where-the-units-went.md` | **The spec.** |
| 5 | `webapp/protype-2/src/exceptions/JobPeekSheet.tsx` | Where both frontend stories land. Read its `load`/`useEffect` pair before adding a fetch beside it. |
| 6 | `webapp/protype-2/src/planner/plannerApi.ts` lines ~440-470 and ~740-910 | The list entry (no quantities) and the line/split endpoints (quantities). The whole epic lives in that gap. |

Nothing else. Do not open other epics, and do not touch `product/validation-publish-execution/`.

---

## 3. What is already settled — do not reopen these

1. **Display only.** `putWorkItemLines` exists and stays untouched. Editing quantities is a
   different epic with its own validation and governance.
2. **Both frontend stories land in `JobPeekSheet`** — the one read-only job view (EXC-2's D-2).
   Do not build a second place to look at a job.
3. **No N+1 on the Jobs column.** One `getWorkItemLines` per visible row is refused, however
   convenient it looks as a way around the gated story. Spec D-3.
4. **ERP phrasing, not invented words.** `10 ordered · 8 here · 2 moved out`. The founder says
   "sub job"; the code says "child job"; the UI says neither — it writes a sentence.
5. **"No lines recorded" and "a quantity of zero" are different** and must read differently.

---

## 4. Hard limits

- **US-QTY-1-03 is BLOCKED.** It needs a Xano push. Do not call `createAPI`/`updateAPI`, and do
  not edit a live endpoint, without the founder's explicit go-ahead in that session. Deferring it
  and saying so is a perfectly good outcome; doing it quietly is not.
- **No schema change in any story.** US-QTY-1-03, if approved, is an **additive response field**
  on an existing endpoint — no new column, no new table.
- **If US-QTY-1-02 turns out to need backend data** (the per-child moved quantity may or may not
  already be in `getWorkItem`'s response — check first), **stop and say so.** Do not fold it into
  the gated story to avoid the conversation.
- **Two requests, two failure states.** A failed lines fetch must not blank the job's steps or
  status, and must surface its own reference. Spec D-4.
- **Do not fabricate test results.** Every e2e spec skips without `E2E_AUTH_TOKEN`. Write them,
  report them as unrun, never record a skip as a pass.
- **Do not edit Epic-15 or Epic-16** without asking.

---

## 5. Models, per story

| Story | Model | Why |
|---|---|---|
| US-QTY-1-01 | Sonnet 5.5 | One fetch beside an existing one, plus a tested summary function. |
| US-QTY-1-02 | Sonnet 5.5 | A sentence built from data the component mostly already has. |
| US-QTY-1-03 | **Opus 5.5** | A live list endpoint the founder's main screen depends on, and a per-job tally in XanoScript — where the silent-failure traps live (pre-seeded tally maps, no `[index]`, no `conditional` on a var updated in the same iteration). ✅ Built and pushed 2026-11-01 — **on Opus 5, not 5.5**; see the epic's §10 for that deviation and what was done to offset it. |
| Review pass | Sonnet 5.5 is enough for -01/-02 | No write path. **If -03 is built, review it on Opus 5.5** and smoke-test live with real non-empty data. |

Tell the founder which model to switch to **before** writing code. You cannot switch models
yourself.

---

## 6. What "done" means

Spec §8. In short: -01 and -02 built with their unit tests green and the full suite / `tsc` /
build green; -03 either approved-built-and-smoke-tested or explicitly left blocked; a founder
browser pass on a genuinely split job where **the numbers reconcile** (parent + child = the
original order); and Q-1/Q-2 answered from the real screen.

**Then stop and wait.** Editing quantities, and anything about requirements or the optimizer
(Epic-15 §4), are separate and need the founder's go-ahead of their own.
