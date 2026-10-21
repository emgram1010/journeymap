# EPIC-BLK-1 — One card per order

**Status:** ✅ **done (2026-10-21).** Four stories built, pushed and proved
live. Story 05 deferred by scope decision. Written 2026-10-20,
rewritten the same day after the founder settled the question the design hung
on, corrected on 2026-10-21 after a live check, and scoped to **four stories**
on the same day.

**Build order: 01 → 02 → 03 → 04 → 06.** Backend first so the destructive
story (02) is proven over real HTTP before any screen depends on it. Story 05
is deferred — see MVP scope.

Completes `US-SCHED-1-02` and `US-SCHED-1-03`, deferred in SCHED-1.

## Why

The founder ran their own `item-turnaround` map end to end and hit the problem
immediately: one customer's return produced **eight separate cards**, one per
stage. For twenty customers that is 160 cards, and none of them is the thing a
person actually picks up and does.

What they want:

> In execution, the user is able to see each job that represents an order of a
> turnaround. Open it up. And work through the different stages.

### The decision that shrank this epic

An earlier draft built a general grouping mechanism: a per-stage "continues the
one before" marker, and a rule that derived block boundaries from it. That
existed to handle work split across sittings, with dwell time between them.

The founder removed the need for all of it:

> Any order that gets processed will be processed on all the steps at that
> moment.

So there is no dwell between stages, and no partial sitting. **An order runs
start to finish in one pass.** That makes the grouping rule trivial — a card is
a job — and deletes two stories, a side table, a resolver function, and the
entire question of where a block begins and ends.

### What this still is not

An earlier conversation explored reshaping the Intelligence Layer for this:
one map per task, or stages as subtasks of an actor row. Rejected, and still
rejected:

- A map is a **process** — versioned, hashed, reused. A job is **one run** of
  it. A map per customer puts instance data inside a published definition.
- **Quantity is data, not structure.** 25 chairs and 3 tables belong in the
  job's `attributes`, not as 28 records.
- **Structure follows divergence, not count.** A child job is created when a
  subset takes a *different path* — damaged tables going to a repair map —
  never because there are more of something.

**This epic changes nothing in the Intelligence Layer.** The stages, their
order, their text, their done-when and their expected minutes are already in
the published version and already arrive correctly.

## The rule

> **A card is one job's steps for one actor row. One order, one role, one
> person, one pass.**

For the founder's `item-turnaround` map this is the same thing as "the whole
job", because the map has exactly one row that does planned work. It is not the
same thing in general — see *Decided*, which records the live check that found
**7 of 23 existing jobs spanning two actor rows** (`sales` and `ops`).

Everything follows from that:

- It cannot span two jobs, or two actor rows within a job — the steps' text and
  order all come from one job's pinned version, and the row is who does them.
- It sits on one day, because a `planner_task` belongs to exactly one
  `planner_timeline`, and a timeline is one agent's day.
- It does not change measurement. The steps still exist underneath, each with
  its own status, its own actual minutes and its own variance — the performer
  starts and finishes each one as they walk it.

## What already exists, verified live 2026-10-20

This epic is unusually cheap because the groundwork was laid deliberately, and
because the hardest part of the execution experience is already built.

| Already true | Evidence |
|---|---|
| The slot→step link is **many-to-one**, with `position` | `static/tables/124_planner_task_work_task.xs`: *"blocks are coming… Keeping the relationship many-to-one from the start means blocks arrive without a migration."* |
| A step can be scheduled **at most once** | `btree\|unique` on `work_task_id`, enforcing `E-SCHED-001` |
| The performer model expects several steps per card | `SnapshotItem.work_task_ids: number[]` — *"One task → one id. A block (grouped stages) → several."* |
| **The performer screen already groups by job** | `sessionModel.ts`: *"a session groups by JOB (`work_item_id`) because that is what a performer actually experiences: one customer, one flow, start to finish."* |
| The step screen already walks steps in order | `SessionScreen.tsx` — planned order, next highlighted, `subSteps` rendered |

**No migration. No new table. No change to `planner_task`.**

## The shape, end to end

