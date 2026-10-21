# Epic-12 — What gets recorded here

Created 2026-10-20, from a design conversation about making the Intelligence
Layer the complete specification of a process — the founder's words:

> I want the intelligence layer to be almost like the DNA of a solution. It
> contains everything it needs to create the necessary jobs or tasks. If the
> job requires quantity, it's quantity. If it requires a dropdown, a dropdown.
> So it could be translated when published.

The sharper form of the same idea: **the map is source code, publish is the
compile step, the job is the running instance.** Today the map compiles into
tasks with text, an owner and a duration. It does not yet compile into a
**form** — what the person must record while doing the step.

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [CAP-1 — What gets recorded here](EPIC-CAP-1-capture-fields.md) | A row declares the fields its steps record; a cell adds or switches off its own; publish freezes them; the performer's screen is generated from them | 📋 **Not started** — 6 stories |

## What the map already compiles into

Verified live 2026-10-20 by reading the version snapshot's own definition:

- The map title, and the **stages in order** with their owner.
- Each row flagged with whether it **does planned work** — which is why the
  founder's "Description" row produced no tasks and "Warehouse Operations"
  produced eight.
- Per work cell: the **task text, the done-when, and the expected minutes**.
- Any **links** to sub-maps.
- Plus a `content_hash` for tamper detection and the `readiness_report`
  recording why the version passed the gate.

CAP-1 adds one thing to that list: the **form**.

## The shape, in one picture

```
CELL  "inspect"   —  Warehouse Ops × stage s2
├─ task:        Inspect every item against the condition standard
├─ done when:   No item leaves without a verdict and an inspector
├─ expected:    120 min
└─ capture:     counted   number   required        ← from the ROW
                damaged   number   required        ← from the ROW
                verdict   choice   [pass|repair|retire]  ← from the CELL
                note      text     optional        ← from the ROW
```

**The row declares the default. The cell adds, changes or switches off.** You
set it up once per row, then touch only the two or three stages that are
genuinely different.

## Build order

| # | Story | Effort | Model |
|---|---|---|---|
| 01 | A row declares what its steps record | **S–M** | Sonnet 5.5 |
| 02 | A cell adds, changes or switches off a field | **M** | Sonnet 5.5 |
| 03 | One rule resolves the final form for a cell | **M** | Opus 5 |
| 04 | The published version carries the form | **M–L** | Opus 5 — it changes the content hash |
| 05 | The performer records it | **M** | Sonnet 5.5 |
| 06 | The values add up across jobs | **S–M** | Sonnet 5.5 |

**Total: roughly 2 working sessions.** Story 04 is the one to be careful with:
it changes what a version hashes, and the hash is pinned on both the server and
the TypeScript side.

## The disagreement recorded in this epic

The founder asked for this as a **new type of actor** — a row whose job is to
hold the form fields. This epic does **not** build it that way, and the reason
is in the epic's *Decided* section:

- The row that **does** the work is the row that **records** it. Capture is a
  property of a working row, not a separate kind of row.
- Tasks are generated per row that does planned work. A capture row that does
  no planned work generates no task, so there is nothing for the form to attach
  to. One that *does* generate tasks would duplicate a task at every stage.

If the founder still wants a distinct row type after reading that, *Still open*
in the epic says exactly what would change. It is a reversible decision.

## Relationship to the other open epics

- **[Epic-11 / BLK-1](../Epic-11/EPIC-BLK-1-one-card-per-sitting.md)** — one
  card per sitting. Independent of this; either can go first. BLK-1 changes how
  steps are *grouped*, CAP-1 changes what each step *collects*.
- **Epic-10 / ORD-2** — done. Its `journey/actor_template` is the pattern CAP-1
  copies: one place defines a per-type default, every caller reads it.
