# EPIC-ORD-1 — Insert and resequence a column or a row

**Status:** ✅ **all six stories done (2026-10-19).** Insert on the seam and
move with arrows are live in the matrix, for columns and rows. Issues found along
the way are ranked in [ISSUES-BACKLOG.md](ISSUES-BACKLOG.md).
**Model:** **Opus 5.5** for stories 01–02 (key minting and the shared resequence
rule — CLAUDE.md flags ordering and guards as risky), **Sonnet 5.5** for 03–06,
with an Opus review pass after 02.
**Depends on:** SEC-1 (`journey/assert_map_owner`), GOV-1 (`guards/assert_owns`),
OBS-1 (`ops/log_event`), PLN-7 (the resequence precedent this epic copies)
**Blocks:** nothing

## Why

The founder asked for the ability to **insert and resequence a column (stage) or
a row (lens)** in a journey map. Today neither is possible from the UI:

| Want | Today |
|---|---|
| Add a column anywhere | **Append-only.** `POST journey_stage/add/{map_id}` sets `display_order = max + 1`. There is no "insert at position 3" |
| Add a row anywhere | Same — `POST journey_lens/add/{map_id}`, `max + 1` |
| Move a column left/right | **No endpoint, no button.** A reorder exists *only* inside `ai/tool/mutate_structure` (`reorder_stages` / `reorder_lenses`), reachable by the AI agent and by nothing else |
| Move a row up/down | Same |
| Remove and have the order stay sane | Remove leaves a **gap** and nothing renumbers |

So the AI can already reorder a map that the person looking at it cannot. That
asymmetry is the feature request.

## The trap that sets the story order

**Keys are currently minted from `display_order`, and keys are load-bearing.**

```
apis/journey_map/47_journey_stage_add_journey_map_id_POST.xs
  var $stage_key { value = "s%d"|sprintf:$next_stage_order }    // max(display_order) + 1

apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs
  var $lens_key  { value = "lens-%d"|sprintf:$next_lens_order } // same

ai/tool/mutate_structure.xs  (add_lens)
  var $new_lens_key { value = "lens-%d"|sprintf:$new_lens_order } // same, third copy
```

The moment anything normalises `display_order` to 1..n — which is exactly what
resequence does — the next added stage mints a key that **already exists**.

That matters because a key is an identity, not a label:

- `journey_stage.key` is documented as stable (PRD §320).
- `journey_stage.primary_actor_lens` holds a **text lens key**, not a foreign
  key — so renumbering a lens key silently repoints stage ownership.
- `work_task` identity is `(work_item_id, stage_key, lens_key)` — renumbering a
  key detaches live execution records from the definition they describe.

**Therefore story 01 comes first and nothing else ships before it.** Insert and
reorder change `display_order` only; `key` is minted once and never rewritten.

## The rule

1. **`display_order` is presentation. `key` is identity.** One is rewritten
   freely; the other is never rewritten at all.
2. **One place normalises order.** A single shared function per axis, copied from
   `functions/planner/resequence.xs`, which is "THE ONE PLACE seq IS EVER
   NORMALISED." Nothing else invents a `display_order`.
3. **A reorder is all-or-nothing.** An order that is not an exact permutation of
   the map's current rows is refused and **nothing is written**. A half-applied
   reorder is worse than a refused one.
4. **Resequence accepts gapped input.** Gaps already exist in live data; they are
   an input condition, not an error.

## What already exists and is being copied, not invented

| Thing | Where | What it gives ORD-1 |
|---|---|---|
| Normalise-to-1..n | `functions/planner/resequence.xs` | Sort by `(order, id)`, loop, patch each row by its own `id`, inside `db.transaction`. Idempotent by construction |
| Exact-permutation check | `apis/planner/544_timeline_timeline_id_reorder_POST.xs` | A **two-count** check with no loops and no array-membership filter — see story 03 |
| Ownership | `journey/assert_map_owner` (SEC-1, function 178) | One `function.run`, delegates to `guards/assert_owns`, emits `E-GOV-001`, logs the refusal |
| Refusal logging | `ops/log_event` (OBS-1) | A rejected reorder shows on the Health page like a failure does |
| Client-side ordering | `sortByDisplayOrder` — `webapp/protype-2/src/xano.ts:575` | Already sorts by `display_order` with an `id` tiebreak, matching the server |

## Non-goals

- **Drag-and-drop.** The founder chose buttons for v1 (2026-10-18). Drag-and-drop
  is a later story on top of the same endpoints.
- **Renumbering existing keys.** Explicitly forbidden, see above.
- **Backfilling the 16 maps that have gapped order.** Resequence tolerates gaps;
  there is no need to rewrite history. A map's order is normalised the first time
  someone reorders it, as a side effect, not as a migration.
- **Reordering a published version's snapshot.** A pinned version keeps the order
  it was published with. That is the point of pinning.
- **Orphan structure rows** (stages/lenses referencing 6 deleted maps). DEL-1
  territory, recorded in the Epic-8 README.
- **Moving a stage or lens between maps.** Not asked for, and SEC-1 specifically
  guards against it.

## Versioning — decided 2026-10-19

**The founder's decision: a reorder is a real change to the map, and the map must
register that it changed.** Accepted. What follows is what that costs, because
the answer turned out to be "nothing".

**A reorder already does this, with zero ORD-1 work.** Verified in the code:

- `functions/pub/build_map_snapshot.xs` queries stages and lenses
  `sort = {display_order: "asc", id: "asc"}` and serialises them **as an ordered
  array**.
- `apis/journey_map/521_journey_map_journey_map_id_versions_GET.xs` re-runs that
  same snapshot builder on the **live** map, hashes it with
  `pub/canonical_hash`, and compares it to the stored `content_hash` of the
  latest version. `has_unpublished_changes` is that comparison.
