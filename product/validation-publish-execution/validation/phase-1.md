# Validation — Phase 1: Validator Lens Standard

**Problem this phase solves:** There is no actor inside an atomic journey map whose job is to verify that a stage was completed correctly. The AI builds the map and also declares it done — the same agent checking its own work. This is structurally unreliable.

**Goal:** Introduce the Validator as a first-class actor on every L3 atomic map. Each Validator cell contains the acceptance criteria for its stage — specific, binary, independently verifiable conditions. The Validator lens is the Critic. It is populated at map-build time and read at execution time.

**Why this is Phase 1:** No backend changes required. Skills files + one map update. This is the fastest, highest-leverage fix available.

**Exit condition for this phase:** The `atomic-journey-map` (ID 163) has a Validator lens with populated cells on all 9 stages. Any AI reading the skills files knows the Validator lens is mandatory on atomic maps and knows how to populate it.

---

## US-VAL-01 — Add Validator Lens to atomic-journey-map (ID 163)

**What:** Add a `validator` lens row to the atomic-journey-map reference standard (the gold standard all atomic maps are measured against).

**For each stage (s1–s9), the Validator cell must contain:**
- A short list of binary acceptance criteria — each one independently testable (yes/no, not subjective)
- A required structured fields checklist:
  - `time_duration_value` set on primary actor cell
  - `stage_goal` (exit condition) set on the stage
  - `cost_rate_value > 0` on the primary actor lens (atomic maps only)
  - `actor_fields.metrics[]` has at least one entry
- Verification method declaration: `ai | human | both`

**Acceptance criteria:**
- Validator lens exists on all 9 stages of ID 163
- Every Validator cell has at least 2 binary acceptance criteria and the structured fields checklist
- No Validator cell is left with generic placeholder text

---

## US-VAL-02 — Document Validator Lens in intelligence_layer.md

**What:** Add a "Validator Lens" section to `emgram-skills/skills/intelligence_layer.md` so any AI reading the skills files knows what it is, when it is required, and how to write it.

**The section must define:**
- What the Validator lens is: a Critic actor whose output is verification, not work product
- When it is required: mandatory on all `map_level = atomic` maps, optional on L1/L2
- What each Validator cell must contain (same spec as US-VAL-01)
- The rule: the AI that builds the map cannot also be the only validator — Validator cells must be written as objective criteria a separate agent or human can check
- The rule: Validator cells are written at build time, read at execution time — they are the acceptance test, not a summary

**Acceptance criteria:**
- Section exists in `intelligence_layer.md` under a clearly labeled heading
- The rule "Validator lens is mandatory on atomic maps" appears as a HARD RULE
- Any AI reading the file can populate a Validator cell without additional instruction

---

## US-VAL-03 — Scaffold Rule Update for Atomic Maps

**What:** Update the scaffold defaults so any AI building an atomic map automatically includes the Validator lens — it is not an optional add-on.

**Changes required:**
- `emgram-skills/instructions.md` scaffold rules table: add `validator` to the default lens list when `map_level = atomic`
- When the AI scaffolds a new atomic map, Validator lens is created alongside AI Agent, Handoff, Engineering, and Metrics
- After scaffold, the AI must populate Validator cells before the map is considered build-complete — not after

**Acceptance criteria:**
- Scaffold rules table in `instructions.md` includes Validator for atomic maps
- AI never delivers an atomic map draft without a Validator lens present
- Validator cells are populated during the build pass, not deferred
