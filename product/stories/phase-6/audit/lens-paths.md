# ITEM-0 audit — every lens-iterating path, and what it does when it meets the Items row

> **Run:** 2026-10-24, Opus 5, workspace 1. **Clone used:** map **213** (`ITEM-0 audit clone of item-turnaround`, from 193), Items row = lens **1248**, 8 Items cells (ids 9994–10001), with **real per-unit lines** in s2 and s8 so nothing was verified on empty data.
> **Row under test:** `journey_lens` with `key = "items"`, `label = "Items"`, `actor_type = ""`, `template_key = "items-v1"`, plus an explicit `journey_lens_planned_work.does_planned_work = false`.
> **No production file was changed by this epic.** Proposed changes are listed with file and line for ITEM-1 / RATE-1 to apply.

---

## 1. Headline findings

| # | Finding | Severity | Owner |
|---|---|---|---|
| **G-1** | `get_gaps` reports **all 8** Items cells as empty gaps — *including the two holding real rates* — and names the Items row as `most_empty_lens`. The AI builder would be pointed at it as the highest-priority thing to fill with prose. | **Must fix** | ITEM-1 |
| **L-1** | `calculate_leakage` has **no structural guard**. It contributes 0 today only because the Items row has no `cost_rate` and its cells no `time_duration`. Giving it both charged **50/event at s8**, live. Safe by accident, not by design. | **Must fix** | ITEM-1 |
| **H-1** | Adding the Items **row** changes the version hash (it emits a `lens\|` line), but changing its **rates** does **not** — proven: identical hash `9be07a8d…` before and after adding per-unit lines to a second stage. Two versions differing only in rates are indistinguishable. | **Must fix** | RATE-1 (already its reason to exist; now proven, not inferred) |
| **J-1** | `db.patch` on `journey_cell.actor_fields` **merges**, confirmed on this exact column: a probe key survived a single patch and vanished only after the two-step `null`-then-value patch. | Confirmed rule | ITEM-1 |
| **O-1** | `resolve_stage_owner` is a pure key lookup with no actor filter, so a stage **can** name the Items row as its owner. The ban must be enforced at the write path. | Should fix | ITEM-1 (`E-ITM-007`) |
| **T-1** | `actor_template` has no `items-v1` branch, so a stage added later gives the Items row a cell with **empty** `actor_fields`, not the `{scales_with: "per_order", lines: []}` default. | Should fix | ITEM-1 |
| **P-1** | `doesPlannedWork` honours any explicit override, including `true`. Nothing in the shared predicate stops the Items row being switched on. | Should fix | ITEM-1 (`E-ITM-008`) |
| **C-1** | `clone_scenario` does **not** copy `map_level` (the clone came back non-atomic and leakage refused to run until it was set by hand). Pre-existing, unrelated to this framework. | Note only | Not phase-6 |

**Everything else is safe.** The two mechanisms that carry the most weight — `does_planned_work` and the work-row filter in `build_map_snapshot` — hold, and they hold for two independent reasons (see §2).

---

## 2. Why the core is safe, twice over

`functions/does_planned_work.xs` defaults to `($actor_type == "internal" || $actor_type == "ai_agent")`. For `actor_type = ""` that is **false** before any override row is read. So the Items row resolves to "does no planned work" even if ITEM-1's explicit `false` row were missing. The explicit row is belt-and-braces, and worth keeping.

`functions/pub/build_map_snapshot.xs:233` gates cell emission on `$cell_does_work == true`. Confirmed live: `cell_count` stayed **8** after adding 8 Items cells with real content.

⚠️ **A divergence worth recording.** In XanoScript `"" != null` is **false** (loose equality, CLAUDE.md). In TypeScript `"" != null` is **true**. Both sides reach `false` for the Items row, but by different routes:

| | Expression | Result | Why |
|---|---|---|---|
| XanoScript (`get_gaps:244`) | `$actor_type != null && $actor_type != ""` | false | first clause already false — `"" == null` |
| TypeScript (`stageOwnerModel:33`) | `actorType != null && TYPES.includes(actorType)` | false | first clause true, `includes("")` false |

Neither is wrong, but anyone porting one to the other will get a surprise. Do not "fix" the XanoScript clause to match the TypeScript.

---

## 3. Backend — full inventory

### 3.1 Needs a change (4)