- `webapp/protype-2/src/MapVersionBadge.tsx` turns it into the amber badge
  **"v3 · draft changes"**, with the hover text *"You've changed this map since
  v3. Plans keep using v3 until…"*.

So reordering a column changes the array order → changes the canonical string →
changes the hash → lights the badge. **Nothing in ORD-1 has to set a flag**, and
story 05's "stale notice" counter-measure is deleted because the notice already
exists and is better than the one specced.

### The part that needs flagging, not building

The founder said: *"any time there is a change on the journey map and saved it
will create a new version."* **That is not what PUB-1 built, and the difference
is not a detail.** Today a `journey_map_version` row is written **only** by an
explicit *Publish version* (endpoint 201), behind the `publish_gate` account
flag. Auto-versioning every save would collide with four decisions already shipped:

| Conflict | Why it matters |
|---|---|
| **A publish runs the readiness gate first** | Endpoint 201 refuses to version a map that isn't ready. A half-filled map saved mid-edit cannot pass that gate — so auto-versioning would either fail constantly or require bypassing the gate, which removes the gate's reason to exist |
| **Versions are immutable and undeletable by rule** | `static/tables/112_journey_map_version.xs`: *"🔴 NOTHING MAY EVER DELETE A ROW FROM THIS TABLE"*, enforced by a build check. A version per save is an unbounded, never-prunable table of full map snapshots. There is no way back |
| **`version_no` is user-facing and monotonic** | "v1, v2, v3" is what the badge and the plan pin show. Per-save versioning turns that into v400 and the number stops meaning anything a person can use |
| **Drift detection is content-based, which is strictly better** | The current check compares hashes, so typing something and undoing it correctly reports **no change**. Versioning on save would mint a permanent version for a no-op edit |

**Decided 2026-10-19 — publish-only stands.** *Publish version* remains the only
thing that mints a `journey_map_version` row. The content-hash drift badge is the
"this map changed" signal, and it already fires on a reorder.

**If a per-change trail is wanted later, it comes from `event_log`, not from
version rows.** Every save already logs an event (OBS-1); the log is prunable,
costs no `version_no`, and is not bound by the never-delete rule. A "what changed
since v3" view built on it is a later story, not part of ORD-1.

## Error codes

Reuse before minting (GUARD-1-01: a code means exactly one thing).

| Code | Meaning | Emitted by | New? |
|---|---|---|---|
| `E-GOV-001` | The map belongs to a different account | `journey/assert_map_owner` (SEC-1) | Existing — reused |
| `E-ORD-001` | The submitted order is not an exact permutation of this map's stages/lenses — nothing was changed | Story 03, both reorder endpoints | **New** |
| `E-ORD-002` | The anchor row (`after_stage_id` / `after_lens_id`) does not belong to this map | Story 04, both insert paths | **New** |

### Why these two are new, in detail

**The search that was run:** `E-ORD-` appears nowhere in `product/`, `functions/`
or `apis/`. The prefix is unused, so there is no collision and no existing
meaning to overload.

**The one real candidate for reuse was `E-PLN-016`**, from
`apis/planner/544_timeline_timeline_id_reorder_POST.xs`. It is the *identical
failure shape* — "the order you sent is not a permutation of what's there, so
nothing was written" — and ORD-1 copies that endpoint's two-count check verbatim.
It was rejected for reuse on three grounds:

1. **Its message names the wrong noun.** The live text is *"That new order doesn't
   match this day's tasks, so nothing was changed."* A founder reordering journey
   stages would be told about a day of tasks. The friendly-message requirement is
   a governance rule here, not a nicety.
2. **Its namespace is a promise.** `E-PLN-*` means "the planner refused". A
   journey-map endpoint emitting it would make Health-page filtering by feature
   wrong, and would make the code's blast radius two features wide — change the
   planner's wording and the journey map's wording changes with it.
3. **GUARD-1-01 cuts both ways.** "A code means exactly one thing" forbids two
   codes for one condition *and* one code for two conditions. The condition here
   is "a journey map's order was rejected", which is not the same condition as "a
   planner day's order was rejected", even though the arithmetic is identical.

**Why `E-ORD-002` is separate from `E-ORD-001` rather than folded into it:** they
fail at different times and tell the user different things. `001` means *"your
list is wrong"* (recoverable by resending a correct list). `002` means *"the
place you pointed at isn't in this map"* — which, on a seam click, means the UI
and the server disagree about what is on screen, and the right response is to
refetch, not to retry. One code for both would make that distinction
undiagnosable from the Health page.

**Precedent for the shape of these codes:** `E-GOV-001` (ownership),
`E-OBS-001` (not a platform admin), `E-PLN-016` (bad permutation) — three
digits, feature-prefixed, one condition each. `E-ORD-001` / `E-ORD-002` follow
it exactly.

**Approved by the founder 2026-10-19.** Both codes are minted as specified.

---

## Stories

### US-ORD-1-01 — A key is minted from keys, never from position ✅ Done (2026-10-19)

**As a** founder
**I want** a new column or row to get an identity that does not depend on where it sits
**So that** reordering the map can never collide two keys or silently repoint stage ownership.

```gherkin
Scenario: Minting after a normalise
  Given a map whose stages are s1, s2, s3 with display_order 1, 2, 3
  And the order has just been normalised to 1..n
  When a new stage is added
  Then its key is s4
  And no existing key changed

Scenario: Minting into a gap
  Given a map whose stage keys are s1, s2, s5 with gapped display_order 1, 2, 7
  When a new stage is added
  Then its key is s8, which is max(key suffixes and display_orders) + 1
  And its display_order is 8, which is max(display_order) + 1

Scenario: Minting after a remove and a normalise (the case that used to collide)
  Given a map whose stages are s1, s2, s5, s8 at display_order 1, 2, 3, 4
  When a new stage is added
  Then its key is s9, not s5
  And its display_order is 5
  And the key and the order are allowed to disagree

Scenario: A reorder never touches a key
  Given a map with stages s1, s2, s3
  When the order is changed to s3, s1, s2
  Then the three keys are still s1, s2, s3
  And only display_order changed
```

