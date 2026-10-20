# EPIC-ORD-2 — The AI reshapes a map the same way the buttons do

**Status:** 📋 **not started.** Written 2026-10-19, immediately after ORD-1
shipped insert-on-the-seam and resequencing for the matrix buttons. This epic
gives the **AI agent** the same abilities, and fixes six actions it has been
claiming to perform while doing nothing.

Depends on **ORD-1** (done). Nothing else blocks it.

## Why

ORD-1 gave the founder buttons: a `+` on the seam between two columns or rows,
and arrows to move one left/right or up/down. The AI agent in this workspace —
**`Journey Map Assistant`, agent 18** — reaches structure through two tools,
`ai/tool/mutate_structure` and `ai/tool/scaffold_structure`, and those two tools
were never finished.

What the agent can actually do today:

| Agent action | State |
|---|---|
| `reorder_stages` / `reorder_lenses` | ✅ works — repointed to `journey/apply_*_order` by ORD-1 story 06 |
| `add_lens` (add a row) | ✅ works — appends to the bottom |
| `rename_stage` / `rename_lens` | ✅ works |
| `add_stage` (add a column) | ❌ **does nothing** — `api.call "" verb=GET { api_group = "" }` |
| `remove_stage` | ❌ **does nothing** — same empty call |
| `remove_lens` | ❌ **does nothing** — same empty call |
| `scaffold_structure`: stage add, stage remove, lens remove | ❌ **does nothing** — three more empty calls |
| Insert at a position | ❌ **does not exist** — append only |

Six dead call sites. The agent's own system prompt tells it that
`mutate_structure` can *"Add, remove, rename, or reorder stages and lenses"*, so
it chooses those actions confidently, reports success, and the map is unchanged.
That is the exact failure mode OBS-1 exists to prevent: a silent no-op that
reports success.

The second gap is placement. `after_stage_id` / `after_lens_id` live on the HTTP
endpoints the buttons call (47 and 49). The AI tools write to the database
directly and never see those inputs, so the agent can only append and then
resequence as a separate turn.

**"Insert in the seam" is not a separate backend feature.** The seam is a screen
affordance only. "Between Onboarding and Pricing" **is** "after Onboarding",
which is `after_stage_id` — already built, already proven. The agent needs the
same input expressed in keys.

## The decision that shapes the epic

**Do not fix `api.call ""` by pointing it at the real endpoints.** Three reasons:

1. Endpoints 47/48/49/50 are `auth = "user"`. A tool runs server-side with no
   user token, so every call would 401 unless a token were threaded through the
   agent — new surface, new leak risk, for no gain.
2. Xano's router can permanently shadow a static path with a dynamic sibling
   (CLAUDE.md: endpoint 210 has been dead since birth). An `api.call` adds a
   second routing dependency where none is needed.
3. An HTTP hop inside a tool is a network call per operation, inside a
   `foreach`, on a request path.

