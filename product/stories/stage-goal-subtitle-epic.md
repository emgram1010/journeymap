# Epic: Stage Header — Full Platform Enablement

## Concept Alignment

**`stage_goal`** — The *exit condition* for a stage. One sentence that must be TRUE before the process advances. Think acceptance criteria at the stage level. e.g. *"Intake parsed; name, company, and pain point confirmed."* Without it, neither a human nor an AI agent knows when a stage is actually *done*.

**`primary_actor_lens`** — The lens *key* (e.g. `lens-3`) of the actor who *owns* this stage — not who participates, but who is accountable for the stage outcome. The Orchestrator uses this to know whose `task_objective`, `tools_systems`, and `information_needs` to lead with when executing the stage.

Together they turn a stage from a label into a **contract**: *this actor is accountable; here is the definition of done.*

---

## Problem

The stage column header shows only the label. `stage_goal` and `primary_actor_lens` exist in the backend API (endpoint 211) but:
- Are **not in the table schema** (local `.xs` file missing both columns)
- Are **invisible to AI agents** — `get_map_state` and `get_slice` do not return them
- Are **not writable by agents** — `scaffold_structure` ignores them; no agent prompt mentions them
- Are **not in the frontend** — no type, no render, no edit path

## Solution Overview

Enable the fields end-to-end: DB → API → AI read tools → AI write tools → agent prompts → frontend render + edit.

The stage column header is redesigned to show all three pieces of information and support in-place editing via a `StageEditPanel` — consistent with how the lens header uses `ActorSetupWizard`.

### Stage Header Visual Design

```
┌──────────────────────────────────┐
│                              ✎  │  ← pencil btn (hover only, top-right)
│  Receive Intake                  │  ← label: white #fff, 13px semibold
│  👤 Customer                     │  ← primary actor: indigo pill #6366f1
│  Intake parsed; name,            │  ← stage_goal: zinc #a1a1aa, 10px,
│  company, pain confirmed         │     2-line clamp, italic
└──────────────────────────────────┘

When fields are empty:
│  👤 · No actor                   │  ← muted gray pill, dashed border
│  ⚠ No goal set                   │  ← amber #f59e0b warning
```

**Color tokens:**
| Element | Value |
|---|---|
| Stage label | `#ffffff`, 13px, weight 600 |
| Primary actor pill (set) | bg `#6366f1`, text `#fff`, 9px uppercase |
| Primary actor pill (unset) | bg transparent, border `#52525b` dashed, text `#71717a` |
| Stage goal (set) | `#a1a1aa`, 10px, italic, `-webkit-line-clamp: 2` |
| Stage goal (unset) | `#f59e0b`, 10px, `⚠ No goal set` |
| Edit button | `✎`, hidden until hover, top-right, same style as `.jm-lens-edit-btn` |

**Interaction model:** Remove `editableTitle: true`. Clicking the edit button opens `StageEditPanel` (right-side panel or popover) with label, primary actor dropdown, and stage goal textarea. Saving calls endpoint 211 (`/journey_stage/update/:id`).

---

## Stories

### US-SG-01 — Add `stage_goal` and `primary_actor_lens` columns to journey_stage table
**File:** `tables/7_journey_stage.xs`

**Story:** As the system, I need both fields stored in the database so every other layer can read and write them.

**AC:**
- `stage_goal text? filters=trim` column added to the `journey_stage` schema
- `primary_actor_lens text? filters=trim` column added
- Both are nullable — no existing rows are broken

---

### US-SG-02 — Accept new fields on add_stage API
**File:** `apis/journey_map/47_journey_stage_add_journey_map_id_POST.xs`

**Story:** As a user or AI agent creating a stage, I can optionally set the goal and primary actor at creation time so new stages are not born blind.

**AC:**
- `text stage_goal? filters=trim` and `text primary_actor_lens? filters=trim` added to input
- Both passed into the `db.add` data block alongside `label`, `key`, `display_order`
- Omitting them is valid — they default to null

---

### US-SG-03 — Expose `stage_goal` and `primary_actor_lens` in `get_map_state` tool
**File:** `tools/2_get_map_state.xs`

**Story:** As an AI agent, I need to see `stage_goal` and `primary_actor_lens` when I read the map so I can reason about stage ownership and completion criteria.

**AC:**
- The `stages` array in the response includes `stage_goal` and `primary_actor_lens` on each stage object (they come from `$stages` DB query which already returns all columns — confirm projection passes them through)
- The `instructions` comment in the tool updates the documented response shape: `{ id, key, label, display_order, stage_goal, primary_actor_lens }`
- No logic change needed if `$stages` is returned raw — only the instruction comment needs updating