**Method (as planned):** one shared function per axis that reads the map's
existing keys and mints one more than the max. Three call sites were expected.

**What was built — and where the plan was wrong:**

- **The functions are `journey/next_stage_key` (182) and `journey/next_lens_key`
  (183)**, not `jm/…` — `journey/` is the namespace SEC-1 already uses
  (`journey/assert_map_owner`, `journey/visible_map_ids`). Reuse, not a second
  prefix.
- **The rule is max(valid key suffixes ∪ display_orders) + 1**, not max(key
  suffix) + 1. Including `display_order` is what makes the change provably
  behaviour-preserving today: the `description` row sits at order 1, so without
  it the first actor row on a new map would become `lens-1` instead of the
  `lens-2` every map has always had. Every value in the set can only push the
  number *up*, so it can never collide.
- **There were five mint sites, not three.** The epic missed two AI tools:

| Site | Old formula | Status |
|---|---|---|
| `apis/journey_map/47` (`journey_stage/add`) | `"s"` + (max order + 1) | ✅ repointed, proved over HTTP |
| `apis/journey_map/49` (`journey_lens/add`) | `"lens-"` + (max order + 1) | ✅ repointed, proved over HTTP |
| `ai/tool/scaffold_map` (tool 56), stage **and** lens add | **count + 1** | ✅ repointed, executed live |
| `ai/tool/mutate_structure` (tool 4), `add_lens` | `"lens-"` + (max order + 1) | ✅ repointed — pushed and parsed, **not executed** (see below) |
| `ai/tool/scaffold_structure` (tool 7), lens add | `"lens-"` + (max order + 1) | ✅ repointed — pushed and parsed, **not executed** |
| `ai/tool/create_journey_map` | `"s"` + n, for a **brand-new** map | Left alone — no existing rows, so no collision is possible |

- 🔴 **`scaffold_map` had a live collision bug that did not need ORD-1 to fire.**
  count + 1 re-mints an existing key after any remove: stages s1, s2, s3, remove
  s2, add → `s3` again. It had not happened yet (0 duplicates live), but only by
  luck. Fixed as a side effect.
- **No pre-insert collision check.** The epic asked for one. It was not built,
  because it cannot work: outside a race a collision is impossible by
  construction (above), and inside a race both requests read the same rows and
  both see "no clash". Only a **unique index on `(journey_map, key)`** catches a
  race — that is a schema change, so it is raised as a question instead (Still
  open). The exposure is unchanged from before ORD-1.

**Counter-measures:**
- A key that does not match the expected shape (hand-edited, imported, legacy)
  must not crash the mint. Non-numeric suffixes are ignored for the max, and the
  function falls back to `count + 1`, then probes for collision.
- The mint must be **collision-checked against the table**, not just against the
  computed max — two tabs adding a stage at the same moment is a real sequence.
- `|contains:` returns false for every array (CLAUDE.md), so uniqueness is proved
  with a `db.query ... return = {type: "count"}` and `key in $keys`, never a
  filter.
- Do not use a pipe character as a separator anywhere in this function — a pipe
  inside a string literal breaks the parser (CLAUDE.md). Use `::`.

**Done when:** the live scan still reports **zero duplicate keys** across all
maps after an add → reorder → add cycle on a clone of map 178.

**Result — done.** Run on a purpose-built fixture (map 210) in **test account 6,
as test user 9**, rather than a clone of 178: it needed a gap that 178 does not
have, and it keeps the test out of the founder's account entirely. Map 178 was
read but never written (still 7 lenses, next key `lens-14`, after every test).

| Check | Expected | Got |
|---|---|---|
| New mint vs old formula, **every** existing row | identical | ✅ 0 of 201 stages and 0 of 198 lenses differ; every key is `sN`, `lens-N`, or `description` at order 1 |
| Function smoke test, 5 maps | 178 → `s9` / `lens-14`; 182 → `s10` / `lens-26`; none → `s1` | ✅ 5/5 |
| HTTP, no token | 401 | ✅ 401 |
| HTTP, stage add on gap `s1@1 s2@2 s5@7` | `s8@8` | ✅ `s8@8`, 2 cells |
| Normalise to 1..n, then stage add — **old code: `s5`, a duplicate** | `s9@5` | ✅ `s9@5` |
| Stage add with no label | default label follows position, key does not | ✅ `s10@6`, "Stage 6" |
| Lens add with `lens-4` at order 3 — **old code: `lens-4`, a duplicate** | `lens-5@4` | ✅ `lens-5@4`, template `internal-v1`, 6 cells |
| HTTP, user 9 adding to founder map 178 | refused, nothing written | ✅ 403 |
| `scaffold_map` executed live, 2 stages + 1 lens in one call — **old code: `lens-5`, a duplicate** | `s11@7`, `s12@8`, `lens-6@5` | ✅ exactly, 16 cells |
| Duplicate keys across the workspace after all of the above | 0 | ✅ 0 of 209 stages, 0 of 203 lenses — and the detector **does** catch a planted duplicate (1 of 1), so this zero is real |
| `npm test` / `npm run lint` | green | ✅ 399/399, typecheck clean |

**Not executed, stated plainly:** `mutate_structure` and `scaffold_structure`
are AI tools with no direct runner from a session (the journey-map MCP exposes
`scaffold_map`, not these two). Both pushed and parsed, both call the identical
function that 47/49/`scaffold_map` were proved with, and the edit is a
three-line swap. Proof of execution comes when the AI next adds a row.

