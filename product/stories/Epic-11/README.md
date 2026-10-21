# Epic-11 — One card per order

Created 2026-10-20, from a working session that went end to end through the
product for the first time: map → publish → plan → attach → job → schedule →
perform. Rewritten the same day, smaller, after the founder settled the
question the design hung on.

The feature, in the founder's words:

> In execution, the user is able to see each job that represents an order of a
> turnaround. Open it up. And work through the different stages.

Today scheduling makes one card per stage, so a single customer's return
arrives on the board as eight separate cards — and the performer can only
reach it through a day, so one order looks like several fragments.

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [BLK-1 — One card per order](EPIC-BLK-1-one-card-per-order.md) | One card is one order's work for one actor row, scheduled in one action; the performer opens it and walks every stage start to finish | ✅ **Done (2026-10-21)** — 4 stories built and proved live, 05 deferred |

**One correction made before building (2026-10-21):** a card is one job's steps
**for one actor row**, not the whole job. A live check found **7 of 23 existing
jobs** with steps across two rows (`sales` and `ops`) — grouping by job alone
would have put one role's work on another person's card. For any single-row
map, including the founder's `item-turnaround`, the two are identical.

## What changed, and why it got smaller

An earlier draft of this epic built a general grouping mechanism: a per-stage
"continues the one before" marker, a side table to hold it, a resolver
function, and a rule deciding where one group ended and the next began. All of
that existed to handle an order worked across several sittings, with dwell time
in between.

The founder deleted the need for it in one sentence:

> Any order that gets processed will be processed on all the steps at that
> moment.

No dwell, no partial sittings. **A card is simply the whole job.** That removed
two stories, one side table and one function, and made the grouping rule
trivial. The epic went from six stories to five, and from needing a schema
change to needing none at all.

## Why this is not a change to the Intelligence Layer

The founder's first instinct was to reshape the map — one map per task, or
stages as subtasks. Explored and rejected, for reasons worth keeping:

- A **map is a process**: versioned, hashed, published, reused forever.
- A **job is one run of it**: Mr. Jones's return is a job, not a map.
- **Quantity is data, not structure.** 25 chairs and 3 tables belong in the
  job's `attributes`, not as 28 records.
- **Structure follows divergence, not count.** You create a child job when a
  subset takes a *different path* — damaged tables going to a repair map —
  never because there are more of something.

**The Intelligence Layer needs zero changes for this epic.** Stages, their
order, their text, their done-when and their expected minutes already publish
correctly and already arrive in the job.

## Build order

| # | Story | Effort | Model |
|---|---|---|---|
| 01 | The backlog offers whole jobs, not loose steps | **S–M** | Sonnet 5.5 |
| 02 | Schedule a whole job in one action | **M** | Opus 5 — it writes the links |
| 03 | Take a job back off the schedule | **S** | Sonnet 5.5 |
| 04 | The performer opens a job and walks it | **M** | Sonnet 5.5 |
| ~~05~~ | ~~Reach a job without going through a day~~ | — | **Deferred** |
| 06 | A tweak is a promise about the card, not its steps | **S–M** | Opus 5 — it decides what variance means |

**Story 05 is deferred.** The founder's "one pass, no dwell" decision removed
the need: if an order is worked in a single day, the day view already shows the
whole order, and a job-scoped screen reveals nothing new. Re-open it only if
orders start spanning days.

**Build order: 01 → 02 → 03 → 04 → 06**, backend before UI, so the one
destructive story is proven over real HTTP before anything leans on it.

**Total: roughly one working session.** Stories 02 and 06 earn Opus: 02 writes
the links that make a step un-schedulable anywhere else, and a half-written card
is permanent until someone unpicks it by hand; 06 settles what variance means
once a card covers several steps, and getting that wrong corrupts the number the
product exists to produce.

Story 06 was added after a holistic pass over publishing, planning and
execution found it as the **only** gap the rest of the epic did not already
answer — see "What the holistic pass found" below.

## What already exists, verified live 2026-10-20

This epic is cheap because the groundwork was laid on purpose.

- **`planner_task_work_task` is already many-to-one**, with a `position`
  column. Its header says why: *"blocks are coming (US-SCHED-1-02, deferred):
  one slot covering several consecutive steps of a job. Keeping the
  relationship many-to-one from the start means blocks arrive without a
  migration."*
- **`work_task_id` is already unique** there, so a step can be scheduled at
  most once — the constraint that makes a card safe.
- **The performer screen already groups by job.** `sessionModel.ts`: *"a
  session groups by JOB (`work_item_id`) because that is what a performer
  actually experiences: one customer, one flow, start to finish."*
- **`SessionScreen` already walks steps in order** with the next highlighted,
  and already renders `subSteps`.
- `SnapshotItem` already carries `work_task_ids: number[]`.

**No migration. No new table. No schema change of any kind.**

## The one thing that is wrong in the data

The live `item-turnaround` map's eight stages total **11h 50m**, which is more
than one person's day. The founder has confirmed those times are incorrect —
they describe a batch of returns, not a single customer's order. Until they are
corrected, every capacity warning on a card will be nonsense.

That is a data fix in the map, not work for this epic, but it should happen
before anyone judges an over-capacity flag.

## What the holistic pass found

Each layer was checked against what a card-covers-several-steps change needs,
on 2026-10-20:

| Layer | Refactor? | Why |
|---|---|---|
| **Map → version** (publish) | ❌ none | The snapshot already carries stage order, owner, task text, done-when and minutes — confirmed live through `planner/job_step_hydration` |
| **Version → job** (work tasks) | ❌ none | Already one task per stage, in the pinned version's order |
| **Backlog** | ✅ read shape | Story 01 |
| **Scheduling** | ✅ the real one | Stories 02–03 |
| **Plan → live** (publish to live) | ❌ none | `functions/live/build_publication.xs` already collects several `work_task_ids` per item and joins them into the frozen publication line |
| **Execution** | ✅ small | Stories 04–05; the grouping already exists |

**Both kinds of publishing already work for this.** That is not luck — the link
table was made many-to-one on purpose, and the publication format was written
to carry a list.

The one thing none of that answered was what a duration **tweak** means once a
card covers several steps. That is story 06.

## Relationship to the other epics

- **Completes `US-SCHED-1-02` and `US-SCHED-1-03`**, deferred in
  [EPIC-SCHED-1](../phase-4/EPIC-SCHED-1-scheduling-and-tweaks.md).
  Owner-role matching (`US-SCHED-1-04`) stays deferred.
- **[Epic-12 / CAP-1](../Epic-12/EPIC-CAP-1-capture-fields.md)** — capture
  fields, so a step can ask for a count or a dropdown rather than free text.
  **Parked by the founder.** Independent of this epic; either can go first.
- **Epic-10 / ORD-2** — done. Its `journey/actor_template` is the pattern this
  codebase reaches for whenever a rule would otherwise be copied.
