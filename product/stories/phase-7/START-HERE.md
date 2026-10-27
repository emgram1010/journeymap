# START HERE — phase 7, for the AI session that builds it

**You are picking up work that was designed but not built.** Everything you need is in this
folder. Read this file first, end to end, before you open anything else. It exists because the
founder is one non-engineer with no team: a session that guesses costs them a day they do not
have.

**Written:** 2026-10-26, at the end of the design session that produced this phase.
**Status when written:** nothing in EXC-1 is built. No table, no endpoint, no UI, no test.

---

## 1. What you are building, in four sentences

A journey map can already say *"when work leaves this journey, it goes to that map"* — an
**exception link** drawn on a cell. Today that link is a picture: nothing reads it. After this
phase, a performer doing a step can say *"this part is leaving the happy path"*, and the system
starts a **child job** on the linked map, pinned to that map's published version, tagged back to
the job and step it came from, carrying any item counts that left. The parent job keeps going.

It is generic on purpose. The founder's example was a torn rental item going to a vendor for
repair, but the feature is *"work leaves this journey here, for this reason"* — a failed
delivery, a lead that needs legal review, a return that needs a claim. **Never build for the
rental example.** If you catch yourself writing the word "repair" into a column name, a status,
or a message, stop.

---

## 2. Read in this order

Do not skip ahead to the code. Each of these exists because a previous session got something
wrong without it.

| # | Read | Why |
|---|---|---|
| 1 | `CLAUDE.md` (repo root) | How to work here, how to talk to the founder, and ~40 XanoScript traps that were each found live, the hard way. Several will bite this epic specifically. |
| 2 | This file | Context, what is settled, what you must not do. |
| 3 | `product/stories/phase-7/README.md` | The phase: the two-layer picture, the vocabulary, what already exists, what is deferred. |
| 4 | `product/stories/phase-7/EPIC-EXC-1-exception-child-jobs.md` | The epic itself: builder brief, 8 stories, test plan, governance, settled decisions. **This is your spec.** |
| 5 | `product/emgramprd.md` §2, §7.4 (EX-5, EX-7), §9 | Why the three layers are shaped this way; what EX-7 promised. |
| 6 | The files named in the epic's **Builder brief → Read first** | The code you are extending. Read them before writing, not after. |

Nothing else. Do not open other epics, do not browse `product/validation-publish-execution/`
(see §6), do not read phase-4/5/6 epics beyond the specific files the brief names. One epic per
session is a rule here, not a preference.

---

## 3. Vocabulary — get this right or the whole thing reads wrong

This confused everyone, including the model that designed it. Two layers, two different words.

```
WRITE ONCE (intelligence layer)          HAPPENS EVERY TIME (execution)

parent map                                parent job #482
  … stage ─┐                                … step in progress ─┐
           │ exception link                                     │ "send to <linked map>"
           ▼                                                    ▼
linked map (own stages, own version)      child job #482-A (pinned to linked map vN)
```

- **Map = the recipe.** Written once, in the intelligence layer. A linked map is just another
  map that an exception link points at.
- **Job = one run of a recipe.** Created every time work actually happens. A **child job** is one
  run of the linked map, tagged with the parent job and step it came from.
- A child job is **not** a sub-task. `work_task` is flat and unique on
  `(work_item_id, stage_key, lens_key)`. A child is a normal `work_item` with
  `parent_work_item_id` set.
- A method's **sub-journey** link and an **exception** link share a word and are different
  things. A sub-journey is *how to do this stage for these items* — informational, shown to the
  performer later (EXE-M-1). An exception is *work leaves this journey here*. **This epic acts on
  `exception` links only.**

---

## 4. What is already settled — do not re-open these

The epic's **Decisions (settled)** table has all twelve with reasoning. The founder personally
confirmed these four on 2026-10-26:

| | Decision | What it means when you code |
|---|---|---|
| **D-1** | The parent does not stop. | Spawning never sets the parent to `blocked`. Blocking is a separate, explicit toggle that goes through LOG-1 with a reason, and a refusal there must not fail the spawn. |
| **D-3** | The linked map needs no separate plan approval. | Do not refuse a spawn because the target is missing from `planner_workspace_map`. If a list endpoint filters on acceptance, insert that row inside the same transaction. |
| **D-7** | Cancelling a parent does not cancel its children. | No cascade. Health surfaces orphaned open children so a person decides. |
| **D-11** | Exceptions live in a new table, not in `work_item.attributes`. | **Table 140 `work_item_exception` is approved — create it.** Record the id Xano actually assigns and name the local file after it. |

If building proves one of these wrong, **stop and say so**. Do not quietly design around it, and
do not re-litigate it to make your life easier.

---

## 5. Order of work

The epic's story order is the build order. Two things come **before** story one:

1. **Extract `jobs/create_job`** out of `554_work_item_POST.xs`.
2. **Extract `estimate/refresh_job_slots`** out of `607`'s "Refresh scheduled, untweaked slots" section.