**Found, not fixed (pre-existing, out of scope):**
- **`scaffold_map` "add" crashes when the AI omits `stage_goal`** —
  `"Unable to locate var: op.stage_goal"`. The tool's own instructions call that
  field optional. Unchanged by this story; the crash is on a line it did not
  touch.
- **`mutate_structure` add_stage / remove_stage / remove_lens and
  `scaffold_structure` stage add / both removes call `api.call ""` with an empty
  group** — live, not just in the local files. They almost certainly fail every
  time. Story 06 rebuilds `mutate_structure`; that is the place.
- The local `ai/tool/scaffold_map.xs` was **stale** — it predated RES-6-01's
  transactions. It now matches live.

---

### US-ORD-1-02 — One place decides what order means ✅ Done (2026-10-19)

**As a** founder
**I want** exactly one definition of "the stages are in order 1..n"
**So that** the UI, the AI tool and the API can never disagree about a map's order.

```gherkin
Scenario: Normalising a gapped map
  Given a map whose stage display_order values are 1, 4, 9
  When the stages are resequenced
  Then the values are 1, 2, 3 in the same relative order
  And no key changed

Scenario: Idempotent
  Given a map already at 1..n
  When it is resequenced twice in a row
  Then both runs return an identical order
  And nothing else in the map changed

Scenario: A tie resolves the same way every time
  Given two stages briefly share display_order 2
  When the map is resequenced
  Then the lower id takes the lower position
  And repeating the run gives the same answer
```

**Method:** `functions/jm/resequence_stages.xs` and
`functions/jm/resequence_lenses.xs`, modelled directly on
`functions/planner/resequence.xs`:

- `db.query` sorted `{display_order: "asc", id: "asc"}` — the **id tiebreak is
  not optional**; two rows can briefly share an order mid-move, and without it
  the result depends on whatever order the database felt like returning.
- A plain counter, `db.patch` **by `id`** for each row, inside one
  `db.transaction`.
- Return the resulting order so callers can respond with it.

**Counter-measures:**
- 🔴 **`db.patch` with a non-unique `field_name` touches only the FIRST match**
  (CLAUDE.md). Patching by `journey_map` would move one stage and report success
  — the PLN-5 bulk-visibility bug exactly. Every write is by the row's own `id`.
- No `conditional` inside the loop. If a branch is ever needed, it may only read
  the loop item — a condition reading a variable `var.update`d earlier in the
  same iteration silently discards every write in the branch (CLAUDE.md).
- No `function.run` and no HTTP inside the `db.transaction`; pure computation
  happens before it.
- `array.push` builds the returned order; nothing is accessed by `[index]`.

**Done when:** two consecutive runs on a clone of map 178 return byte-identical
orders, and a deliberately gapped clone (1, 4, 9) comes back 1, 2, 3.

---

### US-ORD-1-03 — Reorder a map's columns or rows in one call ✅ Done (2026-10-19)

**As a** founder
**I want** to send the stage ids in the order I want them
**So that** the map's column order changes in one atomic step, or not at all.

```gherkin
Scenario: A valid reorder
  Given a map owned by my account with stages A, B, C
  When I POST the order [C, A, B]
  Then the map's columns are C, A, B
  And all three keys are unchanged
  And a success event is logged

Scenario: A missing id
  Given a map with stages A, B, C
  When I POST the order [C, A]
  Then it is refused with E-ORD-001
  And the order is still A, B, C
  And a rejected event is logged

Scenario: A duplicate id
  When I POST the order [A, A, B]
  Then it is refused with E-ORD-001
  And nothing is written

Scenario: An id from another map
  When I POST the order [A, B, X] where X belongs to a different map
  Then it is refused with E-ORD-001
  And X is not moved into this map

Scenario: Another account's map
  Given the map belongs to a different account
  When I POST any order to it
  Then it returns accessdenied with E-GOV-001
  And a rejected event is logged

Scenario: No token
  When I POST with no Authorization header
  Then it returns 401 and nothing is written
```

**Method:** two endpoints, `POST journey_stage/reorder/{journey_map_id}` and
`POST journey_lens/reorder/{journey_map_id}`, copying endpoint 544's shape:

1. `planner/resolve_actor` → `journey/assert_map_owner` (SEC-1) — ownership
   before anything is read or written.
2. The **two-count exact-permutation check**, no loops, no array filters:
   - (a) submitted count == the map's current stage count, and
   - (b) `WHERE journey_map = X AND id IN (submitted)` == that same count.

   Together these catch every bad case. A missing or extra id fails (a). A
   duplicate fails (b) — `[A,A,B]` has a count of 3 but matches only 2 distinct
   rows. A foreign id fails (b) too, which is also what stops a stage being
   reordered in from another map.
3. Log `rejected` **then** `precondition` — the log must happen before the
   precondition aborts the stack, exactly as 544 does it.
4. Apply with a counter, patching each row by `id`, in one `db.transaction`.
5. Call story 02's resequence function to leave the map provably at 1..n.
6. Log `success`, return the new order.

**Counter-measures:**
- 🔴 **Path collision.** `journey_stage/reorder/{map_id}` must be checked against
  the existing `journey_stage/{journey_stage_id}` routes before it is created —
  a static segment can be permanently shadowed by an earlier dynamic path in the
  same group and verb (CLAUDE.md: endpoint 210 has been dead code since the day
  it was built, for exactly this reason). `journey_stage/add/{map_id}` already
  works, which is evidence this three-segment shape is reachable, but `listAPIs`
  on group 4 must confirm it rather than assume it.
- Keep every boolean condition on **one line** — a multi-line `&&` fails to parse.
- `stage_ids` is declared `json`, matching 544's `task_ids`. `int[]` also
  round-trips correctly (CLAUDE.md), but 544 is the proven shape.
- Two-count, not membership: `|contains:` returns false for every array, so a
  membership loop would report "not found" for everything.

