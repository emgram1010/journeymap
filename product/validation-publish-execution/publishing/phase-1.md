# Publishing — Phase 1: Define the Publish Gate Constraints

**Problem this phase solves:** "Published" currently means nothing. Any map — regardless of completeness, `map_level`, leakage readiness, or structural integrity — can be set to `status = active`. There is no gate. A broken map and a fully certified map look identical once published. This phase defines what the gate must check before it can be built.

**Goal:** Produce a complete specification of the hard constraints that every map must satisfy before it can transition from draft to active. Constraints are organized by map type: universal (all maps), atomic (L3), and automation. No backend changes in this phase — this is the contract that Phase 2 implements.

**Why this is Phase 1:** You cannot enforce a gate until the gate's conditions are fully specified. Getting the contract wrong here means implementing the wrong checks in Phase 2. This phase is the design work.

**Exit condition for this phase:** All three gate constraint sets are documented, reviewed, and agreed. `publish_map.md` is updated with the gate specification. Any AI or engineer reading the skills files knows exactly what a map must satisfy before publish.

---

## US-PUB-01 — Gate 1: Universal Map Identity Constraints

**What:** Define the minimum identity requirements every map must satisfy before publish, regardless of map level or intent.

**Gate 1 constraints — all maps:**
| Field | Requirement | Failure message |
|---|---|---|
| `map_level` | Must be set (not null) | "map_level is required before publishing" |
| `intent` | Must be `sop`, `automation`, or `hybrid` | "intent must be set before publishing" |
| `title` | Must not be a default placeholder or empty | "Map title must be customized before publishing" |
| `stage_goal` | At least one stage must have a stage_goal defined | "At least one stage must have an exit condition defined" |
| `persona_description` | At least one actor lens must have persona_description set | "At least one actor lens must have a persona defined" |

**Rules:**
- All five must pass — no partial publish
- Failure returns the specific field name and the fix instruction, not a generic error
- These constraints apply equally to AI-initiated and human-initiated publishes

**Acceptance criteria:**
- Gate 1 constraints documented in this file and mirrored in `publish_map.md`
- Each constraint has a specific, actionable failure message defined
- No ambiguity about what "passes" vs "fails" each check

---

## US-PUB-02 — Gate 2: Atomic Map Constraints (map_level = atomic)

**What:** Define additional constraints that apply only to L3 atomic maps. These enforce the leakage math readiness requirements — without them, the map cannot produce the core intelligence output it was built for.

**Gate 2 constraints — atomic maps only:**
| Field | Requirement | Failure message |
|---|---|---|
| `measurement_frequency` | Must be > 0 | "measurement_frequency must be set — how many times per year does this process run?" |
| `measurement_period_label` | Must be set | "measurement_period_label must be set (e.g. 'per job', 'per shift')" |
| Primary actor `cost_rate_value` | Must be > 0 | "Primary actor lens must have cost_rate_value set before publishing" |
| `calculate_leakage` result | `incomplete_cells` must be empty | "Leakage math is incomplete — [N] cells missing time_duration" |
| Validator lens | Must exist and all cells must be populated | "Validator lens is missing or has empty cells" |

**Rules:**
- Gate 2 runs only after Gate 1 passes
- `calculate_leakage` is called as part of the gate check — not assumed
- If Validator lens was added in Phase 1 of Validation epic, this gate enforces its presence

**Acceptance criteria:**
- Gate 2 constraints documented with specific failure messages per field
- `calculate_leakage` is a required gate step — not optional — for atomic maps
- Validator lens presence is a hard requirement before atomic map can publish

---

## US-PUB-03 — Gate 3: Automation Map Constraints (intent = automation)

**What:** Define additional constraints for maps with `intent = automation`. These enforce structural completeness for maps that will trigger external systems (n8n, Make, webhooks).

**Gate 3 constraints — automation intent maps only:**
| Check | Requirement | Failure message |
|---|---|---|
| Handoff cells | No empty handoff lens cells | "Handoff cells are empty — automation triggers cannot be defined without handoff content" |
| AI Agent lens | All ai_agent lenses have `agent_map_id` set OR flagged `human-in-loop` | "AI Agent lens [lens_key] has no agent_map_id and is not flagged as human-in-loop" |
| Automation connection | At least one `automation_connection` registered OR user explicitly acknowledges no webhook | "No automation connection registered — confirm this map will not trigger external systems" |

**Rules:**
- Gate 3 runs only after Gate 1 passes (Gate 2 does not apply to automation maps unless also atomic)
- The "user explicitly acknowledges" path requires an active confirmation — not silence
- Maps with `intent = hybrid` run both Gate 2 (if atomic) and Gate 3

**Acceptance criteria:**
- Gate 3 constraints documented with specific failure messages
- Hybrid maps run the applicable subset of both Gate 2 and Gate 3
- The "explicit acknowledgment" path for missing webhooks is defined — it is not a bypass