```
┌─ INTELLIGENCE LAYER ───────────────────────── Δ NONE ─────┐
│  MAP  item-turnaround  v2                                 │
│   s1 count → s7 separate → s2 inspect → s3 triage →       │
│   s8 clean → s4 exception → s5 finish → s6 close          │
└───────────────────────────┬───────────────────────────────┘
                            │ publish (frozen)
┌─ PLANNING ──────────────────────────── Δ one grouping ────┐
│  JOB  "Jones return"   { chairs: 25, tables: 3 }          │
│   ┌───────────────────────────────────────────┐           │
│   │  ONE CARD = THE WHOLE ORDER               │           │
│   │  all 8 steps · one person · one pass      │           │
│   └───────────────────────────────────────────┘           │
│   Mon 26 Oct · Jav                                        │
└───────────────────────────┬───────────────────────────────┘
                            │
┌─ EXECUTION ──────────────────────── Δ open the job ───────┐
│   MY JOBS                      JOB OPENED                 │
│  ┌──────────────────┐         ┌────────────────────────┐  │
│  │ Jones return 0/8 │   ──→   │ ← Jones return    v2   │  │
│  │ Smith return 0/8 │         │  ▸ 1 count      60m    │  │
│  └──────────────────┘         │    2 separate   10m    │  │
│                               │    3 inspect   120m    │  │
│                               │    …                   │  │
│                               │  start → finish,       │  │
│                               │  one pass, no gaps     │  │
│                               └────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

## Non-goals

- **No per-stage continuity markers.** Deleted by the founder's decision; the
  card is always the whole job.
- **No splitting a job across days.** If that is ever needed, it is a new
  question and it brings dwell back with it.
- **No change to how jobs or work tasks are created.** One task per (stage,
  working row), exactly as now.
- **No child jobs.** `parent_work_item_id` is hardcoded to 0 in the create-job
  endpoint — a separate gap, noted in Still open.
- **No capture fields.** That is [Epic-12 / CAP-1](../Epic-12/EPIC-CAP-1-capture-fields.md),
  parked by the founder for now. This epic ships with the existing note and
  status capture.

## Error codes

| Code | Meaning | Status |
|---|---|---|
| `E-SCHED-001` | A step is already scheduled | Exists — the unique index enforces it |
| `E-SCHED-006` | The day is published | Exists |
| `E-SCHED-007` | Work has been recorded against the step | Exists |
| `E-BLK-001` | **New.** The steps sent are not exactly one job's unscheduled steps | Needed: a caller must not be able to schedule half a job and silently strand the rest |
| `E-BLK-002` | **New.** A card cannot span two jobs, or two actor rows | Needed: states the rule in the refusal, by name. Two rows means two roles, and one person would be handed somebody else's work |

`E-BLK-001` exists for the reason `E-ORD-001` did in ORD-1: the client sends a
list, and a list that is *nearly* right is the dangerous case.

## Stories

### US-BLK-1-01 — The backlog offers whole jobs, not loose steps ✅ Done (2026-10-21)

**As a** founder
**I want** the backlog to show me one row per order
**So that** I am scheduling work, not fragments of it.

```gherkin
Scenario: One row per job, per actor row
  Given a job with 8 unscheduled steps, all for one actor row
  When the backlog is opened
  Then it shows 1 row, not 8

Scenario: A job spanning two actor rows gives two backlog rows
  Given a job with steps for both the sales row and the ops row
  Then the backlog shows one row for each, named by its actor
  And neither offers to schedule the other's steps

Scenario: A row says what it contains
  Then the row shows the job title, the step count
  And the total expected minutes, summed from the pinned version

Scenario: A scheduled job leaves the backlog
  Given a job has been scheduled
  Then it no longer appears in the backlog

Scenario: A partly scheduled job is shown honestly
  Given some of a job's steps are already on a day
  Then the row says how many remain unscheduled
```

**Method:** `GET /workspace/{id}/backlog_work` returns one row per
**(job, actor row)** with unscheduled steps, instead of one row per step.

**Counter-measures:**
- The existing response shape changes. Enumerate every caller first — the
  backlog drawer is the known one; prove there are no others.
- `db.query`'s `return = {type: "list"}` must not use `paging`: it stops being
  a plain array and `foreach` fails (CLAUDE.md).
- The last scenario matters because jobs created before this epic may already
  have some steps scheduled individually.
- 🔴 **Group by actor row as well as job.** Checked live 2026-10-20: 7 of 23
  existing jobs have steps across two rows. Grouping by job alone would offer a
  card mixing `sales` and `ops` work, and whoever took it would be handed
  somebody else's job.

**Done when:** the founder's live job shows as **one** backlog row, and a
partly-scheduled job reports its remainder correctly.

---

### US-BLK-1-02 — Schedule a whole job in one action ✅ Done (2026-10-21)

**As a** founder
**I want** to put an order on Jav's day in one click
**So that** the board shows one card for the work he will actually do.

```gherkin
Scenario: One card, every step of that actor row
  Given a job of 8 steps, all for one actor row
  When it is scheduled onto a day
  Then exactly one planner_task is created
  And it links all 8 steps, position 1..8 in the pinned version's stage order
  And its duration defaults to the sum of the steps' expected minutes