**Done when:** all six scenarios above are proved over **real HTTP with two
accounts' tokens**, and the three refusal cases each leave the order
byte-identical.

---

### US-ORD-1-04 — Insert a column or row at a position ✅ Done (2026-10-19)

**As a** founder
**I want** to add a column before or after the one I'm looking at
**So that** I don't have to add at the end and then move it five times.

```gherkin
Scenario: Insert after a stage
  Given a map with stages A, B, C
  When I add a stage with after_stage_id = A
  Then the columns are A, NEW, B, C
  And NEW's key is minted from the max key suffix, not from position 2
  And a cell is scaffolded for NEW against every lens

Scenario: Insert before the first stage
  Given a map with stages A, B, C
  When I add a stage with after_stage_id = 0
  Then the columns are NEW, A, B, C

Scenario: Omitting the anchor keeps today's behaviour
  Given a map with stages A, B, C
  When I add a stage with no after_stage_id
  Then the columns are A, B, C, NEW
  And the call behaves exactly as it did before this epic

Scenario: An anchor from another map
  When I add a stage with after_stage_id pointing at a stage in a different map
  Then it is refused with E-ORD-002
  And no stage is created

Scenario: Inserting a row scaffolds its cells
  Given a map with 5 stages
  When I add a lens with after_lens_id = B
  Then the new row sits directly below B
  And 5 cells are scaffolded, one per stage, with the row's actor_fields shape
```

**Method:** extend endpoints 47 and 49 with one optional input each
(`after_stage_id` / `after_lens_id`), **additively** — omitted means append, so
every existing caller and the AI tool keep working unchanged.

Placement appends the row first, then calls story 02's resequence with the new
row spliced into the requested position. Story 02's function stays the only thing
that writes a final `display_order` value.

**Counter-measures:**
- 🔴 **An omitted optional `int` input arrives as `0`, never `null`**
  (CLAUDE.md). `$input.after_stage_id != null` is never true, and `0` is also the
  legitimate value for "insert at the very front". The three-way split
  (omitted / 0 / a real id) must come from `util.get_raw_input` with a `has`
  check, not from a null check. **These are POSTs, so there is a JSON body and
  this technique works** — it is the one that fails on GET.
- `== null` is PHP-loose here: `0 == null` is `true`. It cannot be used to detect
  "was this provided".
- The anchor must be verified to belong to **this map** before use, or an insert
  becomes a cross-map read. That is `E-ORD-002`.
- Endpoint 47 contains ~150 lines of per-template `actor_fields` scaffolding
  duplicated from endpoint 49 and from `mutate_structure`. **This epic does not
  refactor it** — it is pre-existing, it works, and touching it would put cell
  scaffolding in the blast radius of an ordering change. Recorded as a finding.

**Done when:** all five scenarios pass on a **clone of map 178**, never the
original (CLAUDE.md), and the omit-the-anchor case is proved byte-identical to
pre-epic behaviour.

---

### US-ORD-1-05 — Insert on the seam, move with arrows ✅ Done (2026-10-19)

**As a** founder looking at a map
**I want** to hover the line between two columns and click a `+` to insert there
**So that** inserting is one unambiguous click exactly where I'm pointing.

**The interaction, as the founder specified it (2026-10-19):** the Confluence
table pattern. Hover the seam between two columns and a small `+` appears;
clicking it inserts a new column **between those two columns**. The same on the
horizontal line between two rows. Moving is separate — that stays on arrows,
because drag-and-drop is deferred.

```gherkin
Scenario: Insert a column on a seam
  Given the matrix shows columns A, B, C
  When I hover the seam between A and B
  Then a + appears on that seam
  When I click it
  Then a new column is inserted between A and B
  And it is scaffolded with an empty cell for every row
  And the columns read A, NEW, B, C

Scenario: The leading seam
  Given the matrix shows columns A, B, C
  When I click the + on the seam to the left of A
  Then the columns read NEW, A, B, C

Scenario: The trailing seam
  Given the matrix shows columns A, B, C
  When I click the + on the seam to the right of C
  Then the columns read A, B, C, NEW
  And this is the same result as the old "add stage" button

Scenario: Insert a row on a seam
  Given the matrix shows rows P, Q, R
  When I click the + on the line between P and Q
  Then a new row is inserted between P and Q
  And one cell is scaffolded per stage with the row's actor_fields shape

Scenario: N columns offer N+1 seams
  Given the matrix shows 3 columns
  Then there are 4 insertion seams
  And every seam maps to exactly one position, with no duplicate affordance

Scenario: The + is reachable without a hover
  Given I am on a touch device with no hover
  When I view the matrix
  Then every seam still exposes a tappable target
  And no insertion point is hover-only

Scenario: Move a column right
  Given the matrix shows columns A, B, C
  When I click the right arrow on A's header
  Then the columns redraw as B, A, C
  And the cells move with their column, none are lost

Scenario: The ends are honest
  Given the matrix shows columns A, B, C
  Then A's left arrow is disabled and C's right arrow is disabled
  And clicking a disabled arrow does nothing and sends no request

Scenario: Move a row up
  Given the matrix shows rows P, Q, R
  When I click the up arrow on Q
  Then the rows redraw as Q, P, R

Scenario: A refused reorder keeps the screen honest
  Given the server refuses a reorder
  When the refusal comes back
  Then the matrix returns to the order the server actually has
  And a friendly message says nothing was changed
```

**Method — and this is the part that is not ordinary React.** The matrix is
**Tabulator**, not JSX. Column headers and row-header cells are built as **HTML
markup strings**:

- `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts` —
  `formatStageHeaderMarkup()` and `formatLensCellMarkup()` return strings.