**Instead, extract the rule into shared functions and have both callers run it.**
That is already the house rule in CLAUDE.md ("Put a shared RULE in its own
function rather than copying it into the reader and the writer") and it is
exactly what made the AI's reorder start working in ORD-1: one
`journey/apply_*_order`, called by the endpoint and by the tool, so the two can
never disagree about what a legal order is.

## The rule

> **One function per structural operation. The endpoint calls it. The tool calls
> it. Nothing else computes structure.**

After this epic there is exactly one place that adds a column, one that adds a
row, one that removes each, and one that decides order (ORD-1's). The button path
and the AI path differ only in how they authenticate and what they log.

## What already exists and is being moved, not invented

| Piece | Where it lives now | Fate |
|---|---|---|
| Mint a stage/lens key | `journey/next_stage_key`, `next_lens_key` (182, 183) | Reused unchanged |
| Write a final `display_order` | `journey/apply_stage_order`, `apply_lens_order` (186, 187) | Reused unchanged |
| Insert at a position | Inline in endpoints 47 and 49 | **Extracted** to a function |
| Cell scaffolding for a new column/row | Inline in 47 and 49 | **Extracted** with it |
| Per-actor-type role prompt + `actor_fields` | Copied **4×**: 47, 49, `mutate_structure`, `scaffold_structure` | **Extracted** to one function |
| Cascade cell delete on remove | Inline in endpoints 48 and 50 | **Extracted** to a function |
| Ownership guard | `journey/assert_map_owner` | Reused unchanged |

Most of this epic is moving proven code behind a function boundary. Very little
is new logic.

## Non-goals

- **No new tables, no new columns, no schema change.** Nothing goes near
  `updateTableSchema`, which silently drops `filters=trim` validators (CLAUDE.md).
- **No new UI.** The buttons already work; this epic must leave them
  byte-identical in behaviour.
- **No change to how the AI reorders.** ORD-1 already fixed that.
- **No drag-and-drop**, still deferred.
- **Not fixing `scaffold_map`'s `stage_goal` crash** (ISSUES-BACKLOG #2) unless
  it falls out for free — different tool, different bug, one-line fix.

## Error codes

| Code | Meaning | Status |
|---|---|---|
| `E-ORD-001` | The submitted order is not an exact permutation of this map's rows | Exists (ORD-1) |
| `E-ORD-002` | The anchor row does not belong to this map | Exists (ORD-1) — reused for `after_*_key` |
| `E-ORD-003` | **New.** The named key does not exist in this map | Needed: the AI works in keys, and a hallucinated key must be refused by name, not silently skipped |
| `E-GOV-001` | Caller does not own the map | Exists |

`E-ORD-003` is the one new code. It matters because the agent invents keys: today
a bad key in a remove silently matches nothing and the tool still reports
success. The message must name the key it could not find, so the agent can
self-correct on its next turn instead of retrying the same thing.

## Stories

### US-ORD-2-01 — One actor template, not four copies

**As a** founder
**I want** a row to behave the same no matter what created it
**So that** the AI and the buttons don't produce two different kinds of row.

```gherkin
Scenario: The same actor type gives the same row everywhere
  Given the actor type "metrics"
  When a row is created by the Add Row button
  And an identical row is created by the AI
  Then both rows have the same template_key
  And both have the same role_prompt
  And both scaffold the same actor_fields keys in the same order

Scenario: An unknown actor type is refused, not guessed
  When a row is requested with actor_type "accountant"
  Then it is refused with a message naming the eight valid types
  And no row is created
```

**Method:** one new function `journey/actor_template`, input `actor_type`,
returning `{template_key, role_prompt, actor_fields}`. Called by endpoints 47
and 49 and by both AI tools.

**Counter-measures:**
- 🔴 **The four copies have already drifted** (ISSUES-BACKLOG #8): the metrics
  prompt in `scaffold_structure` differs from the one in `journey_lens/add`, and
  `mutate_structure` has no financial or metrics template at all. **Extraction
  is therefore a behaviour change for some paths, not a pure refactor.** Diff all
  four copies first, write down which text wins per actor type, and record that
  choice in this epic before replacing anything.
- `journey_lens/add` (endpoint 49) is the version the founder's own UI uses and
  is the most exercised — it is the default winner on any disagreement.
- Existing rows are **not** migrated. Their `role_prompt` is already stored; this
  only governs rows created from here on.

**Done when:** the eight actor types each produce one agreed template, proven by
running the function for all eight and diffing against endpoint 49's current
output.

---

### US-ORD-2-02 — One place adds a column or a row

**As a** founder
**I want** adding a column to mean exactly one thing
**So that** a fix or a rule applies everywhere at once.

```gherkin
Scenario: Add with no anchor appends
  Given a map with stages A, B, C
  When insert_stage is called with no anchor
  Then the columns are A, B, C, NEW
  And NEW's key is minted from the shared mint, never from a count

Scenario: Add with an anchor places the column
  Given a map with stages A, B, C
  When insert_stage is called with after_stage_id = A
  Then the columns are A, NEW, B, C

Scenario: Adding a column scaffolds one cell per row
  Given a map with 6 rows
  When a column is added
  Then 6 cells exist for it, each with its row's actor_fields shape

Scenario: An anchor from another map is refused
  When insert_stage is called with an anchor belonging to a different map
  Then it is refused with E-ORD-002
  And no stage is created and no cell is created
```

**Method:** two new functions, `journey/insert_stage` and `journey/insert_lens`,
lifted out of endpoints 47 and 49 unchanged in behaviour. Inputs:
`journey_map_id`, `label?`, `actor_type?` (lens), `after_*_id?`, plus the
`user_id` / `account_id` / `step` / `correlation_id` logging inputs the ORD-1
functions already take.

Placement stays "append, then hand the spliced list to
`journey/apply_*_order`" — ORD-1's function remains the only thing that writes a
final `display_order`.

**Counter-measures:**
- 🔴 **`db.patch` on a `json` column MERGES** (CLAUDE.md, critical). Cell
  scaffolding writes `actor_fields` as json. Any place this extraction turns a
  create into a patch needs the two-step `null`-then-value write. Prefer
  `db.add` and change nothing about how cells are first written.
- 🔴 **No `function.run` inside `db.transaction`** (CLAUDE.md). The current
  endpoints wrap their writes in a transaction; the key mint and the order call
  must sit outside it, as they do in 47/49 today.
- An omitted optional `int` anchor arrives as `0`, and `0 == null` is `true`.
  The three-way split must come from `util.get_raw_input` + `has`. **The tools
  receive a json/text body, so this works** — but a function called by
  `function.run` has no raw body, so the **anchor must be passed explicitly as
  `-1` for "not given"**, the convention ORD-1 already uses on endpoints 47/49.
- The function must not assume a label. An inserted column with no label is
  **"New stage"** (ORD-1 decision) — never "Stage N", which would be its append
  position rather than its placed one.

**Done when:** the four scenarios pass on a **clone of map 178**, never the
original (CLAUDE.md), for both axes.

---

### US-ORD-2-03 — One place removes a column or a row

**As a** founder
**I want** removing a column to clean up after itself
**So that** deleting from the AI is as safe as deleting from the screen.

```gherkin
Scenario: Removing a column deletes its cells
  Given a map with 6 rows and a column X
  When remove_stage is called for X
  Then X is gone
  And all 6 of X's cells are gone
  And no other column's cells are touched

Scenario: The last column cannot be removed
  Given a map with exactly 1 column
  When remove_stage is called for it
  Then it is refused
  And the column still exists

Scenario: Removing closes the gap it leaves
  Given columns at display_order 1, 2, 3, 4
  When the column at 2 is removed
  Then the remaining columns are at 1, 2, 3

Scenario: A key that does not exist is refused by name
  When remove_stage is called with key "s99" on a map that has no s99
  Then it is refused with E-ORD-003
  And the message names "s99"
  And nothing is deleted
```

**Method:** two new functions, `journey/remove_stage` and `journey/remove_lens`,
lifted out of endpoints 48 and 50. Ends with a call to
`journey/apply_*_order` on the survivors, which closes the numbering gap
(ISSUES-BACKLOG #10, free here).

**Counter-measures:**
- 🔴 **`db.del` with `field_name`/`field_value` deletes only the FIRST match**
  (CLAUDE.md). A cascade written as "delete cells where stage = X" removes one
  cell and reports success, orphaning the rest. **Query the cells, loop, delete
  each by its own `id`, inside `db.transaction`.** This is the single most
  dangerous line in the epic.
- `db.del`, never `db.delete`, and it takes no `as`.
- The "at least one must remain" rule must be re-asserted inside the function.
  It currently lives in the endpoints; if it is left there, the AI path loses it
  and the agent can empty a map.
- Check what else points at a stage/lens key before deleting: `primary_actor_lens`
  holds a **lens key as text**, and `work_task` identity is
  `(work_item_id, stage_key, lens_key)`. A removal that strands either is a
  data-integrity bug, not a UI bug. **Decide and record** whether remove is
  refused when a published plan references the key, the way DEL-1 refuses
  deleting a map that is in use.

**Done when:** all four scenarios pass on a clone, and a cell count taken before
and after proves no orphans and no collateral deletions.

---

### US-ORD-2-04 — The buttons keep working, provably

**As a** founder
**I want** my screen to behave exactly as it did yesterday
**So that** making the AI work doesn't cost me what already works.

```gherkin
Scenario: Every ORD-1 HTTP case still passes
  Given the endpoints now delegate to the shared functions
  When the eight ORD-1 insert cases and six reorder cases are re-run
  Then every result is identical to the recorded ORD-1 result

Scenario: The seam and the arrows are unchanged
  When a column is inserted on a seam in the browser
  And a row is moved with an arrow
  Then both behave exactly as recorded in ORD-1's Build results
```

**Method:** repoint endpoints 47, 48, 49, 50 to `function.run` the new functions.
No input or response shape changes. This story is **done before any new
capability is added**, so a regression surfaces while the change set is still
small.

**Counter-measures:**
- 🔴 This is the only destructive part of the epic: it edits four endpoints the
  founder's UI depends on. **Commit the current source to git before touching
  them** (ORD-1's source is still uncommitted — that must be resolved first).
- Fetch the live source with `getAPI` and diff against the local `.xs` first.
  Local files are known to drift (ISSUES-BACKLOG #12).
- Response shape must not change. The frontend reads `$placed_row` and
  `deleted_cell_count`; both must survive the move.

**Done when:** the full ORD-1 test table is re-run green, plus `npm test`,
typecheck and build, **before story 05 begins**.

---

### US-ORD-2-05 — The AI's six dead actions actually work

**As a** founder
**I want** the AI to change the map when it says it did
**So that** I can trust what it tells me.

```gherkin
Scenario: The AI adds a column
  Given the agent is asked to add a stage called "Renewal"
  When it calls mutate_structure with add_stage
  Then a column "Renewal" exists on the map
  And a cell exists for it against every row
  And the tool reports the created column, not a bare success

Scenario: The AI removes a row
  When it calls mutate_structure with remove_lens for an existing key
  Then the row and its cells are gone

Scenario: scaffold_structure applies a whole blueprint
  Given a blueprint with 2 removes, 3 renames and 2 adds
  When scaffold_structure runs it
  Then all 7 operations are applied
  And the reported counts match what is actually in the database

Scenario: A hallucinated key fails loudly
  When the AI removes a key that does not exist
  Then the tool returns E-ORD-003 naming the key
  And success is false
```

**Method:** replace all six `api.call "" verb=GET { api_group = "" }` sites —
three in `mutate_structure`, three in `scaffold_structure` — with
`function.run` of the story 02/03 functions. Keys come in from the AI, so each
site translates key → id with the single `db.query ... return = {type: "single"}`
then `|get:"id":0` pattern ORD-1 proved, and refuses `0` with `E-ORD-003`.

**Counter-measures:**
- 🔴 **These six sites sit inside a `conditional` whose condition reads a
  variable set earlier in the same loop iteration** (`if ($target_stage != null)`
  after a `db.query ... as $target_stage`). CLAUDE.md documents that shape as
  **silently discarding every write in the branch** — proven live, result all
  zeros, no error. Fixing the empty `api.call` may therefore reveal a second
  bug underneath it. **Restructure so the condition reads the loop item or an
  input, not an in-iteration variable** — do not simply swap the call and assume
  the branch runs.
- 🔴 `$target_stage != null` is PHP-loose: a missing single-row query result is
  falsy and so is a legitimate `0`. Use the `|get:"id":0` → compare-to-zero
  pattern instead of a null test.
- The counters (`$stages_removed`, `$cells_deleted`) are `var.update`d inside
  those same branches, so **the reported numbers are suspect even once the
  writes land.** Verify counts against a real database query, not against the
  tool's own response — the lesson from the json-merge cleanup that reported
  success while changing nothing.
- `scaffold_structure` runs removes, renames and adds in three passes. Order
  matters: a remove and an add in one blueprint must not fight over the same
  key. Re-test the pass order after the change.
- `function.run` inside `foreach` is confirmed working (CLAUDE.md), including one
  that queries per iteration — fine at these volumes.

**Done when:** all four scenarios pass **through the real agent in the chat**,
not only by calling the tool directly — the gap ORD-1 story 06 left open.

---

### US-ORD-2-06 — The AI can place a column or a row, not just append

**As a** founder
**I want** to say "add a stage after Onboarding" and have it land there
**So that** the AI edits a map the way I do with the seam.

```gherkin
Scenario: Place a column after a named stage
  Given stages onboarding, pricing, renewal
  When the AI adds a stage with after_stage_key = "onboarding"
  Then the columns are onboarding, NEW, pricing, renewal

Scenario: Place a column at the very front
  When the AI adds a stage asking for the front position
  Then the new column is first

Scenario: Omitting the anchor still appends
  When the AI adds a stage with no anchor
  Then it appends, exactly as before this story

Scenario: An anchor key that does not exist
  When the AI adds a stage with after_stage_key = "nope"
  Then it is refused with E-ORD-003 naming "nope"
  And no column is created

Scenario: Between two rows
  When the AI adds a lens with after_lens_key = "customer"
  Then the new row sits directly below the customer row
  And its cells are scaffolded for every column
```

**Method:** add `after_stage_key` / `after_lens_key` (text, optional) to both
tools, translate key → id, pass to the story 02 functions. **Keys, not ids** —
the agent reasons in keys and `get_map_state` gives it keys.

**Counter-measures:**
- An omitted optional `text` input arrives as `""`, not `null`, and `"" == null`
  is `true` (CLAUDE.md). "Not given" vs "insert at the front" needs an explicit
  signal — a separate boolean, or a sentinel key value. Decide one and use it in
  both tools.
- "Insert in the seam" needs **no new input**: the seam between A and B *is*
  `after = A`. Do not add a second placement vocabulary for the AI; it must be
  the same concept the buttons use, or the two drift.
- The agent must be told placement exists, or it will never use it — story 07.

**Done when:** all five scenarios pass through the real agent, on a clone.

---

### US-ORD-2-07 — The AI knows what it can and cannot do

**As a** founder
**I want** the agent's instructions to match reality
**So that** it stops promising things it can't do.

```gherkin
Scenario: The tool instructions describe placement
  Given mutate_structure now accepts after_stage_key
  Then its instructions document it with an example
  And they state that an unknown key is refused, not skipped

Scenario: The agent prompt no longer over-promises
  Then agent 18's prompt describes only actions that work
  And it tells the agent to place a column when the user names a position
```

**Method:** update the `instructions` block on both tools, and the
`system_prompt` on agent 18 (`Journey Map Assistant`). Agent 9
(`Journey Map Builder`) is currently forbidden from adding anything — see
**Still open**.

**Counter-measures:**
- The prompt is ~40k characters and agent 9's source contains unresolved
  merge-conflict markers (`<<<<<<<` / `=======` / `>>>>>>>`). **Do not reformat
  either prompt.** Make the smallest possible edit and diff it.
- Prompt text is duplicated between agents 18 and 9. Changing one does not change
  the other; state explicitly which were edited.

**Done when:** a fresh chat session with the agent, given "add a stage called
Renewal after Onboarding", does it in one turn without being told how.

## MVP scope

**In:** stories 01–07.

**Deferred:**
- Migrating existing rows to the agreed actor templates (story 01 governs new
  rows only).
- Multi-operation placement in one `scaffold_structure` blueprint ("add these
  three, in this order, starting after Onboarding").
- Undo for an AI structure change. `event_log` records it; there is no revert.
- `scaffold_map`'s `stage_goal` crash (ISSUES-BACKLOG #2) — adjacent, one line,
  but a different tool.
- Archived-map guard on these paths (ISSUES-BACKLOG #6) — worth folding in if
  the endpoints are already open, flagged as a judgement call at build time.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | The shared functions take `account_id`/`user_id` and are called behind `journey/assert_map_owner` on the endpoint path. **The AI path's ownership story must be stated explicitly** — the agent acts on behalf of a user whose token authorised the chat turn; the tools must carry that identity, not trust `journey_map_id` alone |
| Validation | Unknown key refused by name (`E-ORD-003`); anchor proved in-map (`E-ORD-002`); last-column/last-row rule asserted inside the function, not the endpoint |
| Error codes | `E-ORD-003` added to `src/ops/errorCatalog.json`; `E-ORD-001`, `E-ORD-002`, `E-GOV-001` reused |
| Events | Every add and remove logs success with its step; every refusal logs `rejected`, so AI denials appear on the Health page alongside button denials |
| Table constraints | **Additive only.** No new columns, no index change, no `updateTableSchema` call |
| Delete behaviour | Remove now closes its own numbering gap. Whether a key referenced by a published plan can be removed at all is **an open decision**, story 03 |
| Rollback | Stories 01–03 are new functions (deletable with no caller). Story 04 is the risky one — endpoints committed to git first. Stories 05–07 edit AI tools and prompts, whose current source must be committed before editing |
| No silent failure | This epic exists because six actions failed silently. Every fixed site must be verified against a real database query, never against the tool's own reported count |
| Testing | Every live exercise runs on a **clone of map 178**, never the original (CLAUDE.md) |

## Test Results

_Not started._

| Story | Tests | Result |
|---|---|---|
| 01 | Eight actor types through the function, diffed against endpoint 49's current output; unknown type refused | — |
| 02 | 4 scenarios × 2 axes on a clone; cell counts before/after | — |
| 03 | 4 scenarios × 2 axes on a clone; orphan scan; last-row refusal | — |
| 04 | **Full ORD-1 test table re-run** (8 insert + 6 reorder HTTP cases, browser seam/arrow run); `npm test`, typecheck, build | — |
| 05 | 4 scenarios through the real agent in the chat; counts verified by query, not by tool response | — |
| 06 | 5 placement scenarios through the real agent | — |
| 07 | Cold chat session places a column from one natural sentence | — |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| 🔴 **Story 04 touches the working buttons** | Four endpoints the founder's UI depends on get their guts replaced. A regression here costs more than the feature is worth | Repoint before adding anything; re-run ORD-1's recorded test table as the gate; commit first |
| 🔴 **A second bug may hide under the empty `api.call`** | The six dead sites sit inside the exact `conditional`-in-`foreach` shape CLAUDE.md proves discards writes silently. Fixing the call may expose it, not fix it | Restructure the conditions to read the loop item; verify by database query, never by the tool's counters |
| 🔴 **Cascade delete by `field_value` removes one row** | `db.del` touches the first match only. A "working" cascade would orphan every cell after the first | Query → loop → delete by `id` → inside `db.transaction`; prove with before/after counts |
| 🟡 **The four actor templates have already drifted** | Extraction silently changes behaviour for whichever paths lose | Diff all four, record the winner per actor type in story 01 before replacing |
| 🟡 **Removing a key that execution depends on** | `primary_actor_lens` holds a lens key as text; `work_task` identity includes `stage_key` and `lens_key`. A remove can strand live records | Decide the rule in story 03 — refuse like DEL-1 does, or allow and log. **Do not leave it undecided** |
| 🟡 **The AI's identity on the write path** | The tools currently take `journey_map_id` and trust it. If the shared functions enforce ownership, an AI call with no actor fails; if they don't, the AI is a tenancy hole | Settle it in story 02, before the tools are repointed |
| 🟡 **Prompt edits are hard to verify** | A 40k-character prompt, with merge-conflict markers already sitting in agent 9's source | Smallest possible edit, diffed; agents 18 and 9 named separately |
| 🟢 **`function.run` in a `foreach`** | One query per iteration | Confirmed working and acceptable at these volumes (CLAUDE.md) |

## Decided

| Question | Decision | Date |
|---|---|---|
| Fix the dead sites with `api.call`, or with shared functions? | **Shared functions.** The endpoints are `auth = "user"` and a tool has no token; Xano's router can shadow a static path; an HTTP hop per operation inside a loop is worse than a function call. Also the standing CLAUDE.md house rule | 2026-10-19 |
| Does the AI need a separate "insert in the seam" concept? | **No.** The seam is a screen affordance. "Between A and B" is `after = A`, the input the buttons already use | 2026-10-19 |
| Does the AI address rows by key or by id? | **Key.** The agent reasons in keys and `get_map_state` returns keys; translation happens once, inside the tool | 2026-10-19 |
| Is the actor-template extraction in scope? | **Yes.** `add_lens` needs it, it is copied four times, and the copies already disagree — fixing it here is cheaper than fixing it twice | 2026-10-19 |
| Does remove close its numbering gap? | **Yes**, by calling ORD-1's order function on the survivors. Free, and closes ISSUES-BACKLOG #10 | 2026-10-19 |

## Still open

| Question | Why it's the founder's |
|---|---|
| **Should `Journey Map Builder` (agent 9) be allowed to place columns?** | Its prompt currently forbids adding anything: *"NEVER call scaffold_structure. NEVER call mutate_structure with add_stage or add_lens."* That was deliberate — the Builder runs fast phased cell-fill turns and structure was meant to be settled first. Letting it place columns mid-build makes builds more autonomous and less predictable. Recommend **leave it forbidden** for now; the Assistant is the right agent for structure |
| **Can a column or row be removed when a published plan references its key?** | Story 03 needs an answer. Recommend **refuse**, matching DEL-1's "a map in use can't be deleted" rule, with the message naming what depends on it |
| **Does ORD-1 get committed to git first?** | Story 04 edits four endpoints whose current, working source is **still uncommitted**. Recommend committing ORD-1 before this epic starts, so there is something to roll back to |

## Relationship to ORD-1 and the issues backlog

This epic closes, in whole or in part:

- **ISSUES-BACKLOG #1** (AI tools call an empty endpoint) — closed by story 05.
- **ISSUES-BACKLOG #8** (role prompts copied 4×, already drifted) — closed by
  story 01.
- **ISSUES-BACKLOG #10** (remove leaves a gap) — closed by story 03.
- **ORD-1 story 06's open gap** (the AI path was never run end-to-end through the
  chat) — closed by story 05's completion gate.

It does **not** touch #2 (`scaffold_map` crash), #3 (SEC-1 remainder), #4
(Playwright), #5 (platform admin), #7 (`owner_user` vs account) or #9, #11–#14.
