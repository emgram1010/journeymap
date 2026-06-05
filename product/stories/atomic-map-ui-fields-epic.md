# Atomic Map UI Fields — Epic

**Status:** Ready for Development
**Goal:** Expose the Intelligence Layer Ring 2 fields in the frontend so humans can
build L3 Atomic maps manually — without relying solely on the AI assistant to populate
cost rate, time duration, and measurement fields.

---

## Why This Exists

The DB and Xano APIs already support all L3 leakage fields (`cost_rate_value`,
`time_duration_value`, `measurement_frequency`, etc.). The AI can write them via MCP
tools. But a human editing a map in the UI currently has no way to set these values
directly — the fields are invisible in every form and panel.

This epic adds UI controls for the three missing surfaces:
1. Actor Setup Wizard → cost rate
2. Stage Edit Panel → time on task
3. Map Settings sidebar → measurement frequency + period label

---

## Scope

**In scope:**
- Actor lens: `cost_rate_value` + `cost_rate_unit`
- Cell/stage: `time_duration_value` + `time_duration_unit`
- Map settings: `measurement_frequency` + `measurement_period_label`
- `xano.ts` type updates to carry the new fields through the frontend layer

**Out of scope:**
- `planned_duration` / `actual_duration` gap tracking (future epic)
- `actor_fields.metrics[]` leakage flag UI (future epic)
- Leakage calculation display (covered in leakage-analysis-epic.md)

---

## User Stories

### US-ATM-01 — Actor cost rate in Actor Setup Wizard
**Surface:** `ActorSetupWizard.tsx`
**Trigger:** User adds or edits an actor lens on any map

**Fields to add:**
- `cost_rate_value` — decimal number input
- `cost_rate_unit` — dropdown: `per_minute | per_hour | per_day | per_week | per_event`

**Only shown when** `map_level === 'atomic'` OR the actor type is not `customer`
(cost rate is irrelevant on pure customer actor lenses).

**API target:** `PATCH /journey_lens/{id}` (raw patch — NOT the actor_fields endpoint,
which has an allowlist that excludes cost_rate fields).

**Acceptance Criteria:**
- Cost rate fields appear in wizard when editing an internal/operations/handoff actor
- Values are persisted to `journey_lens.cost_rate_value` and `cost_rate_unit`
- Unit dropdown defaults to `per_hour`
- Empty value is allowed (field is optional)
- `XanoJourneyLens` type in `xano.ts` includes `cost_rate_value` and `cost_rate_unit`

---

### US-ATM-02 — Time on task in Stage Edit Panel
**Surface:** `StageEditPanel.tsx`
**Trigger:** User clicks to edit any stage on an L3 Atomic map

**Fields to add:**
- `time_duration_value` — decimal number input (e.g. 15)
- `time_duration_unit` — dropdown: `minutes | hours | days | weeks`

**Note:** `time_duration_value` lives on the **cell** (actor × stage intersection),
not on the stage itself. The stage panel should write to the cell belonging to the
`primary_actor_lens` for that stage. If no primary actor is set, show a hint to
set one first.

**API target:** `PATCH /journey_cell/update/{journey_cell_id}`

**Acceptance Criteria:**
- Time duration fields appear in stage panel when `map_level === 'atomic'`
- Saves to the primary actor's cell for that stage
- Unit dropdown defaults to `minutes`
- Displays existing value when panel opens
- `XanoJourneyCell` type in `xano.ts` already includes these fields ✅

---

### US-ATM-03 — Measurement fields in Map Settings panel
**Surface:** `App.tsx` Journey Settings sidebar
**Trigger:** User opens the settings panel on any map

**Fields to add:**
- `measurement_frequency` — integer input with helper text
  (e.g. "How many times per year does this process run? e.g. 15924")
- `measurement_period_label` — short text input
  (e.g. "per job", "per shift", "per inquiry")

**Only shown when** `map_level === 'atomic'` to keep the panel clean for L1/L2 maps.

**API target:** `PATCH /journey_map/settings/{journey_map_id}` (already accepts both fields)

**Acceptance Criteria:**
- Fields appear in settings panel only when `map_level === 'atomic'`
- Integer validation on `measurement_frequency` (no decimals, min 1)
- Both fields saved via existing `saveJourneySettings` call
- `JourneySettings` interface in `xano.ts` extended with both fields

---

### US-ATM-04 — xano.ts type coverage
**Surface:** `xano.ts`

**Changes needed:**
- `JourneySettings` interface: add `measurement_frequency?: number | null` and
  `measurement_period_label?: string | null`
- `XanoJourneyLens` interface: add `cost_rate_value?: number | null` and
  `cost_rate_unit?: string | null`
- `ActorWizardInput` (in `ActorSetupWizard.tsx`): add `costRateValue` and `costRateUnit`
- `saveJourneySettings` body: already passes `settings as Record<string, unknown>` ✅

**Acceptance Criteria:**
- No TypeScript errors after type additions
- `XanoJourneyLens` carries cost rate fields through `loadJourneyMapBundle` response

---

## Build Order

```
US-ATM-04   xano.ts type updates          (foundation — do first)
US-ATM-01   Actor Wizard cost rate        (depends on US-ATM-04)
US-ATM-02   Stage Panel time duration     (depends on US-ATM-04)
US-ATM-03   Map Settings measurement      (depends on US-ATM-04)
```

---

## Relationship to Other Epics

| Epic | Dependency |
|---|---|
| leakage-analysis-epic.md | These fields are the inputs to leakage math |
| journey-map-level-architecture-epic.md | `map_level` field gates field visibility |
| intelligence-layer-epic.md | AI already writes these via MCP — this adds human parity |