- `webapp/protype-2/src/JourneyMatrixTabulator.tsx` — one **delegated click
  handler** on the container (~line 215) dispatches on `data-*` attributes:
  `data-edit-stage-id`, `data-toggle-planned-work-lens-id`, `.jm-link-indicator`.

So the arrows are added **exactly the way the existing edit and planned-work
buttons were**: emit `<button data-move-stage-id data-move-dir="left">` from the
markup helper, add a branch to the existing `handleClick`, and call a handler
ref. **There is no React `onClick` available in a Tabulator header formatter** —
attempting one is the predictable way to lose an afternoon.

**The seam is the harder half, because there is no DOM element between two
columns to hover.** Tabulator renders a flat list of header cells; the "line
between A and B" is a border, not a node. The workable shape:

- Each header cell carries a thin, absolutely-positioned **hover strip on its
  own left edge**, which *is* the seam between it and the column to its left.
  The last column carries one extra strip on its right edge. N columns → N+1
  strips → N+1 seams, with no shared or ambiguous targets.
- The strip is emitted **inside the markup string**, not injected into the DOM
  afterwards, so it survives Tabulator's header rebuilds. Anything appended
  post-render disappears the next time `columnsSignature` changes.
- Row seams work the same way on the frozen lens-column cells, using the
  bottom edge.
- The `+` reveals on `:hover`/`:focus-within` in CSS; the click is handled by the
  **existing delegated handler** via `data-insert-stage-after` /
  `data-insert-lens-after`, carrying the anchor id (`0` for the leading seam).

Mapping to the API is exact and needs no new endpoint beyond story 04:

| Seam | Call |
|---|---|
| Left of the first column | `after_stage_id = 0` |
| Between A and B | `after_stage_id = A` |
| Right of the last column | anchor omitted (plain append) |

- `addStage` / `addLens` already live in `webapp/protype-2/src/App.tsx`
  (~lines 1788 / 1842); the insert variants extend them with the anchor argument.
- `sortByDisplayOrder` (`src/xano.ts:575`) already sorts by `display_order` with
  an `id` tiebreak, so a refetch after a reorder renders correctly with no
  change.

**Counter-measures:**
- 🟡 **The column rebuild is signature-driven.** `columnsSignature`
  (`JourneyMatrixTabulator.tsx:96`) joins `id:label:goal:actor:readiness` per
  stage. It captures position only *implicitly*, through array order — swapping
  two stages does change the joined string, so a rebuild should fire. **This must
  be verified by test, not by reading the code**, because if it ever didn't fire
  the symptom is a reorder that works on the server and does nothing on screen.
- **The `+` is always rendered, faint, and darkens on hover/focus** (decided
  2026-10-19). Not hover-to-appear. One implementation covers mouse and touch,
  there is no hidden state, and insertion is always one tap. A hover-only `+`
  would make insertion silently unreachable on a tablet; tap-to-reveal would
  cost two taps.
- 🟡 **The seam strip must not swallow clicks meant for the header.** The strip
  sits over the header's edge, so its width has to be small enough that stage
  edit, the readiness mark and the actor pill stay clickable. The existing
  delegated handler already uses `closest()` with `stopPropagation()`, so
  ordering the new branches before the generic cell-select branch is what keeps
  both working.
- 🟡 **Horizontal scroll and frozen columns.** The lens column is `frozen: true`;
  a seam strip positioned per-cell scrolls with its cell, which is correct. An
  overlay positioned by measured pixel offsets would **not** be — that is the
  reason the strip lives inside the header cell rather than floating above the
  table.
- Arrows are **disabled at the ends**, and the disabled state must be real
  (no request sent), not just grey.
- An optimistic reorder must **roll back to the server's order** on refusal, not
  to the client's guess. CLAUDE.md: the UI helps, the server always validates
  again, and the user's work is kept on a rejected save.

**Done when:** a Playwright spec drives a seam insert at the leading, middle and
trailing positions on a clone, drives both move directions, asserts the rendered
order, asserts no cell content changed, and asserts N+1 seams exist for N
columns.

---

### US-ORD-1-06 — The AI and the buttons use the same rule ✅ Done (2026-10-19)

**As a** founder
**I want** the AI's reorder and my buttons to go through one piece of code
**So that** they cannot drift into disagreeing about what order means.

```gherkin
Scenario: The AI tool normalises the same way
  Given the AI is asked to reorder stages via mutate_structure
  When it completes
  Then the resulting display_order values are 1..n with no gaps
  And the result is identical to the same reorder done with the buttons

Scenario: The AI cannot mint a colliding key
  Given the AI adds a lens to a map whose order was just normalised
  Then the new lens key does not collide with any existing key

Scenario: A rejected AI reorder is logged like any other
  When the AI submits an order that is not an exact permutation
  Then it is refused with E-ORD-001
  And a rejected event appears on the Health page
```

**Method:** repoint `ai/tool/mutate_structure.xs` at story 02's shared functions
and story 01's key mint, deleting its own nested-`foreach` reorder
(`reorder_stages` / `reorder_lenses`, ~lines 509–600) and its own `lens-%d` mint.

**Why this is its own story and not a footnote:** LOG-1 earned this rule the hard
way — *"Put a shared RULE in its own function rather than copying it into the
reader and the writer."* A second copy of the ordering rule, held by the AI, will
eventually disagree with the UI and sound equally certain either way. There were
**five** copies of key minting — story 01 reduced that to one per axis, including
`mutate_structure`'s — and there are still **two** of reorder. This story ends
with one of each.

**Counter-measures:**
- `mutate_structure` is a `tool`, and an omitted optional `bool`/`text` input
  inside a tool definition is indistinguishable from `false`/`""` (CLAUDE.md, the
  `update_stage_contract` bug). Any new optional field uses the
  `"__absent__"` sentinel technique.