| File | What it does per lens | Filters today | Verdict | Proposed change |
|---|---|---|---|---|
| `ai/tool/get_gaps.xs` | Reports empty cells; non-actor rows are "empty when `content` is empty" (line 303-306, `else` branch) | `actor_type != null && != ""` (line 244) — sends `""` down the non-actor branch | **Needs skip (G-1)** | Skip the lens entirely when `$l_rec.template_key == "items-v1"`. Branch on the loop item, which is the only shape that works (CLAUDE.md). Apply in the lens loop at line 87, not inside the cell loop. |
| `ai/tool/calculate_leakage.xs` | Multiplies cell `time_duration_value` × lens `cost_rate` (line 97) | none on row kind | **Needs skip (L-1)** | Resolve `does_planned_work` per lens and skip rows where it is false — which also removes the `description` row's existing false entries from `incomplete_cells`. |
| `functions/journey/actor_template.xs` | Returns the template + default `actor_fields` for a `template_key` | branches on 8 known keys; `items-v1` falls through to `$type = ""` and the `precondition` at line 365 lets it pass | **Needs addition (T-1)** | Add an `items-v1` branch returning `actor_fields = {scales_with: "per_order", lines: []}`. One place fixes `insert_stage` and `scaffold_map`/`mutate_structure` `add_stage` at once — they all read this. |
| `apis/journey_map/211_journey_stage_update_…_PATCH.xs` + `ai/tool/update_stage_contract.xs` | Sets a stage's owner via `resolve_stage_owner` | none on row kind | **Needs guard (O-1)** | Reject when the resolved lens has `template_key = "items-v1"` → `E-ITM-007`. The pure resolver stays as is. |

### 3.2 Defensive guard wanted, low severity (3)

These take an explicit `lens_key` from the caller, so they only touch the Items row if something points them at it — which **G-1 would do**. Fixing `get_gaps` removes the realistic path; the guard is cheap insurance.

