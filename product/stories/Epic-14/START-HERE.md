# START HERE — Epic-14, for the AI session that builds it

**You are picking up work that was designed but not built.** Everything you need is in this
folder. Read this file first, end to end, before you open anything else. The founder is one
non-engineer with no team: a session that guesses costs them a day they do not have.

**Written:** 2026-10-27, straight after the founder's first real end-to-end test of EXC-1.
**Status when written:** nothing in EXC-2 is built. No code, no test.
**Epic in this folder:** `EPIC-EXC-2-follow-sent-work.md` — that file is your spec.

---

## 1. What you are building, in five sentences

EXC-1 (phase 7) lets a person on a job's step say *"this part is leaving the happy path"*, and the
system starts a **child job** on a linked map. The founder tested it on 2026-10-27 — sent a
damaged item from their `item-turnaround` job to a `Moon bouncer repair` job — and it worked, but
**once the work was sent, they could not see the child job's steps or how far along it was.** On
the worker's step there is only a label chip ("1 → #126") that does nothing when tapped; on the
planner's job detail the same chip is a label too, and nothing anywhere says "the sent work is at
Repair, 2 of 6 steps done." This epic makes sent work **followable from both modules**: tap the
chip (Execution or Planner) and see the other job's steps, statuses and progress, read-only.

It is generic. "Moon bouncer repair" was the founder's test, not the feature. Never write the
words repair, damage, bouncer or rental into code, a column, a label or a message.

---

## 2. Read in this order

| # | Read | Why |
|---|---|---|
| 1 | `CLAUDE.md` (repo root) | How to work here, how to talk to the founder, and ~45 XanoScript traps found live. Section 4 of the epic lists the ones that bite this epic. |
| 2 | This file | Context, what is settled, what you must not do. |
| 3 | `product/stories/Epic-14/README.md` | The folder, the vocabulary, how EXC-2 sits on top of EXC-1. |
| 4 | `product/stories/Epic-14/EPIC-EXC-2-follow-sent-work.md` | **The spec**: builder brief, 5 stories with Gherkin, test plan, governance, decisions, completion gate. |
| 5 | `product/stories/phase-7/EPIC-EXC-1-exception-child-jobs.md` — sections **Vocabulary**, **US-EXC-1-05**, **US-EXC-1-06**, **Test Results** | What EXC-1 already built and how it was tested. EXC-2 extends EXC-1's read path only. |
| 6 | The files in the epic's **Builder brief → Read first** list | The code you are extending. Read before writing. |

Nothing else. Do not open other epics, do not browse `product/validation-publish-execution/`.

---

## 3. Check this BEFORE writing anything (10 minutes, saves a day)

1. **Is EXC-1 committed?** When this was written, all of EXC-1 was still **uncommitted** in the
   working tree on branch `users` (`git status` shows `apis/planner/610…`, `611…`,
   `functions/exceptions/`, `webapp/protype-2/src/exceptions/`, `static/tables/140…` as untracked).
   EXC-2 edits several of those files. If they are still uncommitted, **tell the founder in one
   bullet and ask whether to commit EXC-1 first.** Do not commit on your own; do not build on top
   of uncommitted work without saying so.
2. **Is the live workspace what the local files say?** Fetch live `exceptions/job_links`
   (function) and endpoints 555 and 611 (`getFunction` / `getAPI`, `include_xanoscript: true`) and
   diff against the local `.xs` files before you change them (CLAUDE.md rule).
3. **Run the existing suites once, untouched**, so you know the baseline: `npm test` in
   `webapp/protype-2` (610/610 on 2026-10-27), `npx tsc --noEmit -p .`, and
   `npx playwright test e2e/exceptions.spec.ts`. Write the numbers down.

---

## 4. What is settled — do not re-open these

The epic's **Decisions** table has the reasoning. In short:

| | Decision | What it means when you code |
|---|---|---|
| **D-1** | The view is **read-only**. | No Start/Done/Block buttons for the other job. Working the child's steps stays on its assignee's Today screen. |
| **D-2** | **One** view, shared by both modules. | One React component (`JobPeekSheet`), used by the performer's step screen and the planner's job detail. No second copy. |
| **D-3** | **No new table, no new endpoint** if avoidable. | Extend `exceptions/job_links` (feeds 611 and 555) with a progress summary; read the full step list from the existing `GET work_item/{id}` (555). |
| **D-4** | Progress means **finished steps ÷ all steps**, where finished = `done` or `skipped`. | Same rule on the server and in a TypeScript twin, pinned by one golden fixture. |
| **D-5** | **No new status, no new event type, no new table.** | One client-side failure event for a peek that fails to load, and two new catalog codes. That is all. |

Two things are **proposed, not yet confirmed by the founder** — the epic's **Open questions**
(Q-1 what a performer may see of another job, Q-2 Health). Ask Q-1 **before** US-EXC-2-02, as one
short question with your recommendation first. Q-2 is out of scope unless the founder says so.

