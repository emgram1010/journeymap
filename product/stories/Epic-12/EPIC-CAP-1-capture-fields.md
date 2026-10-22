# EPIC-CAP-1 — What gets recorded here

**Status:** 📋 **not started.** Written 2026-10-20.

Makes the journey map carry not just *what to do* at each step, but *what to
record* while doing it — so the performer's screen is generated from the
published version rather than hand-built, and the numbers people write down
can be added up afterwards.

## Why

The founder's framing, kept because it is the clearest statement of the goal:

> I want the intelligence layer to be almost like the DNA of a solution… If the
> job requires quantity, it's quantity. If it requires a dropdown, a dropdown.
> So it could be translated when published.

Today the map compiles into tasks carrying text, an owner and an expected
duration. What actually happened is captured as a **free-text note** on an
append-only log. That is enough to know *that* a step was done, and nothing
more.

The cost of that shows up the moment you ask a normal question. The founder's
own process counts items at intake, finds damage at inspection, and decides a
disposition at triage. Those are numbers and choices. Stored as prose, they
cannot be totalled, compared between orders, or fed back into the leakage
figures the Intelligence Layer exists to produce. "25 chairs, 3 damaged" in a
note is a sentence. The same thing as `counted: 25, damaged: 3` is data.

### The second reason, which matters more

A map that declares its own form is a map that **compiles into a working
screen**. The performer UI stops being something built per process and becomes
something rendered from the version. That is what makes the product work for
the second customer without a developer.

## The rule

> **The row declares the default form. The cell adds, changes, or switches a
> field off. The published version freezes the result.**

Three consequences follow, and they are the whole design:

1. **Setup is cheap.** One declaration per row, not one per cell. The founder's
   map is 8 stages × 1 row — that is one edit instead of eight.
2. **New stages inherit for free.** When ORD-1's seam `+` inserts a ninth
   stage, it already has the row's form. A cell-only design would leave every
   new stage blank.
3. **Specific steps stay specific.** Triage needs a verdict that intake does
   not. The cell supplies it, and only that cell carries it.

## What already exists and is being copied, not invented

| Piece | Where | How CAP-1 uses it |
|---|---|---|
| A per-type default with a per-row override | `journey_lens_planned_work` + `functions/does_planned_work.xs` | **The exact pattern.** A side table holding an explicit override; "no row" means "use the default" |
| One place defines a per-type field set | `journey/actor_template` (ORD-2) | The design-time twin of this epic's run-time form |
| A design-time field set on a cell | `journey_cell.actor_fields` (json) | Proof the shape works on a cell; CAP-1 is its run-time sibling |
| An append-only record of what happened | `activity_log` — `event_type`, `note`, `occurred_at` (server time), `client_event_id` | Captured values are written as events here, not as a mutable field |
| A cache of a replayed log | `work_task.status` ← `logModel.ts::replay` | The precedent for CAP-1's value cache: the log is the truth, the table is a convenience |
| A frozen, hashed definition | `journey_map_version.snapshot` + `content_hash` | The form is added to the snapshot, so it is versioned like everything else |

## Non-goals