---

### US-SG-04 — Expose fields in `get_slice` column mode
**File:** `tools/8_get_slice.xs`

**Story:** As an AI agent slicing a single column, I need the stage object to include `stage_goal` and `primary_actor_lens` so I have full stage context without calling `get_map_state`.

**AC:**
- In column mode, the `stage` object in `$result` is updated from `{key, label, display_order}` to include `stage_goal: $stage.stage_goal, primary_actor_lens: $stage.primary_actor_lens`
- Same addition in the `instructions` comment for the column response shape

---

### US-SG-05 — Accept `stage_goal` and `primary_actor_lens` in `scaffold_structure` rename op
**File:** `tools/7_scaffold_structure.xs`

**Story:** As an AI agent scaffolding a map structure, I can set the stage goal and primary actor lens alongside the label in a rename operation so the scaffold fully populates the stage contract.

**AC:**
- `rename` operation in the stage loop reads `$op.stage_goal` and `$op.primary_actor_lens` alongside `$op.label`
- Both are included in the `db.edit journey_stage` data block (nullable — if not provided they write null, preserving existing nullability)
- Tool `instructions` text updated to mention both optional fields on rename ops

---

### US-SG-06 — Update Journey Map Assistant prompt to use stage contract fields
**File:** `agents/2_journey_map_assistant.xs`

**Story:** As the AI assistant, I should know that `stage_goal` and `primary_actor_lens` exist on every stage so I can read them, reference them in analysis, and set them via `scaffold_map` when appropriate.

**AC:**
- System prompt mentions `stage_goal` (exit condition / definition of done for the stage) and `primary_actor_lens` (lens key of the stage owner) under the "Map state context" section
- Prompt notes that `scaffold_map` can set both fields in a rename operation
- Prompt notes that when a user asks "who owns stage X" or "what's the goal of stage X", the agent reads these fields from `get_map_state` before answering

---

### US-SG-07 — Update Journey Map Builder prompt to set stage fields in Phase 1
**File:** `agents/4_journey_map_builder.xs`

**Story:** As the AI builder, when executing Phase 1 (scaffold / frame the journey), I should assign `stage_goal` and `primary_actor_lens` to every stage so the map is never built without stage contracts.

**AC:**
- Phase 1 instruction updated: after calling `scaffold_map` to set stage labels, call `scaffold_map` again (or include in the initial call) with rename ops that set `stage_goal` and `primary_actor_lens` for each stage
- System prompt explains: `primary_actor_lens` = the lens key whose actor owns this stage; `stage_goal` = one-sentence exit condition inferred from the journey scope and stage label

---

### US-SG-08 — Extend `XanoJourneyStage`, `Stage`, and add `updateStageDetails` to xano.ts
**File:** `webapp/protype-2/src/xano.ts`

**Story:** As the frontend, I need the Stage type to carry both new fields and a write function that calls endpoint 211 so every component can read and save stage details.

**AC:**
- `XanoJourneyStage` gets `stage_goal?: string | null` and `primary_actor_lens?: string | null`
- `Stage` (in `buildHydratedJourneyMapBundle`) maps both fields: `stageGoal` and `primaryActorLens`
- New export `updateStageDetails(stageId: number, data: { label: string; stageGoal?: string | null; primaryActorLens?: string | null }): Promise<XanoJourneyStage>` calls `PATCH /journey_stage/update/:id` (endpoint 211)
- Existing `renameJourneyStage` (endpoint 45) is kept for backward compat but deprecated internally — callers in `App.tsx` migrate to `updateStageDetails`

---

### US-SG-09 — Extend `Stage` interface in types.ts
**File:** `webapp/protype-2/src/types.ts`

**AC:**
- `Stage` interface gains `stageGoal?: string` and `primaryActorLens?: string`

---

### US-SG-10 — Add `formatStageHeaderMarkup` helper
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

**Story:** As a developer, I want a pure function that renders the 3-layer stage header HTML so the column definition stays clean and the markup is independently testable.

**AC:**
- `formatStageHeaderMarkup({ label, stageGoal, primaryActorLens, primaryActorLabel, stageId }: { label: string; stageGoal?: string; primaryActorLens?: string; primaryActorLabel?: string; stageId: string })` exported
- Renders: edit button `data-edit-stage-id`, bold label, actor pill (indigo if set / dashed muted if not), goal subtitle (zinc if set / amber ⚠ if not)
- All strings HTML-escaped via `escapeHtml()`; goal capped at 120 chars + `…`
- Returns valid HTML string

