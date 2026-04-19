# Epic: Engineering Lens Template

**Goal:** Add a fully functional `engineering` lens type representing the technical/engineering perspective in a journey map. Supports 10 structured cell fields covering system ownership, data flows, integrations, business rules, error handling, storage, security, performance, and audit requirements.

---

## Stories

### US-ENG-01 — Add `engineering` to TypeScript types
**File:** `webapp/protype-2/src/types.ts`
- Add `'engineering'` to the `ActorType` union
- Add `EngineeringActorFields` interface with 10 keys
- Update `ActorFields` union to include `EngineeringActorFields`

### US-ENG-02 — Add engineering template to constants.ts
**File:** `webapp/protype-2/src/constants.ts`
- Add `engineering-v1` entry to `ACTOR_TEMPLATES` (replaces `dev` comingSoon slot)
- 10 `CellFieldDef` entries with keys, labels, and placeholders
- Matching `cellFieldScaffold` with all 10 keys set to `null`
- Cell Detail Panel and badge rendering are already data-driven — no App.tsx changes needed

### US-ENG-03 — Update add-lens API for engineering scaffold
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"engineering"` to the `actor_type` enum values
- Add scaffold block with 10 engineering keys

### US-ENG-04 — Inject engineering fields into AI agent context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add engineering field block gated on `$cell_actor_type == "engineering"`
- Use same `$fv_temp` + paired `conditional` pattern (no `else`)
- 10 fields with engineering-specific labels

### US-ENG-05 — Table schema update (Xano AI prompt)
**Table:** `journey_lens.actor_type`
- Cannot edit `.xs` table files directly — use Xano AI agent
- Prompt: *"Update the `actor_type` enum column on the `journey_lens` table to add `engineering` as an allowable value. The full updated list should be: `["customer", "internal", "engineering", "operations", "ai_agent", "dev", "custom"]`"*
- Pull updated `tables/8_journey_lens.xs` after applying

---

## Fields Reference

| # | Key | Label |
|---|-----|-------|
| 1 | system_service_owner | System / Service Owner |
| 2 | data_inputs | Data Inputs |
| 3 | data_outputs | Data Outputs |
| 4 | api_integration_dependencies | API / Integration Dependencies |
| 5 | business_rules_logic | Business Rules / Logic |
| 6 | error_states_edge_cases | Error States / Edge Cases |
| 7 | data_storage_requirements | Data Storage Requirements |
| 8 | security_permissions | Security & Permissions |
| 9 | performance_requirements | Performance Requirements |
| 10 | audit_logging_needs | Audit / Logging Needs |