- **No new actor type.** See *Decided*.
- **No conditional fields** in v1 ("ask for damage detail only when the verdict
  is repair"). Flagged in *Still open*.
- **No photos, signatures or files.** The closed type set is deliberately
  small; attachments are their own epic with their own storage questions.
- **No per-item-type capture** ("25 chairs, 3 tables" as separate counts in one
  step). *Still open* — it is the founder's live question and deserves its own
  answer.
- **No editing history.** A correction is a new event, never an edit. That is
  `activity_log`'s existing rule and CAP-1 does not weaken it.
- **No change to how tasks are generated.** One task per (stage, working row),
  exactly as now.

## The field types

A **closed set**, on purpose. Closed sets are what let values aggregate, let
validation be real, and let the AI reason about a form it has never seen.

| Type | Stores | Example |
|---|---|---|
| `number` | decimal | `hours_run: 2.5` |
| `integer` | whole number | `counted: 28` |
| `text` | short free text | `note` |
| `choice` | one of a declared list | `verdict: pass \| repair \| retire` |
| `boolean` | yes / no | `customer_notified: true` |

Each field also carries: `key`, `label`, `required`, and for `choice`, its
`options`. Nothing else in v1.

## Error codes

| Code | Meaning | Status |
|---|---|---|
| `E-CAP-001` | **New.** A required field was not recorded, and the step was finished anyway | Needed: finishing without the required evidence is the failure this epic exists to stop |
| `E-CAP-002` | **New.** A recorded value does not match its declared type or options | Needed: a choice outside its list, or text where a number was declared, must be refused at the edge rather than stored and discovered later |
| `E-CAP-003` | **New.** The form has two fields with the same key | Needed: a cell field colliding with an inherited one is ambiguous — the author must rename or explicitly override |

## Stories

### US-CAP-1-01 — A row declares what its steps record

**As a** founder
**I want** to say once what this actor always writes down
**So that** every stage they touch collects it without me repeating myself.

```gherkin
Scenario: A row with no declaration changes nothing
  Given a row that has never been given a form
  When its steps are performed
  Then no fields are shown and the step behaves exactly as today

Scenario: A row's form applies to every one of its stages
  Given the Warehouse Operations row declares counted and damaged
  When any of its 8 stages is opened
  Then both fields are offered

Scenario: A new stage inherits it
  Given the row has a form
  When a ninth stage is inserted on the seam
  Then that stage already offers the row's fields
```

**Method:** a new **side table** `journey_lens_capture` (`journey_lens`,
`capture_fields` json), modelled directly on `journey_lens_planned_work`, plus
its own no-filter `GET` endpoint.

**Counter-measures:**
- 🔴 **Not a column on `journey_lens`.** `updateTableSchema` silently drops
  `filters=trim` validators, confirmed twice on this exact table (CLAUDE.md).
  A side table is the standing workaround and already the house pattern here.
- 🔴 **A side table needs its own GET endpoint or the frontend never sees it.**
  The AUTH-1 trap: correct writes, `undefined` reads, survives a full reload.
- "No row" means "no form", and that must be indistinguishable from today's
  behaviour, so a map nobody has touched cannot change.
- 🟢 **A brand-new table is safe.** The validator bug is in *updating* an
  existing table's schema, not in creating one.

**Done when:** a map with no declarations behaves byte-identically to today,
and a declared form appears on every stage of that row including one inserted
afterwards.

---

### US-CAP-1-02 — A cell adds, changes or switches off a field

**As a** founder
**I want** triage to ask for a verdict that intake doesn't
**So that** each step asks only for what it actually needs.

```gherkin
Scenario: A cell adds a field
  Given the row declares counted and damaged
  When the triage cell adds verdict
  Then triage offers counted, damaged and verdict
  And intake still offers only counted and damaged

Scenario: A cell switches an inherited field off
  Given the row declares damaged
  When the close-batch cell switches damaged off
  Then close-batch does not offer it
  And every other stage still does

Scenario: Off is explicit, not empty
  Then a field switched off is stored as an explicit off
  And is distinguishable from a cell that has never been configured

Scenario: A duplicate key is refused
  When a cell declares a field whose key already comes from the row
  Then it is refused with E-CAP-003 unless marked as an override
```

**Method:** a second side table `journey_cell_capture` (`journey_cell`,
`capture_fields` json holding adds, overrides and explicit offs).

**Counter-measures:**
- 🔴 **"Off" cannot be represented by an absent or falsy value.** `== null` is
  PHP-loose here: `0`, `""`, `false` and `[]` all equal `null` (CLAUDE.md).
  Switched-off must be a stored, explicit marker or it is indistinguishable
  from never-configured — which is exactly the ambiguity this story exists to
  avoid.
- 🔴 `journey_cell` also has `filters=trim` text columns, so again a side
  table, again with its own GET endpoint.
- A cell override must not silently change an inherited field's **type**. A
  `counted` that is an integer on the row and text on one cell makes the whole
  column unaggregatable. Refuse it (`E-CAP-003`).

**Done when:** all four scenarios pass, and switched-off is provably distinct
from never-configured in stored data.

---

### US-CAP-1-03 — One rule resolves the final form for a cell

**As a** founder
**I want** one answer to "what does this step ask for"
**So that** the editor, the publisher and the performer can never disagree.

```gherkin
Scenario: Row only
  Given a row form and no cell configuration
  Then the resolved form is the row's, in the row's order

Scenario: Row plus cell
  Then the resolved form is the row's fields, then the cell's additions
  And an overridden field keeps the row's position, not the cell's

Scenario: Switched off
  Then a field switched off at the cell is absent from the resolved form

Scenario: Deterministic
  When resolved twice over unchanged data
  Then the result is identical, including field order
```

**Method:** one server-side function, `journey/resolve_capture`, taking a cell
and returning its final ordered field list. Every caller reads it — the editor,
the publish serializer, the performer screen.

**Counter-measures:**
- 🔴 **Do not write this twice.** CLAUDE.md's house rule, earned in LOG-1: a
  second copy of a rule eventually disagrees with the first and sounds equally
  certain. The server resolves; the client renders what it is given.
- 🔴 **No `conditional` in the merge loop may read a variable written earlier
  in the same iteration** — the documented silent-discard shape that ORD-2
  found live in six places. Resolve to plain rows first, then merge in a second
  pass that only tests the loop item.
- **Field order must be stable**, because it is hashed in story 04. An
  override keeps the row's position so that editing a label cannot reorder the
  form and invalidate every stored hash.
- `|get` with a variable key throws away its default (CLAUDE.md) — pre-seed
  every key or check for null explicitly.

**Done when:** the four scenarios pass and two consecutive runs over unchanged
data produce byte-identical output.

---

### US-CAP-1-04 — The published version carries the form

**As a** founder
**I want** the form frozen with the version
**So that** a job in flight cannot have its questions changed underneath it.

```gherkin
Scenario: The form is in the snapshot
  When a map with capture fields is published
  Then each work cell in the snapshot carries its resolved form

Scenario: Changing a form changes the version
  Given a published map
  When a capture field is added
  Then the map shows draft changes
  And publishing produces a new version with a different content hash

Scenario: A job in flight is unaffected
  Given a job pinned to v2
  When v3 changes a form
  Then the job still asks v2's questions

Scenario: Hashes still agree across both sides
  Then the server's hash and the TypeScript twin's hash match, as pinned
```

**Method:** extend `pub/build_map_snapshot` to include each work cell's
resolved form, and update `versionHash.ts` in lockstep.

**Counter-measures:**
- 🔴 **This changes what a version hashes.** PUB-1 pinned the expected hash on
  *both* the server and the TypeScript side precisely so drift fails a test
  rather than silently invalidating stored hashes. Both sides must change
  together, and the pinned expectations must be updated deliberately, never to
  "make the test pass".
- 🔴 **Hashing must not go through `json_encode`** (CLAUDE.md): key order,
  whitespace and unicode escaping differ between encoders. Build the string by
  explicit concatenation in a fixed field order, exactly as `canonical_hash`
  already does.
- Existing versions have no form. Their hashes must still verify — so absence
  must serialize to nothing, not to `"[]"` or `"null"`.
- A form change should surface on the drift badge the same way a reorder does.

**Done when:** an existing pre-CAP-1 version still verifies unchanged, a new
version carries its forms, and both hash implementations agree.

---

### US-CAP-1-05 — The performer records it

**As John, doing the work**
**I want** the step to ask me for exactly what it needs
**So that** I am not guessing what to write in a note.

```gherkin
Scenario: The screen is generated, not built
  Given a step whose version declares counted, damaged and verdict
  When John opens it
  Then he sees those three inputs, with their labels and options
  And nothing was coded for this particular process

Scenario: Required means required
  When John finishes a step without a required field
  Then it is refused with E-CAP-001 and the step stays open

Scenario: A value must match its type
  When a choice value outside the declared options arrives
  Then it is refused with E-CAP-002

Scenario: A correction is a new event
  When John records a value, then corrects it
  Then both are in the log, in order, and the later one wins
```

**Method:** values are written as `activity_log` events carrying a typed
payload, with a new `work_task_capture` table holding the current resolved
value per field for querying — the same relationship `work_task.status` has
with the log: **the log is the truth, the table is a convenience.**

**Counter-measures:**
- 🔴 **The log stays append-only.** No update route, no delete route. A
  correction is another event. "A log you can edit is not evidence of
  anything" — `activity_log`'s own header.
- 🔴 **`db.patch` on a `json` column MERGES, it does not replace** (CLAUDE.md,
  critical). Any write that is meant to be "this is now exactly X" needs the
  two-step `null`-then-value patch.
- Reuse `client_event_id` for idempotency — one tap is one row however many
  times the request arrives. Offline retries are the normal case here.
- An untouched `decimal` reads as `0`, not `null`, so "was this recorded" must
  come from the presence of a capture row, never from a value being non-zero
  (CLAUDE.md, AUTH-1).
- The form comes from the job's **pinned version**, never the live map.

**Done when:** a step with a declared form renders with no process-specific
code, a missing required field blocks finishing, and a correction leaves both
events in the log.

---

### US-CAP-1-06 — The values add up across jobs

**As a** founder
**I want** to ask "how many items were damaged last month"
**So that** the thing I made people record actually pays for itself.

```gherkin
Scenario: One field across many jobs
  Given 20 jobs recorded damaged counts
  When the totals are read for a map
  Then the sum and the per-job values come back

Scenario: Only comparable things are compared
  Given a field whose type changed between versions
  Then the two are reported separately, not silently added

Scenario: Scoped to the account
  Then a caller only ever sees their own account's values
```

**Method:** a read endpoint returning captured values for a map, grouped by
field key and version.

**Counter-measures:**
- 🔴 **Never add across a type change.** If `counted` was an integer in v2 and
  a decimal in v3, summing them silently produces a number that is wrong in a
  way nobody can see. Group by `(field_key, type, version)` and let the caller
  decide.
- Tenancy: scope by account, using SEC-1's existing helpers, not by map id
  alone.
- `db.query`'s `return = {type: "list"}` must not use `paging` — it stops being
  a plain array (CLAUDE.md).

**Done when:** totals match a hand count on a seeded fixture, and a deliberate
type change is reported as two groups rather than one sum.

## MVP scope

**In:** stories 01–06.

**Deferred:** conditional fields; per-item-type capture; photos and
attachments; AI-proposed forms; editing a form on a published version;
back-filling forms onto historical jobs.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | Capture definitions follow the map's ownership; recorded values are read through account-scoped queries (SEC-1 helpers) |
| Validation | Type and options enforced server-side on write (`E-CAP-002`); required enforced on finish (`E-CAP-001`); duplicate keys refused (`E-CAP-003`). The UI's validation is a convenience, never the guard |
| Error codes | `E-CAP-001`, `E-CAP-002`, `E-CAP-003` added to `src/ops/errorCatalog.json` |
| Events | Every captured value is itself an `activity_log` event; every refusal logs `rejected` so denials reach the Health page |
| Table constraints | **Two new side tables and one new value table. No existing table's schema is altered** — `updateTableSchema` drops `filters=trim` validators, confirmed twice. Creating a new table is unaffected |
| Delete behaviour | Capture definitions are deleted with their row or cell. Recorded values are **never** deleted — they are the record |
| Rollback | Stories 01–03 are additive. Story 04 is the risky one: it changes the content hash. Commit before it, and keep the pinned hash tests on both sides |
| No silent failure | A value that does not match its declaration is refused at the edge, never stored to be discovered later |
| Testing | Live exercises run on a **clone**, never the founder's own map or job |

## Test Results

_Not started._

| Story | Tests | Result |
|---|---|---|
| 01 | Undeclared row identical to today; form applies to all stages; inherited by a newly inserted stage | — |
| 02 | Add, switch off, explicit-off distinguishable from never-set, duplicate key refused | — |
| 03 | 4 resolution scenarios incl. determinism and stable field order | — |
| 04 | Pre-CAP-1 version still verifies; new version carries forms; both hash implementations agree; job in flight unaffected | — |
| 05 | Generated screen with no process-specific code; required blocks finish; bad choice refused; correction appends | — |
| 06 | Totals match a hand count; a type change reports two groups | — |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| 🔴 **Changing the content hash** | Every stored hash could become invalid, and the failure looks like tampering | Change both implementations together; keep PUB-1's pinned expectations on both sides; prove an old version still verifies |
| 🔴 **Altering an existing table** | `updateTableSchema` drops `filters=trim` validators, confirmed twice on these exact tables | New tables only, side tables for anything attached to an existing row |
| 🔴 **A side table with no GET endpoint** | AUTH-1: correct writes, `undefined` reads, survives a full reload | Each side table ships with its own endpoint and its own frontend fetch |
| 🔴 **"Off" stored as a falsy value** | `0`, `""`, `false` and `[]` all equal `null` here, so cleared and never-set become indistinguishable | An explicit stored marker, with a test proving the two are distinguishable |
| 🟡 **Form bloat** | A 30-field form is one nobody fills in, and partial data is worse than none | House rule, written into the UI copy: declare a field only when a decision or a measurement depends on it |
| 🟡 **Summing across a type change** | Produces a confident number that is quietly wrong | Group by key, type and version; never silently add |
| 🟡 **Two copies of the resolver** | The editor and the performer would eventually disagree about what a step asks | One server-side function; the client renders what it is given |
| 🟢 **Capture on a map nobody has configured** | Nothing changes | "No row" means "no form", proven byte-identical to today |

## Decided

| Question | Decision | Date |
|---|---|---|
| Should this be a new actor type? | **No.** The row that does the work is the row that records it. Tasks are generated per row that does planned work — a capture row doing none would have no task to attach a form to, and one doing some would duplicate a task at every stage. Capture is a property of a working row | 2026-10-20 |
| Row-level or cell-level fields? | **Both, layered.** The row declares the default; the cell adds, overrides or switches off. Cheap setup, new stages inherit for free, specific steps stay specific | 2026-10-20 |
| What is it called? | **Capture fields.** Not `record_fields` — "record" reads as both noun and verb and gets muddled in conversation. Not `actor_fields` — that name is taken by the design-time set. UI label: **"What gets recorded here"** | 2026-10-20 |
| Open or closed type set? | **Closed:** number, integer, text, choice, boolean. Closed sets are what make values aggregate, validation real, and AI reasoning possible | 2026-10-20 |
| Where do recorded values live? | **The log is the truth; the table is a convenience.** Values are `activity_log` events with a cache table for querying — the same relationship `work_task.status` already has | 2026-10-20 |

## Still open

| Question | Why it's the founder's |
|---|---|
| **Do you still want a distinct row type?** | This epic says no, for the task-generation reason above. If you want it anyway, what changes is: the new row would carry forms *for other rows*, which needs a rule for which row's task each form attaches to — and that rule is the thing I could not make come out cleanly. Reversible, but worth a conversation before story 01 |
| **Conditional fields?** | "Ask for damage detail only when the verdict is repair." Genuinely useful and genuinely more complex — it needs a condition language, and conditions in a hashed snapshot need care. Recommend v2, after you have used flat forms for a while |
| **Per-item-type capture?** | Your live question: one step handling 25 chairs and 3 tables. Options are separate keys (`counted_chairs`, `counted_tables`), or a repeating group keyed by item type. The second is more correct and much more work. Recommend separate keys until a third item type appears |
| **Should the AI propose the fields?** | It can read "assign a verdict" and suggest a choice field with three options. Recommend: the AI proposes, you approve — never sets them silently, the same rule as the continuity markers in BLK-1 |