Scenario: A step cannot be scheduled twice
  Given one step of the job is already on another day
  When the job is scheduled
  Then it is refused with E-SCHED-001
  And no planner_task is created and no link is written

Scenario: A card cannot span two jobs or two actor rows
  When a caller sends steps from two jobs
  Then it is refused with E-BLK-002
  And the same happens for steps from two actor rows of one job

Scenario: Half a card is refused
  When a caller sends only some of that row's unscheduled steps
  Then it is refused with E-BLK-001 and nothing is written
```

**Method:** a card-level schedule endpoint taking `timeline_id`, a job id and
an actor row key. One `planner_task`, then one link row per step with
`position` 1..n, all inside a `db.transaction`.

**Counter-measures:**
- 🔴 **Re-derive the card's steps server-side and compare.** The client sends a
  list; the server must not trust it. Same lesson as ORD-1's exact-permutation
  check. "The card" means this job's unscheduled steps **for this actor row**,
  not the job's whole set.
- 🔴 **Write the links inside a transaction.** A half-written card leaves steps
  claimed by a slot that does not cover them, and the unique index makes that
  permanent until someone unpicks it by hand.
- `db.patch`/`db.del` with `field_name`/`field_value` touch only the **first**
  match (CLAUDE.md). Every link must be written and removed **by its own id**.
- Let the unique index fire and translate it to `E-SCHED-001` rather than
  racing it with a pre-check.
- Order steps by the **pinned version's** stage order, not by `work_task.id`.
  ORD-1 made stage order mutable; a job pinned to v2 must use v2's order.

**Done when:** all four scenarios pass against a clone of the founder's live
job, and a failed attempt leaves zero rows behind.

---

### US-BLK-1-03 — Take a job back off the schedule ✅ Done (2026-10-21)

**As a** founder
**I want** to undo a scheduling decision
**So that** a plan can be reshaped before it is committed.

```gherkin
Scenario: The job returns to the backlog whole
  When a scheduled job is unscheduled
  Then its planner_task and all its links are gone
  And all its steps reappear in the backlog as one row

Scenario: A published day is protected
  Given the day has been published to live
  Then unscheduling is refused with E-SCHED-006

Scenario: Recorded work is protected
  Given any step has been started or finished
  Then unscheduling is refused with E-SCHED-007

Scenario: Unscheduling something not scheduled is not an error
  Then the response says already_unscheduled, and nothing changes
```

**Method:** the block-level twin of the existing
`DELETE /work_task/{id}/schedule`. Reuses `E-SCHED-006` / `E-SCHED-007`
unchanged.

**Counter-measures:**
- Delete every link **by its own id**, inside a transaction.
- The steps themselves must survive — they return to "waiting for a day" and
  keep reading their text from the pinned version. Only the slot and the links
  go.
- Refuse the **whole** card if **any** step has recorded work. A partial
  unschedule is how a performer ends up holding half an order.

**Done when:** all four scenarios pass, and a refused unschedule leaves the
card and every link exactly as they were.

---

### US-BLK-1-04 — The performer opens a job and walks it ✅ Done (2026-10-21)

**As John, doing the work**
**I want** to open the order and be walked through it
**So that** I always know what is next without reading a plan.

```gherkin
Scenario: One card, the stages inside
  Given a job of 8 steps for one actor row is on John's day
  When John opens Today
  Then he sees one card, not eight
  And opening it lists all 8 stages in order
  And it shows which actor row the card is for

Scenario: The next stage is obvious
  Then the next unfinished stage is highlighted
  And John can still start a different one (order is a guide, not a lock)

Scenario: Each stage is timed on its own
  When John finishes a stage
  Then that stage's own actual minutes are recorded
  And the card is not finished until every stage is done or skipped