Then re-run the JOB-1 and EST-1 functional tests and prove nothing changed (FT-EXC-1-15) **before**
writing anything new that calls them. The reason is a house rule earned painfully in LOG-1: a
rule that exists in two places will eventually disagree with itself, and both copies will sound
equally certain. The spawn endpoint and `554` must create jobs through the same function; the
spawn and `607` must refresh slots through the same function. No copied blocks.

After that, stories in order, and for each one: **tests first, then the code** (CLAUDE.md build
protocol). Run the new tests *and* the existing suites — `npm test` in `webapp/protype-2`,
`workflow_tests/1–32`, the existing Playwright specs. Record everything in the epic's **Test
Results** section, including anything you could not run and why.

### Models

The epic assigns them, and **you cannot switch models yourself — the founder runs `/model`.** So
say which one is needed, in one line, and wait:

- **Sonnet** builds US-01, 02, 04, 05, 06, 07.
- **Opus** writes **US-EXC-1-03**, the spawn endpoint. It is a multi-table transaction that edits
  frozen order lines on a live job and is the one sanctioned bypass of EST-1's freeze rule
  (`E-EST-007`). Say so before you start it.
- **Opus** again for the review pass at the completion gate.
- **Haiku** is enough for the golden fixtures and the error-catalog entries in US-08.
- Any bug that fails twice → Opus.

---

## 6. Hard limits

- **Ask the founder before:** any change to an existing table, any delete, any outward-facing
  action, anything touching the **original** maps 193 or 178. Table 140 is the one schema push
  already approved.
- **Test on clones only.** Map 193 (`item-turnaround`) and map 178 (`leads-to-sales-baseline`)
  are the founder's real maps. Clone them. Map **215** is an existing fixture clone of 193
  ("safe to delete") already used by the Items e2e spec.
- **Never edit `product/validation-publish-execution/`.** It is a parallel initiative that
  overlaps this work; the overlap is settled in PRD §8.6 (D-39). Its `BLOCKED` / `NOVEL_EXCEPTION`
  states are the AI-run path, deferred. This epic gives the *human* the equivalent action and
  leaves one endpoint the AI path can call later. Same vocabulary — no second status list.
- **Do not edit documents that were not part of the request.** Found a mistake in an older doc?
  Say so and ask.
- **This epic adds no status and no event type.** Not one. If you feel you need one, you have
  misread the design.
- **Do not open:** the catalog UI, the Items cell editor, publish/hash code (`canonical_hash`,
  `verify_version`), or the transition table (`log/next_status`).

---

## 7. Two traps that already cost this project real time

**A UI test that only clicks proves nothing.** On 2026-10-25 the founder reported that an Items
cell would not save their input. Root cause: the Save button sat 19 of its 32 pixels below the
fold of a scroll box, and a click on its own centre landed on a label painted underneath. Its
end-to-end test had been passing the whole time, because Playwright's `.click()` scrolls the
element into view and dispatches straight at it — it reproduces nothing a person does. The
feature looked tested and was unusable. **Every action button this epic adds needs one test that
asserts it is genuinely hittable** in the state that matters, and any button sitting below
content of unbounded length should be sticky. The epic's Test Plan has the exact assertion
(E2E-EXC-1-06).

**Xano fails silently, often.** `db.patch` on a `json` column *merges* instead of replacing.
`0`, `""`, `false` and `[]` all `== null`. `|get` with a variable key throws its default away.
`|contains` returns `false` for every array. A `conditional` inside a `foreach` whose condition
reads a variable updated earlier in that same iteration silently discards everything the branch
writes. None of these raise an error — they produce plausible, wrong output. The epic's Builder
brief lists the ones that bite here; `CLAUDE.md` has all of them with the incident behind each.
**After every push, smoke-test with real, non-empty data via `runWorkspaceFunction`.** A clean
push is not a working function.

---

## 8. What "done" means

The epic's **Completion gate**, in full. In short: every in-scope test green by ID; `npm test`,
`workflow_tests/1–32` plus the new `33`, and the existing e2e specs all still green; the two
extractions proven to have changed nothing; the phase-4 end-to-end rehearsal re-run on a 193
clone *with* a spawn mid-way and on a 178 clone; every new button proven reachable; an Opus
review pass; results written into the epic's Test Results, including failures and anything
skipped.

Then **stop and tell the founder.** Do not start the next epic.

## 9. How to talk to the founder

They are a product manager, not an engineer, ADHD/INTP-leaning, and the only support person for
everything you build. That shapes two things:

- **Answers are short bullets.** Five maximum, one line each, no paragraphs, no sub-bullets, no
  tables unless asked, one question at a time, asked last. More detail means *better* bullets,
  never longer prose. Files, walkthroughs and anything they explicitly ask to be written up are
  exempt.
- **Build the support in, not after.** Every feature gets validation with a plain-language
  message, error codes in the catalog, success *and* failure events, and a Health page view. They
  are the one who will be debugging this at 11pm. Never fail silently.

When you report back: what you built in one or two sentences, which tests pass or fail by ID,
anything that differs from the epic and why, what is next, and any decision you need from them.