---

## 5. Order of work and models

Story order is build order. For each story: **tests first, then code** (CLAUDE.md build
protocol). After each story run the new tests **and** the existing suites.

| Order | Story | Model | Why that model |
|---|---|---|---|
| 1 | US-EXC-2-01 — progress on the family list (Xano) | **Sonnet 5.5** | Read-only aggregation, but it is a XanoScript loop tally — exactly where the silent traps live. Follow §4 of the epic line by line. |
| 2 | US-EXC-2-02 — the shared read-only job view (React) | **Sonnet 5.5** | Ordinary UI + a pure function with a golden fixture. |
| 3 | US-EXC-2-03 — Execution: chips open the view | **Sonnet 5.5** | UI wiring + a reachability e2e at 375 px. |
| 4 | US-EXC-2-04 — Planner: chips show progress and open the view | **Sonnet 5.5** | UI wiring. |
| 5 | US-EXC-2-05 — governance: codes, events, catalog | **Haiku 5.5** for the catalog entries and fixtures; Sonnet for the rest | Mechanical. |
| — | Completion review | **Opus 5.5** (optional, recommended) | Not a risky epic (no writes), but it touches EXC-1, which was Opus-reviewed. |
| — | Any bug that fails twice | **Opus 5.5** | House rule. |

**You cannot switch models — the founder runs `/model`.** At the start, say in one line which
model the next story needs, and wait if it does not match.

---

## 6. Hard limits

- **Ask the founder before:** any schema change (none is planned), any change to an existing
  table, any delete, any outward-facing action, anything touching maps **193** or **178** or
  the founder's own test data (plan **42** "Moonbouncer", jobs **125** "TurnAround" and **126**,
  map **224** "Moon bouncer repair").
- **Test on fixtures you create**, on the existing EXC-1 clone fixtures: map **219** (parent clone
  of item-turnaround, with an exception link at stage `s2` → map **220**) and map **220** (repair
  fixture, published, Items row). Create your own plan; archive it and cancel its jobs at the
  end (you may do that cleanup without asking — standing permission for your own fixtures).
- **Never edit `product/validation-publish-execution/`.**
- **Do not edit documents outside this folder**, except: the EXC-1 epic's files you are told to
  change below, `CLAUDE.md` (only to add a newly found XanoScript trap), and the error catalog
  (`functions/ops/error_catalog.xs` + `webapp/protype-2/src/ops/errorCatalog.json`, both together).
- **Do not touch:** the spawn endpoint 610's write path, `log/record_task_event`, the transition
  table `log/next_status`, publish/hash code, the Items editor, table 140.

---

## 7. Traps that already cost this project real time

- **A UI test that only clicks proves nothing.** Playwright's `.click()` scrolls into view and
  dispatches straight at the element; it reproduced nothing a person does when a Save button sat
  19 px below a scroll fold (2026-10-25). Every new tappable chip and the view's Close button
  need a **hit-test** at 375 px (the epic's E2E-EXC-2-05 has the exact assertion, same shape as
  EXC-1's E2E-EXC-1-06).
- **Xano fails silently.** `|get` with a variable key throws its default away (pre-seed every
  tally key); a `conditional` in a `foreach` that reads a var updated in the same pass silently
  drops its writes; a ternary or `|filter:arg` as an object-literal value silently deletes every
  key after it; `|get:""` returns the whole object. All four are live risks in US-EXC-2-01.
  **After every push, smoke-test with real, non-empty data.**
- **Windows terminal mojibake is not a data bug.** Piping `curl` output into Python on this
  machine decodes UTF-8 as cp1252 and shows `·` as `Â·`. On 2026-10-27 that looked like a
  corrupted job title and wasn't. Read with `sys.stdin.reconfigure(encoding='utf-8')` before
  concluding anything about non-ASCII text.

---

## 8. What "done" means

The epic's **Completion gate**: every in-scope test green by ID; `npm test`, `tsc`, and all
existing e2e specs still green; the founder's own scenario reproduced on fixtures (send from a
parent step → tap the chip on the worker's screen → see the child's steps and "0 of N done" →
complete two child steps → the chip and the planner row both say "2 of N"); every new tappable
thing hit-tested at 375 px; results written into the epic's **Test Results**, including anything
skipped and why.

Then **stop and tell the founder.** Do not start another epic.

---

## 9. How to talk to the founder

- **Short bullets, always.** Five maximum, one line each, no paragraphs, no sub-bullets, no
  tables unless asked, **one** question, asked last. More detail = better bullets, never prose.
  Files and explicit write-ups are exempt.
- **Explain before writing** when they ask a question; never read a short reply ("ok", "yes") as
  approval to build something they did not ask for.
- **Build the support in.** Plain-language messages, catalog codes, success *and* failure
  events. They are the only support person.
- **Report back:** what you built (1–2 sentences), tests pass/fail by ID, anything that differs
  from the epic and why, what is next, the one decision you need.
