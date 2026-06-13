# Publishing — Phase 2: Backend Gate Enforcement

**Problem this phase solves:** The gate constraints defined in Phase 1 are only on paper. The `publish_map` endpoint — both the MCP tool and the HTTP endpoint — currently does none of these checks. A call to publish succeeds regardless of map state. Phase 2 makes the gate structural: constraints are enforced server-side, failures return actionable errors, and the AI is instructed on how to handle rejections.

**Goal:** Implement all three gate check sets as server-side validation inside the publish flow. A failing gate returns a structured response — not a generic 422 — with the specific field, gate number, and fix instruction. The AI receiving a gate failure knows exactly what to fix and does not retry blindly.

**Dependency:** Phase 1 must be complete and agreed. Backend changes implement the contract Phase 1 specified.

**Exit condition for this phase:** `publish_map` rejects any map that fails Gate 1, 2, or 3. Every rejection returns a structured `gate_failures[]` array. AI agents and humans receive specific, fixable feedback — never a silent failure or a generic error.

---

## US-PUB-04 — Pre-Publish Validation in publish_map Endpoint

**What:** Add a validation pass at the start of the `publish_map` execution stack (both MCP tool `publish_map.xs` and HTTP endpoint `publish_POST.xs`) that runs all applicable gate checks before any state change occurs.

**Implementation logic:**
1. Load the journey map record
2. Run Gate 1 checks (universal) — collect any failures into `gate_failures[]`
3. If `map_level = atomic` → run Gate 2 checks, including calling `calculate_leakage` internally
4. If `intent = automation` → run Gate 3 checks
5. If `gate_failures` is non-empty → return structured error response, do NOT set status to active
6. If all gates pass → proceed with existing publish logic (snapshot compile, ai_summary, version increment)

**Failure response shape:**
```json
{
  "published": false,
  "journey_map_id": 162,
  "gate_failures": [
    {
      "gate": 1,
      "field": "map_level",
      "message": "map_level is required before publishing"
    },
    {
      "gate": 2,
      "field": "measurement_frequency",
      "message": "measurement_frequency must be set — how many times per year does this process run?"
    }
  ]
}
```

**Acceptance criteria:**
- `publish_map` returns `{ published: false, gate_failures: [...] }` on any gate failure
- No state change occurs (status stays `draft`) when gate fails
- Gate checks run in order — Gate 1 always runs, Gate 2/3 run only when applicable
- `calculate_leakage` is called as an internal check during Gate 2 — result is not returned to caller, only `incomplete_cells` is evaluated

---

## US-PUB-05 — Update publish_map MCP Tool Instructions

**What:** Update the MCP tool `instructions` field on `publish_map.xs` to describe the gate failure response shape and define how the AI must handle a rejection.

**AI behavior rules on gate failure (add to tool instructions):**
- On receiving `published: false` → do NOT retry the publish
- Read `gate_failures[]` and surface each failure to the user with its specific `message`
- For each gate failure, offer to fix the specific field — do not offer to "try publishing again"
- After fixing all failures, re-run the validation protocol (Phases 1–3 of Validation epic) before re-attempting publish
- Never interpret a gate failure as a transient error — it is always a data completeness issue

**Acceptance criteria:**
- MCP tool `instructions` field describes the gate_failures response shape
- AI agent receiving a gate failure surfaces each item individually to the user
- AI does not retry publish without first resolving the listed failures

---

## US-PUB-06 — Update publish_map.md Skills File

**What:** Update `emgram-skills/skills/publish_map.md` to document the publish gate — what it checks, what a failure looks like, and how the AI must respond.

**Sections to add:**
1. **"The Publish Gate"** — brief description of the three gate sets and when each applies
2. **"Gate Failure Response"** — the `gate_failures[]` schema with an example
3. **"AI Behavior on Gate Failure"** — explicit rules: surface each failure, offer to fix, do not retry blindly
4. **"When NOT to Publish"** — update existing section to include: validation report not clean, gate failures unresolved

**Acceptance criteria:**
- `publish_map.md` has a "Publish Gate" section with all three gate sets described
- Gate failure response schema is documented with a real example
- AI behavior on failure is defined as explicit rules — not left to inference
