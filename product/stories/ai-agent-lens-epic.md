# Epic: AI Agent Lens Template

**Goal:** Add a fully functional `ai_agent` lens type representing any AI model or agent role in a journey map. Supports 12 structured cell fields covering model identity, data flows, decisions, confidence, escalation, training, bias, failures, performance, ownership, and explainability.

---

## Stories

### US-AIL-01 — Add `AiAgentActorFields` to types.ts
**File:** `webapp/protype-2/src/types.ts`
- `ai_agent` already exists in `ActorType` union — no change needed there
- Add `AiAgentActorFields` interface with 12 keys
- Update `ActorFields` union to include `AiAgentActorFields`

### US-AIL-02 — Add ai_agent template to constants.ts
**File:** `webapp/protype-2/src/constants.ts`
- Replace the `ai_agent` comingSoon entry with full `ai-agent-v1` template
- 12 `CellFieldDef` entries with keys, labels, and placeholders
- Matching `cellFieldScaffold` with all 12 keys set to `null`
- Cell Detail Panel and badge rendering already data-driven — no App.tsx changes needed

### US-AIL-03 — Add ai_agent scaffold to add-lens API
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- `ai_agent` already in the enum — scaffold block only
- Add 12-key scaffold block under `if actor_type == "ai_agent"`

### US-AIL-04 — Inject ai_agent fields into AI agent context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add ai_agent field block gated on `$cell_actor_type == "ai_agent"`
- Use same `$fv_temp` + paired `conditional` pattern (no `else`)
- 12 fields with AI-specific labels

> **No table schema change needed** — `ai_agent` is already in `journey_lens.actor_type` enum.

---

## Fields Reference

| # | Key | Label |
|---|-----|-------|
| 1 | ai_model_agent | AI Model / Agent |
| 2 | input_data | Input Data |
| 3 | decision_output | Decision / Output |
| 4 | confidence_threshold | Confidence Threshold |
| 5 | escalation_logic | Escalation Logic |
| 6 | training_data | Training Data |
| 7 | retraining_frequency | Retraining Frequency |
| 8 | bias_fairness_considerations | Bias & Fairness Considerations |
| 9 | failure_scenarios | Failure Scenarios |
| 10 | performance_metrics | Performance Metrics |
| 11 | model_owner | Model Owner |
| 12 | explainability_needs | Explainability Needs |