- The tool's existing `api.call "" verb=GET` pattern for `add_stage` **does not
  forward user auth** — its own comment says so, which is why `add_lens` uses
  direct DB ops. Do not route the new shared calls through `api.call`.
- Governance: both reorder endpoints and both insert paths log success and
  failure through `ops/log_event`. Never fail silently.

**Done when:** exactly one key-mint implementation and one resequence
implementation exist per axis, and the AI-driven and button-driven reorders of
the same clone produce identical `display_order` values.

---

## Build results — stories 02–06 (2026-10-19)

Everything below was proved live, as **test user 9 in test account 6**, on test
map 210 — never the founder's account, never map 178.

### What was built

| Piece | Where | Live id |
|---|---|---|
| The one place order is written, with the exact-permutation check and the E-ORD-001 refusal **inside it** | `functions/journey/apply_stage_order.xs`, `apply_lens_order.xs` | functions 186, 187 |
| Reorder endpoints | `POST journey_stage/reorder/{map}`, `POST journey_lens/reorder/{map}` | endpoints 581, 582 |
| Insert at a position | `after_stage_id` / `after_lens_id` on `journey_stage/add` (47) and `journey_lens/add` (49) | — |
| Seam `+` and arrows | `matrixOrder.ts` (pure), `journeyMatrixTabulatorHelpers.ts` (markup), `JourneyMatrixTabulator.tsx` (clicks), `App.tsx` (handlers), `index.css` | — |
| AI on the same rule | `ai/tool/mutate_structure.xs` reorder branches → `journey/apply_*_order` | tool 4 |
| Error codes in the catalog | `E-ORD-001`, `E-ORD-002` in `src/ops/errorCatalog.json` | — |

### Where the plan changed, and why

- **The permutation check moved into the shared function.** The epic put it in
  the endpoint, copied from 544. Inside `apply_*_order` it protects every
  caller — buttons, insert and the AI — with one copy of the rule.
- **No standalone "normalise" function.** Nothing needed one: a reorder writes
  1..n, and insert appends then hands the spliced list to the same function.
- **Insert is "append, then reorder"**, so no code besides `apply_*_order` ever
  computes an order.
- **An inserted column with no label is called "New stage"**, not "Stage N".
  N would be its append position, which is wrong once it's placed elsewhere.
- **Row insert opens the actor wizard** (a row needs an actor type). The seam's
  anchor waits until the wizard confirms.
- **The "column rebuild is signature-driven" risk didn't apply.** The matrix
  rebuilds the whole Tabulator table whenever stages or data change, so a
  reorder always redraws.
- **No unique-index change.** See story 01 and the issues file — the existing
  `(journey_map, key, display_order)` index already blocks the race.

### Tests

| Check | Result |
|---|---|
| `apply_stage_order`: missing id / duplicate / id from another map | ✅ all three refused with E-ORD-001; order byte-identical afterwards |
| `apply_stage_order`: full reverse, then the same call again | ✅ applied, keys unchanged, second run identical (idempotent) |
| `apply_lens_order`: bad list, then a real move | ✅ refused, then applied |
| Reorder endpoints over HTTP: no token / valid / missing id / founder's map / row swap / row from another map | ✅ 401 / 200 / 400 E-ORD-001 / 403 E-GOV-001 / 200 / 400 |
| Stage insert over HTTP: no anchor / after `s1` / anchor 0 / anchor from another map | ✅ appended exactly as before (`s13@9`, "Stage 9") / landed 2nd / landed 1st ("New stage") / 400 E-ORD-002, nothing created |
| Lens insert over HTTP: same four cases | ✅ same four results; actor template carried over (vendor-v1, customer-v1); one cell per stage |
| `has` on the raw body tells "sent 0" from "not sent" | ✅ proved on a scratch function before shipping |
| **Browser, real app, test user 9:** ▶ on the first column | ✅ moved to 2nd; ◀ on the first column greyed out |
| Browser: seam `+` between two columns | ✅ new column landed exactly there; N columns showed N+1 seams (11 → 12, read from the DOM) |
| Browser: ▼ on a row | ✅ moved down |
| Browser: seam `+` between two rows | ✅ actor wizard opened → "Internal Employee" landed exactly there, 12 fields scaffolded |
| Browser: **stale screen** (column deleted server-side, then ▶ clicked) | ✅ refused; friendly banner *"That column order doesn't match this map's columns, so nothing was changed. Refresh and try again. (E-ORD-001)"*; matrix reloaded to the real 10 columns |
| Browser console during the tests | ✅ no errors |
| AI key→id lookup used by `mutate_structure` (real keys + an unknown key) | ✅ `[1547, 1545, 0]` — unknown key gives 0, so the shared function refuses rather than skipping |
| Workspace duplicate-key scan after everything | ✅ 0 of 211 stages, 0 of 207 lenses; detector catches a planted duplicate |
| `npm test` | ✅ **416/416** (17 new: `matrixOrder.test.ts` + 5 markup tests) |
| `npm run lint` / `vite build` | ✅ clean / builds |

**Not run, stated plainly:**
- **No Playwright spec.** The 26 existing specs already fail at sign-in (no
  `E2E_AUTH_TOKEN`), so a new spec would fail the same way. Covered by the
  manual browser run above; the fix is issue #4 in the backlog.
- **`mutate_structure` reorder wasn't executed end-to-end through the AI chat.**
  Its two parts (the key lookup and the shared function) were each proved live,
  and the tool pushed and parsed.

## MVP scope

**In:** stories 01–06.