| File | Risk | Proposed change |
|---|---|---|
| `ai/tool/fill_cells.xs` | Would write `content`/`actor_fields` into an Items cell, overwriting rates with prose | Refuse a write to an `items-v1` lens unless the payload validates as an Items cell (ITEM-1's validator) |
| `ai/tool/batch_update.xs` | Would write `content` (rates live in `actor_fields`, so data survives, but the cell gains stray prose) | Same refusal |
| `ai/tool/update_actor_cell_fields.xs` | Validates `actor_fields` keys by `actor_type`; `""` has no key list | Same refusal, with a message naming the Items cell endpoint instead |

### 3.3 Safe — verified, no change (24)

| File | Why safe |
|---|---|
| `functions/pub/build_map_snapshot.xs` | Gates on `does_planned_work`; **live: cell_count 8 → 8** |
| `functions/pub/canonical_hash.xs` | Pure over the snapshot it is given; emits `lens\|` for all rows, cells only for what it is handed (see H-1 for what this means) |
| `functions/pub/evaluate_readiness.xs` | Builds `works_by_lens` from `does_planned_work` (line 97); **live: report byte-identical before and after** |
| `functions/jobs/tasks_from_version.xs` | Two-phase, eligibility as a field (line 71); **live: 8 tasks, 0 for Items, 0 skipped** |
| `functions/does_planned_work.xs` | The resolver itself — correct default for `""` |
| `functions/resolve_stage_owner.xs` | Pure lookup; correct to stay unfiltered (the ban belongs at the write path) |
| `functions/set_lens_planned_work.xs` | Writes the override it is told to; ITEM-1 guards it (`E-ITM-008`) |
| `functions/journey/insert_stage.xs` | Loops all lenses and creates a cell each — **desired**; needs only T-1's template |
| `functions/journey/insert_lens.xs`, `remove_lens.xs`, `next_lens_key.xs`, `apply_lens_order.xs` | Single-lens structural ops by id/key |
| `functions/journey/delete_map_cascade.xs`, `orphan_report.xs` | Delete/report by map; row kind irrelevant |
| `functions/journey/visible_lens_ids.xs`, `visible_map_ids.xs` | Tenancy scoping only |
| `functions/perform/hydrate_statuses.xs`, `functions/planner/derive_tasks.xs`, `job_step_hydration.xs` | Consume `work_task` rows, which the Items row can never produce (T-1 above) |
| `functions/live/build_publication.xs`, `functions/variance/task_report.xs` | Downstream of tasks, same reason |
| `functions/ops/audit_execution.xs`, `audit_integrity.xs` | Audit tasks/jobs, not lenses |
| `ai/tool/validate_workflow.xs` | Only looks at `actor_type == "internal"` (line 85) — Items row invisible |
| `ai/tool/clone_scenario.xs` | Copies `actor_type`, `template_key`, cost rates, `actor_fields` (line 280) and planned-work overrides (line 415) — **clones the Items row correctly**. See C-1 for `map_level`. |
| `ai/tool/mutate_structure.xs`, `scaffold_map.xs`, `scaffold_structure.xs` | `add_lens` requires an `actor_type` from a fixed list, so neither can create a second Items row. `add_stage` scaffolds cells for all lenses — desired, needs T-1. `remove_lens` by key could remove the Items row → RATE-1's `E-RATE-002` covers it after a rated publish. |
| `ai/tool/get_map.xs`, `get_map_state.xs`, `get_slice.xs`, `get_stage_detail.xs`, `search_cells.xs`, `batch_set_status.xs`, `set_cell_status.xs`, `update_actor_identity.xs`, `update_cell.xs`, `infer_stage_metrics.xs` | Read-only, or explicit single target with no all-lens write |
| `apis/journey_map/124_…_scorecard_GET.xs` | Filters explicitly to `metrics-v1` / `financial-v1` |
| `apis/journey_map/30–35, 46, 49, 50, 63, 517, 518, 582` (lens CRUD, rename, reorder, planned-work) | Single lens by id; no all-lens iteration |
| `apis/journey_map/22, 42, 43, 47, 51, 52, 61, 69, 76, 126, 129, 130, 202` | Map-level load/delete/AI-message/export; no row-kind logic |
| `apis/planner/555, 559` | Read jobs and work tasks |
| `ai/agent/*`, `ai/mcp_server/journey_map.xs` | Prompt/registry text only; behaviour comes from the tools above |

---

## 4. Frontend — full inventory

| File | Verdict | Note |
|---|---|---|
| `stageOwnerModel.ts` | Safe, with P-1 | `doesPlannedWork('', null)` → false; an explicit `true` would win (pinned by UT-ITEM-0-03) |
| `jobModel.ts` | Safe | `if (!lens?.does_planned_work) continue` (line 109); an Items row named as owner raises a visible error (line 98) rather than silently passing |
| `readiness.ts` | Safe | Uses the override/default pair |
| `journeyMatrixTabulatorHelpers.ts`, `JourneyMatrixTabulator.tsx`, `matrixOrder.ts` | Safe | Render by `display_order`; ITEM-1 pins the Items row last (D-1) |
| `App.tsx` (`cellHasAnyContent`, line 1185) | **Review in ITEM-1** | AUTH-1's content predicate. ITEM-1 must ensure an Items cell with `lines: []` does not read as "partially filled" — the AUTH-1 decimal bug in a new costume |
| `versionHash.ts` / `.test.ts` | Safe now, **changes in RATE-1** | Needs the `scaling[]` / `rates[]` sections and a v2 golden |
| `types.ts`, `xano.ts`, `constants.ts` | Safe | Types and transport; `xano.ts` already reads `template_key` |
| `exportMarkdown*.ts` (3), `ScenariosTab.tsx`, `ActorSetupWizard.tsx`, `StageEditPanel.tsx`, `JourneyHealthWidget.tsx` | Safe | Display/export; an Items row exports as a row with empty prose — cosmetic, worth a later pass |
| `cellIdentifiers.ts`, `cellPersistence`, `persistedCellUpdates.ts` | Safe | Address cells by stage+lens, kind-agnostic |
| `scheduleModel.ts`, `liveModel.ts`, `perform/*`, `planner/*` | Safe | Downstream of tasks |
| `ops/schemaAudit.ts` | Safe | Will need the 5 new tables added in their own epics |

---

## 5. Live evidence

| Check | Before Items row | After Items row | After rates added |
|---|---|---|---|
| `schema_version` | 1 | 1 | 1 |
| `lenses[]` count | 2 | 3 | 3 |
| `cells[]` count | **8** | **8** | **8** |
| `content_hash` | `dc0fe2d98840fa0e…` | `9be07a8d50b610d6…` | `9be07a8d50b610d6…` *(unchanged — H-1)* |
| readiness | ready, 8/8, 0 blockers, 0 warnings | **identical** | **identical** |
| tasks generated | 8 | 8, **0 for Items**, 0 skipped | 8, 0 for Items, 0 skipped |
| `get_gaps` total | 0 | **8, all Items** | **8, all Items** (G-1) |
| leakage per_event | 0 | 0 | 0 — but **50** once the row got a cost rate and a cell a duration (L-1) |
| `actor_fields` single patch | — | probe key **survived** (merge) | — |
| `actor_fields` two-step patch | — | probe key **gone** (replace) | — |

---

## 6. Answers to ITEM-0's own decisions

- **D-1 — where to apply the skips:** in the epic that needs them (ITEM-1), with this audit's guard tests already red for L-1. ITEM-0 changed no production file. Confirmed.
- **D-2 — empty per-unit cell a readiness warning?** Yes, warning not block. Readiness is provably indifferent to the Items row today, so ITEM-1 adds the warning deliberately rather than inheriting one.

## 7. Carried into ITEM-1 / RATE-1

1. ITEM-1 US-ITEM-1-06 gains four named changes: G-1, L-1, T-1, O-1 (+ P-1 as `E-ITM-008`, already specified).
2. ITEM-1 must check `App.tsx:1185 cellHasAnyContent` against an Items cell with `lines: []`.
3. RATE-1's H-1 is now evidence, not inference — and its US-RATE-1-02 note is confirmed: non-work rows do appear in `lenses[]`, so adding the row already moves the hash; only the rates are missing.
4. `clone_scenario` not copying `map_level` (C-1) is a separate, pre-existing bug. Not fixed here.