Scenario: Each stage shows its own text from the pinned version
  Then every stage shows its task text and its done-when
  And none of it is read from the live map
```

**Method:** mostly wiring. `SnapshotItem.work_task_ids` is already an array,
`sessionModel` already groups by job, and `SessionScreen` already walks steps
with the next one highlighted. The work is making a multi-step card render and
behave as one unit.

**Counter-measures:**
- 🔴 **Per-stage timing must survive.** It is the reason the steps still exist
  underneath the card. Prove it with a before/after comparison of the same work
  done as 8 cards and as one.
- A card's status is **derived** from its stages (`deriveJobStatus`'s
  precedence: blocked wins outright). Do not store a second status on the card
  that can drift from its parts.
- An untouched `decimal` reads as `0`, not `null`, so "has this stage been
  timed" must come from a real signal, never from a duration being non-null
  (CLAUDE.md, AUTH-1).

**Done when:** the founder's own job is performed as one card, and the
per-stage actuals are identical to performing it as eight separate steps.

---

### US-BLK-1-05 — Reach a job without going through a day *(deferred)*

**As John**
**I want** to open "Jones return" directly
**So that** an order is one thing, not three fragments across three screens.

```gherkin
Scenario: My jobs
  Given John has work on two orders
  When he opens My Jobs
  Then he sees one row per order, with its progress

Scenario: Someone else's role is not John's work
  Given an order has steps for the sales row and the ops row
  And John holds the ops row's card
  Then My Jobs shows him the order with his own steps
  And the sales steps are visible as context, not as his to start

Scenario: Every stage is visible, scheduled or not
  Given some of a job's steps are not yet on a day
  When John opens the job
  Then those steps are listed, marked as not scheduled
  And they cannot be started

Scenario: Day view still works
  Then Today is unchanged for anyone who prefers it
```

**DEFERRED 2026-10-21, and the reason is the founder's own decision.** An
order is now worked in one pass on one day, so the day view already shows the
whole order — there is nothing left for a job-scoped screen to reveal. This
story only earns its cost again if an order starts spanning days, which is
exactly the case the founder ruled out. Re-open it then, not before.

**Method (when re-opened):** a job-scoped fetch alongside the existing
date-scoped `fetchToday`, and a list screen. The grouping logic is reused
unchanged — `sessionModel` already groups by `work_item_id` by design.

**Counter-measures:**
- Today's entry point is a **date**, which is why one order currently appears
  as several fragments. The fix is the entry point, not the grouping.
- An unscheduled step has no slot and no planned start. It must be visibly
  distinct and not startable, or a performer will work ahead of the plan and
  the variance figures will not mean what they say.
- Scope the fetch by account and by the performer's own agent, not by job id
  alone.

**Done when:** John can open an order end to end from one screen, and
unscheduled steps are visible but inert.

---

### US-BLK-1-06 — A tweak is a promise about the card, not about its steps ✅ Done (2026-10-21)

**As a** founder
**I want** to shorten a card without corrupting the process estimate
**So that** I can tell "our estimate is wrong" apart from "we promised less
time today".

```gherkin
Scenario: Tweaking a card leaves the estimate alone
  Given a card of 8 steps whose pinned version expects 300 minutes
  When the card is tweaked to 240 minutes with a reason
  Then planner_task.duration_minutes is 240 and is_tweaked is true
  And every step's expected minutes are unchanged

Scenario: Two variances, reported separately
  Given the card's steps actually took 275 minutes in total
  Then PROCESS variance compares 275 against the version's 300, per step
  And PLAN variance compares 275 against the committed 240, for the card
  And neither number is derived from the other

Scenario: The card's actual is never entered directly
  Then the card's actual is the sum of its steps' actuals
  And there is no field on the card a person can type an actual into

Scenario: A tweak must say why
  When a card is tweaked with no reason
  Then it is refused, and the card keeps its previous duration