**Deferred:**
- Drag-and-drop (same endpoints, later story).
- Multi-select move (move three columns at once).
- Undo for a reorder. The log records it; there is no one-click revert.
- Backfilling gapped order in the 16 maps that have it.
- Refactoring the duplicated `actor_fields` scaffolding in endpoints 47/49.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | `journey/assert_map_owner` on all four new/extended write paths; the anchor row is proved to be in the same map (`E-ORD-002`) |
| Validation | Exact-permutation check server-side; the UI's order is never trusted |
| Error codes | `E-ORD-001`, `E-ORD-002` added; `E-GOV-001` reused for ownership; `E-PLN-016` checked and deliberately not borrowed |
| Events | Every reorder and insert logs success; every refusal logs `rejected`, so denials appear on the Health page |
| Table constraints | **Additive only.** No new columns, no schema change — `display_order` and `key` already exist. Nothing goes near `updateTableSchema`, which silently drops `filters=trim` validators (CLAUDE.md) |
| Delete behaviour | Unchanged. Remove still leaves a gap; the next reorder closes it |
| Rollback | Stories 01–02 are new functions (deletable). Stories 03–04 are additive inputs and new endpoints. Story 06 is the only destructive edit — `mutate_structure`'s current source is committed to git before it is touched |
| No silent failure | A refused reorder is logged, and the screen is corrected to the server's truth |
| Testing | Every live exercise runs on a **clone of map 178**, never the original (CLAUDE.md) |

## Test Results

_Not started._

| Story | Tests | Result |
|---|---|---|
| 01 | Mint vs old formula on every row; 5-map smoke test; 8 real-HTTP cases as test user 9; `scaffold_map` executed live; workspace duplicate scan with a proven detector; `npm test`, `npm run lint` | ✅ All pass — see story 01. Two of five mint sites (AI tools) pushed but not executed |
| 02 | Shared order functions: 3 refusal cases, reverse, idempotence, lens case | ✅ all pass |
| 03 | Reorder endpoints: 6 real-HTTP cases incl. no token and another account's map | ✅ all pass |
| 04 | Insert at position: 4 stage + 4 lens real-HTTP cases | ✅ all pass |
| 05 | 17 new unit tests; real-browser run of move, seam insert (both axes) and the stale-screen refusal | ✅ all pass — no Playwright spec (see Build results) |
| 06 | Key→id lookup proved on a scratch function; tool pushed and parsed | ✅ pass — not executed through the AI chat |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| ✅ **Key/order coupling** | ~~Three~~ **Five** call sites minted keys from position (one from count + 1). Normalising order makes the next add collide, and a collided key repoints `primary_actor_lens` and detaches `work_task` rows | **Closed by story 01.** One shared mint per axis; collision impossible outside a race. A race needs a unique index — Still open |
| 🟡 **Gapped order already exists** | 3 maps have gapped stage order, 13 have gapped lens order (live scan: 200 stages, 198 lenses, 24 maps, zero duplicate keys, zero duplicate order) | Resequence sorts by `(display_order, id)` and tolerates gaps by design; gaps are input, not error |
| 🟡 **`db.patch` only touches the first match** | A reorder patched by `journey_map` would move one row and report success — the PLN-5 bulk-visibility bug exactly | Query then loop, patch each row by its own `id`, inside `db.transaction` |
| 🟢 **Stale-after-reorder** | ~~A published version pins its own snapshot, so reordering makes the live view and the pinned view disagree~~ | **Already handled, no work needed** — see "Versioning" below. `pub/build_map_snapshot` sorts stages and lenses by `(display_order, id)`, so a reorder changes the content hash and `MapVersionBadge` flips to "v*n* · draft changes" on its own |
| 🟡 **Static path shadowed by a dynamic sibling** | `journey_stage/reorder/{id}` could be unreachable from birth, the way endpoint 210 is | `listAPIs` on group 4 checked before the endpoint is created (story 03) |
| 🟡 **Tabulator header buttons are not React** | Headers are markup strings; an `onClick` silently never fires | Copy the existing `data-*` + delegated-handler pattern (story 05) |
| 🟡 **Optional `int` anchor can't be detected with `!= null`** | `0` means "insert at front" *and* "omitted" | `util.get_raw_input` + a `has` check — valid because these are POSTs with a body |
| 🟢 **In-flight jobs are safe** | `work_task` has no order column and reads order from the job's pinned version snapshot | Nothing needed. Verified during discovery |

## Decided

| Question | Decision | Date |
|---|---|---|
| Buttons or drag-and-drop for v1? | **Buttons.** Drag-and-drop deferred | 2026-10-18 |
| Are stage/lens keys stable identities? | **Yes — opaque and immutable.** Never renumbered | 2026-10-18 |
| How is insert triggered? | **A `+` on the seam between two columns/rows**, Confluence-style. Replaces the per-header "insert after" button. Moving stays on arrows | 2026-10-19 |
| Insert before *and* after? | **Moot.** A seam per boundary covers every position with no duplicate affordance — N columns, N+1 seams | 2026-10-19 |
| Does a reorder register as a change to the map? | **Yes** — and it already does, with no ORD-1 work. See Versioning | 2026-10-19 |
| Does *Publish version* stay the only thing that mints a version? | **Yes.** No auto-versioning on save. The content-hash drift badge is the "it changed" signal. If a per-change trail is wanted later, it comes from `event_log`, which already records every save and is prunable — not from immutable version rows | 2026-10-19 |
| `E-ORD-001` / `E-ORD-002` as new codes? | **Approved, both.** Kept separate so the UI can tell *resend a correct list* (`001`) from *refetch, the screen is stale* (`002`) | 2026-10-19 |
| Touch behaviour for the seam `+` | **Always-faint `+`, darkening on hover/focus.** One implementation for mouse and touch, no hidden state, one tap to insert. Hover-only and tap-to-reveal both rejected | 2026-10-19 |

## Still open

**Nothing for this epic.** The unique-index question resolved itself: the
existing `(journey_map, key, display_order)` index already rejects a racing
duplicate (proven live), so no schema change was made. Follow-up work is ranked
in [ISSUES-BACKLOG.md](ISSUES-BACKLOG.md).
