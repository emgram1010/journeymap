# Epic: System Handoff & Dependencies Template

**Goal:** Add a `handoff` lens type representing the connective flow between steps and actors in a journey map. Supports 12 structured cell fields covering triggers, upstream/downstream actors, data prerequisites, handoff format/timing, validation, failure recovery, and retention.

---

## Stories

### US-HND-01 — Add `handoff` to TypeScript types
**File:** `webapp/protype-2/src/types.ts`
- Add `'handoff'` to the `ActorType` union
- Add `HandoffActorFields` interface with 12 keys
- Update `ActorFields` union to include `HandoffActorFields`

### US-HND-02 — Add handoff template to constants.ts
**File:** `webapp/protype-2/src/constants.ts`
- Add `handoff-v1` entry to `ACTOR_TEMPLATES`
- 12 `CellFieldDef` entries with keys, labels, and placeholders
- Matching `cellFieldScaffold` with all 12 keys set to `null`
- Cell Detail Panel, badge, and wizard are already data-driven — no App.tsx changes needed

### US-HND-03 — Update add-lens API enum + scaffold
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"handoff"` to the `actor_type` enum values
- Add 12-key scaffold block under `if actor_type == "handoff"`

### US-HND-04 — Inject handoff fields into AI agent context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add handoff field block gated on `$cell_actor_type == "handoff"`
- Use same `$fv_temp` + paired `conditional` pattern (no `else`)

### US-HND-05 — Table schema update (Xano AI prompt)
**Table:** `journey_lens.actor_type`
- Prompt: *"Update the `actor_type` enum column on the `journey_lens` table to add `handoff` as an allowable value. The full updated list should be: `["customer", "internal", "engineering", "handoff", "operations", "ai_agent", "dev", "custom"]`"*
- Pull updated `tables/8_journey_lens.xs` after applying

---

## Fields Reference

| # | Key | Label |
|---|-----|-------|
| 1 | trigger_event | Trigger Event |
| 2 | upstream_actor | Upstream Actor |
| 3 | prerequisite_data | Prerequisite Data |
| 4 | upstream_dependencies | Upstream Dependencies |
| 5 | handoff_output | Handoff Output |
| 6 | handoff_format | Handoff Format |
| 7 | handoff_timing | Handoff Timing |
| 8 | downstream_actor | Downstream Actor |
| 9 | validation_rules | Validation Rules |
| 10 | failure_recovery | Failure Recovery |
| 11 | communication_method | Communication Method |
| 12 | data_retention_policy | Data Retention Policy |
