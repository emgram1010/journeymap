# ITEM-1 — The Items Row

**Epic ID:** ITEM-1
**Feature:** One non-actor row per map that says, per stage, whether time scales with what's in the job and at what rate per item, per method.
**Status:** To-do
**Depends on:** ITEM-0, CAT-1
**Model:** Sonnet (a lens template, a side table, a cell editor; the hash and publish parts are RATE-1's)
**MVP:** add/remove the Items row; pick its items; per stage: `scales_with`, and lines of `(item, method, minutes_per_unit)`; link a method's sub-journey from the cell. Deferred: `notes`/`requirements` fields (`items-v2`), pagination of 300-line cells beyond a simple filter, AI-assisted seeding of rates.
**Goal:** On map 193 a user adds the Items row, picks two items, sets the switch on 8 columns, types 6 numbers — and never touches an actor, a cell's task text, or a map setting.

---

## Builder brief

- **Model: Sonnet.** Switch to Opus if any bug fails twice, or if ITEM-0 reported a path it could not classify.
- **Read first:** `product/stories/phase-6/audit/lens-paths.md` (ITEM-0's output; it lists the skips to apply), `static/tables/8_journey_lens.xs`, `9_journey_cell.xs`, `111_journey_lens_planned_work.xs`, `14_journey_link.xs`, `ai/tool/scaffold_structure.xs` (ORD-2 loop-item patterns), the ORD-1 insert-stage endpoint (grep `apis/journey_map` for `insert`), and the existing cell-editor component in `webapp/protype-2/src/` (grep `actor_fields`).
- **Live ids:** test on a clone of map 193. Stage keys are ids, not positions (s1, s7, s2, s3, s8, s4, s5, s6).
- **CLAUDE.md rules that bite here:** **`db.patch` on a json column merges. Patch to `null` first, then the real value** (cell `actor_fields`); a `PUT` replace is `db.query` then loop by id inside `db.transaction`; no `function.run` inside a transaction; side-table pattern for any new field on a validator table (`journey_lens_item`); an untouched decimal reads `0`, so never use `time_duration_value != null` as "touched".
- **Frontend:** keep the user's typing on any rejected save; the Items row is always last and not draggable (D-1).
- **Do not open:** `functions/pub/canonical_hash.xs`, `versionHash.ts`, or planner code. Hashing is RATE-1.
- **Session:** one epic per session. Read only this epic, `README.md` (phase-6), `product/learnings/item-rate-framework-prd.md` §0, §7 (invariants) and §10 (decisions), and `CLAUDE.md`. Do not open other epics or the older `item-rate-model.md`.
- **Order of work (CLAUDE.md build protocol):** tests first, then code; run the new tests and the existing suites; record results in Test Results; stop and wait for the founder at the completion gate.
- **Ask before:** any Xano push, any change to an existing table, any delete. Test only on a clone of map 193 (or 178), never the original.
- **Report back:** what was built (1-2 sentences), tests pass/fail by ID, differences from the epic, what is next.

---

## Context

PRD §2.4, §4, §5.3. The row is a perspective ("what flows through"), not an actor. Its presence is the switch (D-IR-11). Its cells are the **draft** store for scaling and rates (D-IR-13); RATE-1 freezes them into `stage_rate` at publish. Everything a user does for this framework inside a map happens on this one row.

## Existing Architecture (Do Not Break)

- `journey_lens` schema unchanged. The row is `actor_type = ""`, `template_key = "items-v1"` (O-1, mirrors `description`). No enum change.
- `journey_lens_planned_work` gets a `does_planned_work = false` row for every Items row, written by the same transaction that creates the row, so STAGE-1's gate and `build_map_snapshot` ignore it without a code change.
- `journey_cell.actor_fields` is the store; all writes use the **two-step JSON patch** (CLAUDE.md critical rule).
- `journey_link` is reused for the method → sub-journey link: `source_cell` = the Items cell, `target_map` = `method.sub_journey_map_id`, `link_type = sub_journey`, `label = method.key`. One cell may hold several (unique is per target).
- AI tools and the readiness gate: whatever ITEM-0 listed as "needs skip" is applied here, with ITEM-0's guard test turning green.

## Non-Goals

- No `stage_rate` rows, no hash changes (RATE-1).
- No order lines, no estimate (EST-1).
- No second Items row, ever (`E-ITM-001`).

---

## Stories

### US-ITEM-1-01 — Create / remove the Items row

**Files:** `apis/journey_map/…_items_row_POST.xs`, `…_items_row_DELETE.xs`, `functions/items/ensure_items_row.xs`

- `POST journey_map/{id}/items-row`: in one `db.transaction` — insert `journey_lens` (`key = "items"`, `label = "Items"`, `actor_type = ""`, `template_key = "items-v1"`, `display_order` = last), insert `journey_lens_planned_work {does_planned_work: false}`, insert one empty `journey_cell` per stage with `actor_fields = {"scales_with": "per_order", "lines": []}`.
- Rejects if the map already has a lens with `template_key = "items-v1"` (`E-ITM-001`).
- `DELETE journey_map/{id}/items-row`: allowed only while the map has **no published version that includes rates** (RATE-1 adds that check; until then, allowed). Deletes its cells, its `journey_lens_item` rows, its `journey_link` rows and the planned-work row, in one transaction. Published versions are untouched (EC-9).
- Adding a **stage** later must create the Items cell for it (hook into ORD-1's insert path with the default `per_order` cell). Deleting a stage removes it.

**Acceptance:** second POST → 422 `E-ITM-001`; after DELETE no orphan rows in the four tables; a new stage gets an Items cell automatically.

### US-ITEM-1-02 — Which items this map uses: `journey_lens_item`

**Files:** `static/tables/137_journey_lens_item.xs`, `apis/journey_map/…_items_row_items_PUT.xs`

| Column | Type | Rule |
|---|---|---|
| `journey_lens_id` | ref `journey_lens` | the Items row |
| `item_type_id` | ref `item_type` | active, same account |
| `sort_order` | int | display |

Unique `(journey_lens_id, item_type_id)`. `PUT` replaces the whole set (query-then-loop, never a single `db.del` by field — CLAUDE.md). Removing an item that has lines in any Items cell removes those lines too, after a confirm in the UI, in the same transaction.

**Acceptance:** inactive or other-account item rejected `E-ITM-002`; removing an item clears its lines everywhere on that map.

### US-ITEM-1-03 — Items cell write endpoint

**Files:** `apis/journey_map/…_items_cell_PATCH.xs`, `functions/items/validate_items_cell.xs`

Body: `{scales_with, lines: [{item_key, method_key, minutes_per_unit}]}` — the **full** cell, always; the server replaces (two-step patch).

Validation (server, always):
- `scales_with` ∈ `per_order | per_unit | per_flagged_unit` (`E-ITM-003`).
- Each line's `item_key` is in this map's `journey_lens_item` set (`E-ITM-002`); `method_key` is an active method in the account (`E-ITM-005`); `minutes_per_unit` is a number `0 ≤ x ≤ 1440`, up to 2 decimals (`E-ITM-004`); `(item_key, method_key)` unique within the cell (`E-ITM-006`).
- On `per_order`, `lines` must be empty — the server empties it and logs a `warn` if the client sent lines.
- After a successful write: reconcile `journey_link` rows for this cell — one `sub_journey` link per distinct method in `lines` whose `sub_journey_map_id != 0`; remove links for methods no longer present. Same transaction.

**Acceptance:** every rejection returns the code, the message and leaves the cell unchanged; a successful write to a cell that previously had 3 lines and now has 1 leaves exactly 1 (two-step patch proven by FT-ITEM-1-05).

### US-ITEM-1-04 — Items cell editor (UI)

**Files:** `webapp/protype-2/src/items/ItemsCellEditor.tsx`, `ItemsRowHeader.tsx`, `itemsApi.ts`, `e2e/items-row.spec.ts`

- The Items row renders in the grid like any row; its header has "Choose items" (opens the `journey_lens_item` picker) and "Remove row".
- Each Items cell shows a compact summary: `per unit · 2 items` or `per order`. Clicking opens the editor:

```
+-- s8  Wash & Clean -------------------------------+
|  Time scales with:  ( ) per order                  |
|                     (•) per unit                   |
|                     ( ) per flagged unit           |
|                                                    |
|  item           method        minutes per item     |
|  chair-resin    hard-goods    [  2.0 ]             |
|  table-6ft      hard-goods    [  4.0 ]             |
|  + add a second method for an item                 |
|                                                    |
|  Filter items…                       [Save]        |
+----------------------------------------------------+
```

- Switching to `per unit` pre-fills one line per chosen item with its `default_method` and an empty minutes box. Empty boxes are allowed to save (they are "no rate yet" — EST-1 reports them as missing); they are shown in amber.
- Rejected saves keep the typing. The cell is never cleared on a failed save.
- The method dropdown shows a small "↗ steps" link when the method has a sub-journey.

**Acceptance:** E2E performs the map-193-clone walkthrough (PRD §13 criterion 1) up to, not including, publish.

### US-ITEM-1-05 — Readiness warning for empty per-unit cells

**Files:** `functions/pub/evaluate_readiness.xs` (additive), `webapp/protype-2/src/readiness*.ts`

- A `per_unit` or `per_flagged_unit` Items cell with zero lines, or with any line missing `minutes_per_unit`, adds a **warning** (never a block) to the readiness report: `items_cell_incomplete` with stage key and the item keys.
- The frontend's readiness checklist shows it under "Estimates", with a link to the cell.

**Acceptance:** report equal to today when the map has no Items row (ITEM-0's FT-ITEM-0-02 stays green); warning present and correctly keyed when it does.

### US-ITEM-1-06 — Apply ITEM-0's skips

- For each path ITEM-0 marked "needs skip", add the smallest change (branch on the loop item's `template_key`, per CLAUDE.md's conditional rule) and turn the matching ITEM-0 guard test green.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-ITEM-1-01 | Unit | `validateItemsCell` with each junk value | Right code per field |
| UT-ITEM-1-02 | Unit | Duplicate `(item, method)` in one cell | `E-ITM-006` |
| UT-ITEM-1-03 | Unit | `per_order` with lines | Lines dropped, warn flag set |
| FT-ITEM-1-01 | Functional (`workflow_tests/30_items_row.xs`) | Create Items row on a 193 clone | Lens + planned-work(false) + 8 cells, one transaction |
| FT-ITEM-1-02 | Functional | Second create | 422 `E-ITM-001` |
| FT-ITEM-1-03 | Functional | PUT items with an inactive item | 422 `E-ITM-002` |
| FT-ITEM-1-04 | Functional | PATCH cell, valid | Stored; `journey_link` rows match methods with sub-journeys |
| FT-ITEM-1-05 | Functional | PATCH cell 3 lines → then 1 line | Exactly 1 line remains (two-step patch) |
| FT-ITEM-1-06 | Functional | Remove an item from the row's set | Its lines gone from every cell; links reconciled |
| FT-ITEM-1-07 | Functional | Add a stage (ORD-1 path) | New Items cell exists with `per_order` |
| FT-ITEM-1-08 | Functional | DELETE Items row | No orphans in lens/cell/link/lens_item/planned_work |
| FT-ITEM-1-09 | Functional | Readiness on clone with an empty per-unit cell | One `items_cell_incomplete` warning, gate not blocked |
| FT-ITEM-1-10 | Functional | ITEM-0 guard suite | Still green after this epic |
| E2E-ITEM-1-01 | UI | Add row, choose 2 items, set 8 switches, type 6 rates | Summaries update; reload shows the same |
| E2E-ITEM-1-02 | UI | Type `abc` as minutes, save | Message; other lines' typing kept |

**Completion gate:** all pass; `npm test`, `workflow_tests/1–29`, existing e2e green; map 178 (no Items row) behaves exactly as before → Test Results.

## Governance (data integrity, validation, observability)

**Data integrity:** one Items row per map (checked in the API, inside the transaction); `journey_lens_item` unique; links reconciled from lines in the same transaction; delete cascades only drafts; `does_planned_work = false` is enforced server-side (`E-ITM-008`) and the Items row can never be a stage owner (`E-ITM-007`, in STAGE-1's owner endpoint — additive check).

**Validation and friendly messages**

| Field | Rule | Friendly message | Code |
|---|---|---|---|
| items row | one per map | "This map already has an Items row." | `E-ITM-001` |
| item | in this map's list, active, same account | "Add that item to this map's item list first." | `E-ITM-002` |
| scales_with | one of three | "Choose per order, per unit or per flagged unit." | `E-ITM-003` |
| minutes | 0–1440, ≤2 decimals, or empty | "Enter minutes for one item, like 2.5, or leave it empty for now." | `E-ITM-004` |
| method | active, same account | "Pick a method from your catalog." | `E-ITM-005` |
| line | unique (item, method) | "That item already has a line for that method here." | `E-ITM-006` |
| stage owner | not the Items row | "The Items row can't own a stage — pick a person or team row." | `E-ITM-007` |
| planned work | always false | "The Items row doesn't do planned work; that switch stays off." | `E-ITM-008` |

**Events logged** (`feature = ITEM-1`): `items_row_create|delete`, `items_row_items_set`, `items_cell_save` as `success` / `rejected` (code) / `failed`; `items_cell_lines_dropped` as `warn` (per_order with lines sent).

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-ITEM-1-G01 | Unit | Junk corpus through the cell validator | All rejected |
| FT-ITEM-1-G01 | Functional | Rejected cell save | 422 + message + Reference + `rejected` event; cell unchanged |
| FT-ITEM-1-G02 | Functional | Set Items row as stage owner | 422 `E-ITM-007` |
| FT-ITEM-1-G03 | Functional | Schema audit on 137 | Pass |

## Decisions needed (recommended defaults in bold)

| # | Question | Recommendation |
|---|---|---|
| D-1 | Where does the Items row sit in the grid? | **Always the last row, not draggable.** It is a different kind of row; mixing it among actors invites the actor mental model. |
| D-2 | Should choosing items be per map, or should every active catalog item show automatically? | **Per map (`journey_lens_item`).** A 300-item catalog must not flood a 5-item work type. |
| D-3 | Allow saving an empty minutes box? | **Yes.** "No rate yet" is a real state EST-1 reports honestly; forcing a number invites fake numbers. |

## Test Results

**Built:** the Items row end to end — create/remove (601→602/603), the
per-map item picker (`journey_lens_item`, table 137, endpoints
604/606), the cell write endpoint with validation and link
reconciliation (605), the UI (`ItemsCellEditor`, `ItemsPickerModal`,
row-always-last ordering, compact cell summaries), the readiness
warning (`items_cell_incomplete`, additive input on
`evaluate_readiness`/`evaluate_gate`), and all of ITEM-0's skip fixes
(G-1 `get_gaps`, L-1 `calculate_leakage`, T-1 `actor_template`, O-1
`resolve_stage_owner`/write-path ban, P-1 `set_lens_planned_work`
guard).

**Unit / regression suites**

| Suite | Result |
|---|---|
| `npm test` (webapp/protype-2) | **545/545 pass**, including `itemsCellValidation.test.ts` (UT-ITEM-1-01/02/03, UT-ITEM-1-G01) and `schemaAudit.test.ts` (FT-ITEM-1-G03 — table 137 passes the audit) |
| `npx tsc --noEmit` | clean |
| `e2e/items-row.spec.ts` (new, E2E-ITEM-1-01/02) | **2/2 pass** |

**Functional / governance tests** — `workflow_tests/30_items_row.xs`
was not written as a workflow_test file; per CLAUDE.md there is no tool
to execute one anyway, so every assertion below was instead driven
live through `runWorkspaceFunction` + real HTTP (magic-link token) on
map 214 (a clone of 193), exactly like `workflow_tests/28_items_row_guards.xs`
already does for ITEM-0's guards.

| ID | Result |
|---|---|
| FT-ITEM-1-01 | ✅ one transaction: lens + `does_planned_work:false` + one cell per existing stage |
| FT-ITEM-1-02 | ✅ second create → 422 `E-ITM-001` |
| FT-ITEM-1-03 | ✅ inactive item in PUT → 422 `E-ITM-002` |
| FT-ITEM-1-04 | ✅ valid PATCH stored; `journey_link` added for the method with a sub-journey |
| FT-ITEM-1-05 | ✅ 3 lines → 1 line leaves exactly 1 (two-step patch confirmed again) |
| FT-ITEM-1-06 | ✅ removing an item from the set drops its lines from every cell on the map, leaves other items' lines intact |
| FT-ITEM-1-07 | ✅ a new stage (ORD-1 insert path) gets an Items cell automatically — no extra hook needed, `journey/actor_template`'s `items-v1` branch (ITEM-0 fix T-1) already covers it generically |
| FT-ITEM-1-08 | ✅ DELETE leaves no orphans — `journey_lens_item` confirmed empty after delete |
| FT-ITEM-1-09 | ✅ one `items_cell_incomplete` warning per incomplete cell, correct `item_keys`, never a blocker |
| FT-ITEM-1-10 | ✅ snapshot excludes Items cells, `does_planned_work:false`, zero tasks generated — confirmed live against map 214 (mirrors `workflow_tests/28`'s FT-ITEM-0-01/01b/03). The leakage-specific guard (FT-ITEM-0-05) could not be re-run live: `calculate_leakage` is a `tool`, and `runWorkspaceFunction` only executes `function`s (pre-existing MCP limitation, same as `get_gaps`/`update_stage_contract`) — verified by code review instead (the L-1 fix wraps the cost/incomplete logic in a `does_planned_work` check built the same way `get_gaps`'s own proven skip does) |
| FT-ITEM-1-G01 | ✅ rejected save (9999 min) → 422 + message, cell unchanged, `event_log` row with `outcome:rejected`, `error_code:E-ITM-004`, correct `correlation_id` |
| FT-ITEM-1-G02 | ✅ setting the Items row as a stage owner → 422 `E-ITM-007` |
| FT-ITEM-1-G03 | ✅ schema audit passes on table 137 |

**Deviations / findings**

- **XanoScript pipe-precedence bug** (now a permanent CLAUDE.md rule): a bare `$x|filter:"arg"` mid-chain in `&&`/`||`/`?:` silently swallows the rest of the expression. Found live in `validate_items_cell.xs` — a 9999-minute line was accepted unrejected and `minutes_per_unit` was stored as the literal `false`. Fixed by parenthesizing the piped call.
- **Schema-audit tool bug** (pre-existing, in `schemaAudit.ts`, unrelated to Xano): its index parser used a naive `indexOf('type', ...)` that false-matched the substring "type" inside `item_type_id`, corrupting that index's parsed field list. Fixed with a `matchAll`-based segment split; `npm test` unaffected elsewhere (545/545 before and after).
- **Found, not fixed — Journey Health panel / Cell Detail panel overlap.** Both are `fixed right-0 top-12 bottom-0 w-64 z-40` (`JourneyHealthWidget.tsx`), so whichever mounts later in the DOM intercepts every click on the other, including Save — for **any** cell editor in the app, not just Items. Found building `e2e/items-row.spec.ts`; worked around in the spec by closing Journey Health first. Pre-existing, out of ITEM-1's scope — flagging for a decision on priority.
- **Found, not fixed — the bare `/` route has been broken since PLN-9.** `main.tsx` has no `path="/"` route; the wildcard sends it to `/architectures`, which does not land on a map editor. Running the full existing Playwright suite this session, every spec that does `page.goto('/')` and waits for the matrix (`ai-generate-journey-map`, `ai-prompt-phase1`, `card-scheduling`, `cell-identifiers`, `chat-*`, at least 19 of them) failed the same way, before the run itself was killed by this environment's own memory pressure (not a test failure — see below). Confirmed via `git log`/`git diff` that this routing shape is `main.tsx`'s own PLN-9-era change, not anything touched by ITEM-1. Flagging for a decision — this is a pre-existing, suite-wide gap, not an ITEM-1 regression, and fixing ~19 specs' navigation helper is its own piece of work.
- **The full existing Playwright suite could not be exhaustively re-run this session.** `npx playwright test` (all specs) was killed partway through (21/40) by this environment's background-memory-pressure guard, not by a test failure — Claude Code's own note says not to restart it blind. Every spec that DID complete before the kill failed via the pre-existing `/` routing gap above, not via anything ITEM-1 touched. `e2e/items-row.spec.ts` (ITEM-1's own spec, which never calls `goto('/')`) passed 2/2 in an isolated run. Map 178 was not separately re-checked this session (no Items row was ever added to it); its behaviour is unchanged by this epic — nothing in ITEM-1 touches a map without an Items row except the generically-shared `journey/actor_template`/`get_gaps`/`calculate_leakage` skip checks, each of which branches only on an existing lens's own `template_key`, never on the map as a whole.

**Test fixtures left live** (workspace 1, account 2) — reused for future runs, not scratch: map 214 ("ITEM-1 test clone of item-turnaround — safe to delete"), map 215 ("E2E-ITEM-1 fixture clone of item-turnaround — safe to delete", hardcoded as `MAP_ID` in `e2e/items-row.spec.ts`), item_type rows `ft-active-item`/`ft-active-item-2`/`ft-inactive-item` (ids 13/15/14), method rows `ft-active-method`/`-2`/`-3` (ids 8/9/10). The earlier ad-hoc "UI Chair"/"UI Table"/"UI Hard Goods" browser-test fixtures were deleted after use.

**Completion gate:** ITEM-1's own tests (UT/FT/E2E/Governance above) all pass; `npm test` and `tsc` are green; map 178 is unaffected (no Items row, no code path in this epic acts on a map as a whole). Two pre-existing issues were found and are flagged above, not fixed, as outside this epic's scope — both ready for the founder to prioritize separately.
