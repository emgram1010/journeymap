# Epic: Internal Actor Template

**Goal:** Add a fully functional `internal` actor type representing any internal employee role in the journey map. Supports 12 structured cell fields covering task objectives, tools, handoffs, constraints, and pain points.

---

## Stories

### US-IAT-01 — Add `internal` to TypeScript types
**File:** `webapp/protype-2/src/types.ts`
- Add `'internal'` to the `ActorType` union
- Add `InternalActorFields` interface with 12 keys
- Update `ActorFields` union to include `InternalActorFields`

### US-IAT-02 — Add internal template to constants.ts
**File:** `webapp/protype-2/src/constants.ts`
- Add `internal-v1` entry to `ACTOR_TEMPLATES`
- 12 `CellFieldDef` entries: task_objective, entry_trigger, tools_systems, information_needs, decisions_required, friction_points, assumptions, handoff_dependencies, success_criteria, output_deliverable, employee_constraints, pain_points
- Matching `cellFieldScaffold` with all 12 keys set to `null`
- No changes needed in App.tsx or journeyMatrixTabulatorHelpers — already data-driven

### US-IAT-03 — Update add-lens API for internal scaffold
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"internal"` to the `actor_type` enum values
- Add scaffold block mirroring the 12 internal fields

### US-IAT-04 — Inject internal fields into AI agent context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add a parallel block to the existing customer field injection
- Check `$actor_lens.actor_type == "internal"`, then iterate all 12 fields using the same `$fv_temp` + paired `conditional` pattern (no `else`)

### US-IAT-05 — Minimal scaffold on new journey map creation

**Story:** As a user creating a new journey map, I want to start with only the stages row
and a single Description row so that my initial canvas is clean and uncluttered — I can
add actor rows myself as I decide who is relevant to my map.

**UX Notes:**
- A newly created map opens with **8 stages** (Stage 1 – Stage 8) and **exactly one lens
  row: Description** ("Brief summary of what happens at this stage — the core activity.").
- The empty 8 × 1 grid communicates structure without overwhelming the user with
  prefilled rows they did not ask for.
- The existing **"+ Add Row"** button (opens the Actor Setup Wizard) is the primary
  affordance for growing the matrix. It must remain enabled and prominent even when
  only one lens row exists.
- The "Add Row" button label and wizard copy should reinforce that rows are actor
  perspectives (e.g. "Add an actor row — Customer, Internal team, AI agent…").
- No changes to the Actor Setup Wizard flow itself; the wizard already handles all
  actor types (`customer`, `internal`, `operations`, `ai_agent`, `dev`, `custom`).

**Acceptance Criteria:**
- `POST /journey_map/create_draft` creates exactly **1 lens** (`key: "description"`,
  `label: "Description"`) and **8 stages** — no other lens seeds are inserted.
- Opening a freshly created map in the editor shows a single row labelled "Description"
  with 8 empty cells.
- The "Add Row" button is visible and clickable on a single-lens map (not gated on
  having ≥ 2 rows).
- Clicking "Add Row" on a single-row map opens the Actor Setup Wizard normally.
- Existing maps that already have more than one lens row are unaffected.

**Implementation scope:**
- `apis/journey_map/42_journey_map_create_draft_POST.xs` — remove the 9 non-description
  `array.push $lens_seeds` blocks; keep only the `description` seed.
- No frontend changes required — `App.tsx` "Add Row" button has no minimum-row guard.

---

## Fields Reference

| # | Key | Label |
|---|-----|-------|
| 1 | task_objective | Task / Objective |
| 2 | entry_trigger | Entry Point / Trigger |
| 3 | tools_systems | Tools & Systems Used |
| 4 | information_needs | Information Needs |
| 5 | decisions_required | Decisions Required |
| 6 | friction_points | Friction Points |
| 7 | assumptions | Assumptions Being Made |
| 8 | handoff_dependencies | Handoff Dependencies |
| 9 | success_criteria | Success Criteria |
| 10 | output_deliverable | Output / Deliverable |
| 11 | employee_constraints | Employee Constraints |
| 12 | pain_points | Pain Points |