---

### US-SG-11 — Update `JourneyMatrixTabulator` column definitions and click delegation
**File:** `webapp/protype-2/src/JourneyMatrixTabulator.tsx`

**Story:** As a user, clicking the edit button on a stage column header fires `onEditStage` so `App.tsx` can open the `StageEditPanel`.

**AC:**
- `editableTitle: true` removed from stage column definitions
- Column `title` uses `formatStageHeaderMarkup(...)` with resolved `primaryActorLabel` (looked up from `lenses` prop by matching `stage.primaryActorLens` key)
- `onEditStage: (stageId: string) => void` added to `Props`; `onEditStageRef` added to avoid stale closures
- Container click handler intercepts `[data-edit-stage-id]` clicks: stops propagation, calls `onEditStageRef.current(stageId)`, returns early
- `columnTitleChanged` handler removed (no longer needed — `editableTitle: true` gone)
- `columnsSignature` updated to include `stageGoal` and `primaryActorLens` per stage: `` `${s.id}:${s.label}:${s.stageGoal ?? ''}:${s.primaryActorLens ?? ''}` ``

---

### US-SG-12 — Build `StageEditPanel` component
**File:** `webapp/protype-2/src/StageEditPanel.tsx` *(new)*

**Story:** As a user, clicking the edit button on a stage header opens a focused panel where I can edit the stage name, choose the primary actor from a dropdown of existing lenses, and write or update the stage goal — then save in one click.

**AC:**
- Props: `stage: Stage`, `lenses: Lens[]`, `onSave: (data) => void`, `onClose: () => void`, `isSaving: boolean`
- Three fields: label (text input, required), primary actor (native `<select>` populated from `lenses` — shows lens label, stores lens key; blank option = "None"), stage goal (textarea, placeholder *"What must be TRUE when this stage is done?"*)
- Save button calls `onSave({ label, primaryActorLens, stageGoal })`; disabled while `isSaving`
- Escape key and click-outside close the panel
- Consistent visual style with `ActorSetupWizard` (same panel width, header, footer buttons)

---

### US-SG-13 — Wire `StageEditPanel` in `App.tsx`
**File:** `webapp/protype-2/src/App.tsx`

**AC:**
- `editingStageId` state (string | null)
- `handleEditStageOpen(stageId: string)` sets `editingStageId`
- `handleStageDetailsSave` calls `updateStageDetails`, patches the `stages` state with the returned record, clears `editingStageId`
- `<JourneyMatrixTabulator onEditStage={handleEditStageOpen} ...>`
- `{editingStageId && <StageEditPanel stage={...} lenses={lenses} onSave={handleStageDetailsSave} onClose={() => setEditingStageId(null)} isSaving={isSaving} />}`

---

### US-SG-14 — CSS for stage header design
**File:** `webapp/protype-2/src/index.css`

**AC:**
- `.jm-stage-header` — flex column, padding `10px 12px`, position relative
- `.jm-stage-label` — `#ffffff`, 13px, weight 600, truncate single line
- `.jm-stage-actor-pill` — indigo set state: bg `#6366f1`, text `#fff`, 9px, uppercase, rounded; unset state: transparent bg, `1px dashed #52525b`, text `#71717a`
- `.jm-stage-goal` — `#a1a1aa`, 10px, italic, `-webkit-line-clamp: 2`, overflow hidden
- `.jm-stage-goal.is-empty` — `#f59e0b`, non-italic
- `.jm-stage-edit-btn` — same spec as `.jm-lens-edit-btn` (hidden, top-right, revealed on `.jm-stage-header:hover`)
- No layout shift on hover

---

## Scope Summary

| Layer | Files |
|---|---|
| DB | `tables/7_journey_stage.xs` |
| API | `apis/journey_map/47_journey_stage_add_journey_map_id_POST.xs` |
| AI read | `tools/2_get_map_state.xs`, `tools/8_get_slice.xs` |
| AI write | `tools/7_scaffold_structure.xs` |
| Agents | `agents/2_journey_map_assistant.xs`, `agents/4_journey_map_builder.xs` |
| Frontend types | `webapp/protype-2/src/types.ts`, `webapp/protype-2/src/xano.ts` |
| Frontend render | `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`, `webapp/protype-2/src/JourneyMatrixTabulator.tsx` |
| Frontend edit | `webapp/protype-2/src/StageEditPanel.tsx` *(new)*, `webapp/protype-2/src/App.tsx` |
| Styles | `webapp/protype-2/src/index.css` |