```

**Method:** no attribution, and that is the whole design.
`planner_task.duration_minutes` is the **commitment**; the pinned version's
per-step minutes remain the **estimate**; actuals roll up from the steps. The
existing `tweak_reason` field carries the explanation.

**Counter-measures:**
- 🔴 **Never distribute a card-level tweak across its steps.** Cutting 300 to
  240 does not say which step the planner meant to shorten, so any split would
  be invented — and the invented number would then flow into the per-step
  process variance, which is the one signal that has to stay clean. The
  product's whole claim is that variance is computed, not reported; a
  distributed guess quietly breaks that claim.
- 🔴 **The card must not get its own `actual` field.** Two places holding the
  same truth is how `work_task.status` and `activity_log` would have drifted,
  and the codebase already answers that the same way: one is a cache of the
  other, never an independent value.
- An untouched `decimal` reads as `0`, not `null` (CLAUDE.md), so "was this
  tweaked" must come from `is_tweaked` / `tweak_reason` — never from the
  duration happening to differ from the sum, which it may do for rounding
  reasons alone.
- Both variances must be visible somewhere, or the distinction is academic:
  "the job took longer than the process says" and "the job took longer than we
  promised today" are different problems with different fixes.

**Done when:** tweaking a card changes the plan variance only, and the per-step
process variance is byte-identical before and after.

## Build results (2026-10-21)

Proved live as **test user 9 in test account 6**, on a disposable plan and two
disposable jobs. Never map 178, never the founder's account — and the one
cross-account test deliberately targeted another **test** account rather than
the founder's, so a failing guard could not have damaged real work.

### What was built

| Piece | Where | Live id |
|---|---|---|
| Backlog returns one row per (job, actor row) | `apis/planner/559_..._backlog_work_GET.xs` | endpoint 559 |
| Schedule a whole card in one call | `apis/planner/583_card_schedule_POST.xs` | endpoint 583 |
| Unschedule releases the whole card | `apis/planner/576_..._schedule_DELETE.xs` | endpoint 576 |
| The cascade that makes that safe | `functions/planner/unschedule_work_task.xs` | function 169 |
| The performer walks every stage | `src/perform/SessionScreen.tsx`, `sessionModel.ts` | — |
| Two variances, never one | `src/planner/varianceDisplay.ts` | — |
| `E-BLK-001` in the catalog; `E-SCHED-001` marked `message_varies` | `src/ops/errorCatalog.json` | — |

### 🔴 The bug found by reading before writing

`planner/unschedule_work_task` deleted **one** link and then the whole slot.
Correct while a slot held one step; catastrophic the moment it holds a card.
Unscheduling would have deleted the `planner_task` and left its other links
behind — rows pointing at a slot that no longer exists. Those steps would then
be invisible to the backlog **forever**, because "unscheduled" means "absent
from that table", and there would be no slot left to unschedule them from.
Permanently stuck, nothing logged, no error.

Found by reading the function before building on it, not by a test failing.
Now deletes every link of the slot, each by its own id, inside a transaction.

Its caller (endpoint 576) needed widening too: its refusals checked only the
named step, so a card could have been dissolved out from under a sibling step
that had already been started. Both checks now look at every step the slot
covers.

### Where the plan changed, and why

- **The caller names the card; the server derives the steps.** The epic had the
  client send a list of step ids for the server to re-derive and compare.
  Endpoint 583 takes `work_item_id` + `lens_key` instead, which removes the
  whole class of "the list was nearly right" failure — there is no list to be
  wrong, and no way to express a card spanning two jobs or two rows. That made
  the epic's second refusal code unnecessary, so only `E-BLK-001` was added.
- **One card-aware unschedule, not a second endpoint.** The epic asked for a
  card-level twin of 576. Two code paths doing the same delete is how the two
  eventually disagree about the rule, so 576 became card-aware instead.
- **A card is (job, actor row), not the whole job.** Decided before building,
  on live evidence — see Decided.
- **Single-step cards render exactly as before.** The multi-step layout is a
  new branch, so nothing changes for a plan that has not been scheduled as
  cards.

### Tests

| Check | Result |
|---|---|
| Backlog: 5 loose steps across 2 jobs | ✅ **4 cards**, split correctly by actor row |
| Backlog: a 2-step card | ✅ steps in the pinned version's **stage order** (s1 then s3, skipping the other row's s2), minutes summed 99 + 5 = 104 |
| Backlog: text comes from the pinned version | ✅ v3's deliberately reworded fixture text ("Enquiry REWORDED") appeared, proving it is not reading the live map |
| Schedule a card | ✅ one `planner_task`, 2 links, **position 1 and 2**, duration 104 = the expected sum, `is_tweaked` false |
| Schedule it twice | ✅ refused `E-SCHED-001`, nothing written |
| Schedule an actor row with no steps | ✅ refused `E-BLK-001` |
| Schedule another account's job | ✅ 404 "Job not found" — tenancy reads as not-found, never forbidden |
| Scheduled card leaves the backlog | ✅ 4 cards → 3 |
| Unschedule via **one** step of a 2-step card | ✅ released **both** (`released_work_task_ids: [75, 77]`), card returned whole |
| Orphan check after unschedule | ✅ **zero** links left pointing at the deleted slot |
| Publish the day to live | ✅ publication froze the card as one item, `work_task_ids` joined into its line |
| Performer payload | ✅ one item with `work_task_ids: [75, 77]`, both steps hydrated with task, done-when and expected minutes |
| **Browser:** open the card | ✅ "Clerk · 2 steps · 104 min", stage 1 "Receive" marked **Next**, stage 2 "File" listed |
| **Browser:** open stage 2 | ✅ opened with its own text, done-when and 5-minute estimate — **this was unreachable before**, the screen rendered `subSteps[0]` only |
| **Browser:** finish stage 2 out of order | ✅ stage 2 went **Done**, stage 1 stayed **Next** (D-4: order is a guide), card status derived to **In progress**, "Finish session" correctly still disabled |
| **Per-stage timing survives** (the story 04 gate) | ✅ database shows step 77 `done` with its own `started_at`/`completed_at`; step 75 untouched at `not_started`/0 |
| `npm test` | ✅ **427/427** (11 new: 5 for `nextSubStepToWork`, 6 for `cardVariance`) |
| `npm run lint` | ✅ clean |

**Caught by the repo's own guards, not by me:** the first run failed two tests —
a stray `E-BLK-002` reference left in a comment, and `E-SCHED-001` emitting a
second wording without being marked `message_varies`. Both were real; both
fixed before the suite went green.

**Not run, stated plainly:**
- **No Playwright spec.** The 26 existing specs still fail at sign-in for want
  of `E2E_AUTH_TOKEN` (ISSUES-BACKLOG #4). The browser path above was driven by
  hand instead.
- **The planner UI was not changed.** Endpoints 559 and 583 are live and
  proven, but no screen calls 583 yet — the Jobs modal still schedules one step
  at a time through 560. That is the next piece of work and it is **not** in
  this epic; see Still open.

## MVP scope

**In:** stories 01, 02, 03, 04 and 06.

**Deferred:** **story 05** — a job-scoped "My Jobs" screen, which the
one-pass-per-order decision made redundant (the day view already shows the
whole order); splitting a job across days; drag-to-merge or drag-to-split on
the board; reordering steps inside a card; assignment by role (SCHED-1's
`US-SCHED-1-04`); child jobs.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | Card endpoints run behind the planner's existing actor resolution; a card is derived from a job that already belongs to the caller's account. The My Jobs fetch is scoped to the performer |
| Validation | The server **re-derives** the job's steps and refuses anything that is not exactly one job's unscheduled set (`E-BLK-001`), or that spans jobs (`E-BLK-002`) |
| Error codes | `E-BLK-001`, `E-BLK-002` added to `src/ops/errorCatalog.json`; `E-SCHED-001/006/007` reused unchanged |
| Events | Every card scheduled and unscheduled logs success; every refusal logs `rejected`, so denials reach the Health page |
| Table constraints | **No schema change at all.** The link table was built many-to-one for this, with `position` |
| Delete behaviour | Unscheduling removes the slot and its links, by id, in a transaction; the steps survive |
| Rollback | Story 01 is a read-shape change. Story 02 is the first destructive one — it writes links that make a step un-schedulable elsewhere. Commit before it |
| No silent failure | A partially valid card is refused outright, never partly applied |
| Testing | Every live exercise runs on a **clone**, never the founder's own job, and never map 178 |

## Test Results

_Not started._

| Story | Tests | Result |
|---|---|---|
| 01 | 5 steps → 4 cards; stage order; summed minutes; pinned-version text; scheduled card leaves the backlog | ✅ all pass |
| 02 | One slot + 2 positioned links; duplicate refused; empty card refused; cross-account 404 | ✅ all pass |
| 03 | Released both steps from one call; zero orphan links; card returns whole | ✅ all pass |
| 04 | Browser: card opens, both stages listed, stage 2 reachable and finishable, card status derived; **per-stage timing proven in the database** | ✅ all pass |
| 05 | _Deferred — not built_ | — |
| 06 | 6 unit tests: tweaking a card moves the plan gap only, process gap byte-identical, card has no actual of its own | ✅ all pass |
| 06 | Per-step process variance byte-identical before and after a tweak; both variances reported; no actual field on the card | — |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| 🔴 **Per-stage measurement could be lost** | If a card records one actual, cycle time and variance become meaningless — and those are the product's reason to exist | Story 04's gate is a before/after equality check of per-stage actuals |
| 🔴 **Grouping by job alone** | Would mix two roles onto one card. Not hypothetical — 7 of 23 live jobs span two actor rows | The card key is (job, actor row) everywhere: backlog, schedule, refusals |
| 🔴 **A half-written card** | The unique index makes a partial write permanent until unpicked by hand | One transaction, links written and removed by id |
| 🟡 **The two variances get conflated** | A card's committed minutes and its steps' estimated minutes are different promises. Reporting one number would hide whichever question nobody asked | Story 06: no attribution, two separate figures, neither derived from the other |
| 🟡 **The expected minutes are wrong** | The live map's eight stages total **11h 50m**, which is more than a person's day. The founder has confirmed the times are incorrect — they describe a batch, not one order. Until they are fixed, every capacity warning on a card will be nonsense | Fix the durations in the map before judging any over-capacity flag. Noted in Still open; not this epic's work |
| 🟡 **Ordering by live stage order instead of the pinned one** | ORD-1 made stage order mutable; a job pinned to v2 must use v2's order | Story 02 walks the pinned version's order explicitly |
| 🟡 **The backlog response shape changes** | Silent breakage in any caller not checked | Enumerate callers before changing it |
| 🟡 **Jobs that predate this epic** | Some may already have steps scheduled individually | Story 01's fourth scenario; the card path must tolerate a partly-scheduled job rather than assume a clean one |
| 🟢 **Migration** | None needed | The link table was built many-to-one for this, with `position` |

## Decided

| Question | Decision | Date |
|---|---|---|
| Reshape the Intelligence Layer for this? | **No.** A map is a process, a job is one run of it. Quantity is data, not structure; structure follows divergence, not count | 2026-10-20 |
| What is a card? | **A job.** One order, all its steps, one person, one pass | 2026-10-20 |
| Per-stage continuity markers and a boundary rule? | **Dropped.** The founder settled it: *"Any order that gets processed will be processed on all the steps at that moment."* No dwell, no partial sittings — so a side table, a resolver function and two stories all disappear | 2026-10-20 |
| Does the Intelligence Layer change? | **No.** Stages, order, text, done-when and expected minutes already publish correctly | 2026-10-20 |
| How does a performer reach an order? | **Directly, from My Jobs** — not only through a day. The grouping already exists; only the entry point is missing | 2026-10-20 |
| Is a card the whole job, or one actor row of it? | **One actor row.** Checked live on 2026-10-20 before building: **7 of 23 existing jobs** have steps across two rows (`sales` and `ops`), so "the whole job" would put one role's work on another person's card. Identical to "the whole job" for any single-row map, including the founder's | 2026-10-21 |
| How is a card-level duration tweak attributed to its steps? | **It is not.** The card's duration is a commitment, the version's per-step minutes are an estimate, and actuals roll up from the steps. Splitting a tweak across steps would invent data and pollute the process-estimate variance — the one figure that must stay clean. Two variances, reported separately | 2026-10-20 |

## Still open

| Question | Why it's the founder's |
|---|---|
| **The planner UI still schedules one step at a time** | Endpoint 583 is live and proven, but the Jobs modal has not been pointed at it, so the backlog still *reads* as cards while the Schedule button still *writes* single steps. One afternoon's frontend work. It was left out deliberately rather than rushed at the end of a long session |
| **The expected minutes are wrong** | 11h 50m across eight stages describes a batch of returns, not one customer's order. Every duration in the map needs revisiting before capacity warnings mean anything. Small job, but it is yours to judge — nobody else knows the real times |
| **What happens when a job genuinely cannot finish in one pass?** | Today's answer is that it always can. The moment one cannot, you are back to splitting a card across days, and dwell comes back with it. Worth knowing now whether that is a real case or truly never |
| **Child jobs — when?** | `parent_work_item_id` exists on `work_item` but is **hardcoded to 0** in the create-job endpoint, so damaged items branching to a repair map cannot be built yet. It is the natural epic after this one |
