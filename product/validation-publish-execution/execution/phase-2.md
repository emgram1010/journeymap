# Execution — Phase 2: Three-Gate Execution Protocol

**Problem this phase solves:** There is currently no protocol that controls when an AI is allowed to start a map, advance between stages, or declare an execution complete. The agent starts, runs stages in sequence, and finishes — with no formal checkpoints. A stage with a missing Validator cell looks identical to a correctly validated stage. An execution with blocked stages can still be marked `completed`. Nothing enforces the order or the verification.

**Goal:** Implement Sign In → Time Out → Sign Out as mandatory, hard-stop checkpoints in every map execution. Each gate is a formal verification pass — not a guideline. If a gate fails, execution does not advance. The AI has explicit, structured instructions for what to check at each gate, what to do on pass, and what to do on fail.

**Dependency:** Phase 1 must be complete. Gates write to `per_stage_log` and `gate_sign_in_passed_at` / `gate_sign_out_passed_at` fields established in Phase 1.

**Exit condition for this phase:** An AI agent executing any published atomic map runs all three gates. Gate failures halt execution with a specific reason. Execution records show gate timestamps. No execution is marked `completed` without a passing Sign Out gate.

---

## US-EXE-04 — Gate 1: Sign In (Before Any Stage Executes)

**What:** Before the AI executes any stage, it runs a pre-execution verification pass. If any check fails, the execution does not start. The `workflow_execution` record is created but stays in `pending` status until Sign In passes.

**Sign In checklist — AI must verify all of the following:**
| Check | Pass condition | Fail action |
|---|---|---|
| Map is published | `journey_map.status = active` and `automation_snapshot` exists | Stop — "Map has not been published. Cannot execute an uncertified map." |
| Map level set | `map_level` is not null | Stop — "map_level is not set on this map." |
| Snapshot pinned | `map_version` recorded on the execution record | Stop — pin snapshot version, retry |
| Primary actor identified | At least one lens has `persona_description` set | Stop — "Primary actor identity not defined. Cannot execute." |
| Cost rate set (atomic) | Primary actor `cost_rate_value > 0` | Stop — "Primary actor cost_rate not set. Leakage math will produce zero." |
| Validator lens exists (atomic) | Validator lens present with content | Stop — "Validator lens missing or empty. Cannot verify stage outputs." |

**On Sign In pass:**
- Write `gate_sign_in_passed_at: now` to `workflow_execution`
- Set `status = running`
- Begin stage 1 execution

**Acceptance criteria:**
- AI has explicit Sign In instruction in skills files — not implied
- Execution cannot reach `status = running` without `gate_sign_in_passed_at` being set
- Each Sign In failure produces a specific stop message — not a generic failure

---

## US-EXE-05 — Gate 2: Time Out (At Each Stage Boundary)

**What:** After completing a stage and before advancing to the next, the AI runs a verification pass against the Validator cell for the current stage. This is the per-stage compliance checkpoint — it runs N times (once per stage) across the execution.

**Time Out sequence — runs after every stage:**
1. Call `get_slice { journey_map_id, stage_key: current, lens_key: "validator" }` from the pinned snapshot
2. Read each acceptance criterion in the Validator cell
3. For each criterion, evaluate the primary actor output — binary: passes or fails
4. **If all criteria pass:**
   - Write stage entry `{ status: "complete", validation_passed: true, validated_by: "ai" }` to `per_stage_log`
   - Advance to next stage
5. **If any criterion fails:**
   - Write stage entry `{ status: "blocked", validation_passed: false, skip_reason: "[exact criterion text]" }` to `per_stage_log`
   - Halt — do not advance to next stage
   - Surface the blocked stage and the failing criterion to the human or orchestrator

**Rules:**
- Time Out runs for every stage — it cannot be skipped even on the last stage
- The AI evaluates criteria against the actual stage output — not against its intent or plan
- Criteria are evaluated as-stated in the Validator cell — the AI cannot reinterpret them charitably
- A blocked stage does not fail the entire execution — it halts at that stage and waits for resolution

**Acceptance criteria:**
- `per_stage_log` has an entry for every stage the AI attempts — no silent skips
- Blocked stages have `skip_reason` set to the exact failing criterion text
- AI cannot advance past a blocked stage without explicit user or orchestrator resolution

---

## US-EXE-06 — Gate 3: Sign Out (After All Stages Complete or Halt)

**What:** After the last stage is attempted (whether complete or blocked), the AI runs a final verification pass before closing the execution record. Sign Out confirms the execution is in a valid terminal state — not just that the loop ended.

**Sign Out checklist:**
| Check | Pass condition | Fail action |
|---|---|---|
| All stages logged | `per_stage_log` has one entry per stage in the map | Flag missing stages — cannot close without a record for every stage |
| No null statuses | Every `per_stage_log` entry has a non-null `status` | Flag the specific stage with null status |
| Leakage math clean (atomic) | `calculate_leakage` returns `incomplete_cells = []` | Warn — execution can still close, but leakage output is flagged as incomplete |
| Novel exceptions documented | All `novel_exception_flag: true` entries have a `novel_exception_description` | Reject close — exceptions must be described before record closes |

**On Sign Out pass:**
- Write `gate_sign_out_passed_at: now` to `workflow_execution`
- Set `status = completed`
- Surface Sign Out summary to user: total stages, complete count, blocked count, novel exceptions, and the 3yr cost-of-inaction number (atomic maps)

**On Sign Out fail:**
- Set `status = failed` with `failure_reason` citing the specific failed check
- Do NOT set `gate_sign_out_passed_at`
- Surface the specific failure to the user with fix instruction

**Acceptance criteria:**
- `workflow_execution.status = completed` requires `gate_sign_out_passed_at` to be set
- Sign Out summary is surfaced to user after every execution — not only on failure
- Novel exceptions without descriptions block the Sign Out close
