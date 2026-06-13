# Validation — Phase 2: Two-Pass Validation Protocol

**Problem this phase solves:** The current `get_gaps` check only catches missing text content. Structured fields required for leakage math — `time_duration`, `cost_rate`, `map_level`, `measurement_frequency` — are invisible to `get_gaps`. An AI can pass all content checks and still produce zero leakage output. There is no enforced sequence for declaring a map build-complete.

**Goal:** Define and enforce a mandatory two-pass (plus Validator check) sequence that every AI must run before a map is considered complete. Pass 1 catches content gaps. Pass 2 catches structured field gaps. Pass 3 checks output against Validator acceptance criteria. All three must pass.

**Dependency:** Phase 1 must be complete. Pass 3 requires Validator cells to exist and be populated.

**Exit condition for this phase:** No AI agent can mark an atomic map "complete" without running and passing all three checks. The sequence is documented as a HARD RULE in the skills files.

---

## US-VAL-04 — Two-Pass Validation Rule in instructions.md

**What:** Add a HARD RULE block to `emgram-skills/instructions.md` that defines the mandatory completion sequence for atomic maps.

**The rule block must specify:**

```
ATOMIC MAP COMPLETION PROTOCOL — HARD RULE
After fill_cells, before signaling completion or offering to publish:

Pass 1 — Content Check
  get_gaps { journey_map_id }
  → gaps must = 0
  → if gaps > 0: fill them, then re-run Pass 1

Pass 2 — Leakage Field Check
  calculate_leakage { journey_map_id }
  → incomplete_cells must = []
  → if incomplete_cells not empty: fix each missing field, then re-run Pass 2

Pass 3 — Validator Acceptance Check (see US-VAL-05)
  → read Validator cell for each stage
  → confirm primary actor output satisfies each criterion
  → if any criterion unmet: flag stage as blocked, cite specific criterion

Only after all three passes return clean may the AI present the map as complete.
```

**Acceptance criteria:**
- HARD RULE block exists in `instructions.md` with the three-pass sequence
- Rule is positioned at the same priority level as "always search before create"
- AI running this skill file cannot skip the protocol without violating a stated rule

---

## US-VAL-05 — Validator Acceptance Check (Pass 3)

**What:** Define how the AI executes Pass 3 — the Validator lens check — as a structured verification step, not a subjective review.

**Execution sequence for Pass 3:**
1. For each stage (s1 through s{n}), call `get_slice { journey_map_id, stage_key, lens_key: "validator" }`
2. Read each acceptance criterion in the Validator cell
3. For each criterion, evaluate the primary actor cell output against it — binary: passes or fails
4. If all criteria pass → stage is `complete`
5. If any criterion fails → stage is `blocked`; AI must cite the exact criterion text in the block reason
6. AI cannot soften a failing criterion by rephrasing it as passing

**Acceptance criteria:**
- AI reads each Validator cell individually — not the whole map at once
- Each failing criterion is cited verbatim in the blocked stage report
- AI cannot mark a stage complete if Pass 3 has not been run for that stage

---

## US-VAL-06 — Map-Level Pre-Flight Check

**What:** Before the AI starts any build or update session on an atomic map, it runs a pre-flight check on map-level required fields. If any pre-flight fails, the AI surfaces the specific gap and stops — it does not build on a broken foundation.

**Pre-flight checks (run at session start before any fill_cells call):**
- `map_level` is set and not null → if null: stop, surface: "map_level must be set before building"
- `intent` is set (`sop | automation | hybrid`) → if null: ask user, do not assume
- `measurement_frequency > 0` (atomic maps only) → if 0 or null: stop, surface the gap
- `measurement_period_label` is set → if null: ask user for the cadence label
- Primary actor lens identified and has `cost_rate_value > 0` (atomic maps only) → if missing: stop

**Acceptance criteria:**
- Pre-flight check is defined in `intelligence_layer.md` as a required step before build
- AI never fills cells on an atomic map with a null `map_level`
- Any pre-flight failure surfaces the specific field name and what value it needs — not a generic error
