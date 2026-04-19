## AI Agent Intelligence Epic

### Why This Exists

The journey map AI currently operates in a single mode: ask one question, get an answer, write one
cell, repeat. That works — but it misses two much more powerful behaviours that a world-class PM or
UX practitioner would bring naturally:

1. **Scope-aware building** — when a user says "build me a journey map for customer onboarding",
   a great PM doesn't ask a single clarifying question. They draft the whole thing — stages, roles,
   descriptions, pain points — in one pass, in the right order, and *then* refine. The AI should
   do the same at whatever scope the user requests: full map, a single stage column, a single lens
   row, or a single cell.

2. **Cascade / ripple awareness** — when a pain point changes, the cascade risk and escalation
   trigger cells that referenced it are now potentially stale. A great PM notices that and flags it.
   The AI never does this today. Every write is treated as isolated.

This epic adds both capabilities entirely through **agent prompt additions** in
`agents/2_journey_map_assistant.xs`. No new API endpoints, no schema changes, no frontend work.
All existing tools (`get_map_state`, `get_slice`, `batch_update`, `scaffold_structure`, etc.)
are already sufficient.

---

### Scope

- New `## Build Scope Detection` section added to the agent system prompt
- New `## Build Sequence Order` section added to the agent system prompt
- New `## Cascade Ripple Analysis` section added to the agent system prompt
- `## Interview mode rules` updated to reference build scope for map-level requests

### Explicit Non-Goals

- No new API endpoints or schema changes
- No frontend changes
- No change to the existing quality gate or override exception — those remain intact
- No automatic rewrites of confirmed cells — the AI surfaces findings and offers, never overwrites

---

### The Build Scope Model

The AI should detect intent at four levels and act accordingly:

| Scope | Example User Request | What the AI Does |
|---|---|---|
| **Map** | "Build me a journey map for customer onboarding" | `scaffold_structure` → actor identity → all cells in dependency order → consistency pass |
| **Stage** | "Flesh out the Activation stage" | `get_slice` stage → write all lens rows for that stage column |
| **Lens** | "Fill in all the pain points" | `get_slice` lens → write that lens row across all stages |
| **Cell** | "Write the pain point for checkout" | `update_cell` or `update_actor_cell_fields` for that one intersection |

At every scope: **build first, refine second.** The AI writes with best available information,
then asks the single most important clarifying question.

---

### The Lens Dependency Order

Lenses cannot be meaningfully populated in random order. Some depend on others existing first.
The correct order (used for map-level and stage-level builds):

```
1. description      ← what happens (baseline — everything depends on this)
2. customer/actor   ← who experiences it (depends on description)
3. owner            ← who is accountable (depends on description)
4. supporting       ← who else is involved (depends on owner)
5. painpoint        ← where it breaks (depends on description + customer)
6. variable         ← what to measure (you measure what hurts — depends on painpoint)
7. systems          ← what technology (depends on description)
8. risk             ← what breaks downstream (depends on painpoint being known)
9. trigger          ← when to escalate (depends on variable for the threshold)
10. notifications   ← what fires (depends on trigger + systems)
```

---

### The Cascade Dependency Map

When a structurally significant cell is written or changed, these are the downstream cells
that may now be inconsistent:

| Cell Changed | What Needs Checking |
|---|---|
| `painpoint` | `risk` cells referencing this pain; `variable` cells tracking it; `trigger` thresholds tied to it |
| `variable` | `trigger` cells (thresholds reference this metric); journey-level `success_metrics` |
| `description` | `customer` cell for same stage (experience should match what happens); `painpoint` for same stage |
| Actor identity (`update_actor_identity`) | `supporting` cells across all stages naming this actor; `notifications` recipients listing this actor |
| Stage added/removed | `risk` cells in adjacent stages (stage name references may now be invalid) |
| Lens row removed | `supporting` cells and `notifications` recipients that named this role |

---

## Stories

---

**US-JMAI-01 — Add Build Scope Detection to the agent system prompt**

**Story:** As the AI agent, I want to detect the intended build scope from a user's request so I
act at the right level — full map, stage, lens row, or cell — without asking the user to clarify
what they already told me.

**Acceptance Criteria:**
- A new `## Build Scope Detection` section is added to the agent system prompt in
  `agents/2_journey_map_assistant.xs`, immediately after `## Interview mode rules`
- The section instructs the agent to detect one of four scopes from the user's message:
  - **Map level:** "build me a journey map for...", "create a journey map for...", "generate the
    full map..." → execute full map build following the Build Sequence Order (US-JMAI-02)
  - **Stage level:** "flesh out [stage]", "fill in the [stage] column", "build the [stage] stage"
    → call `get_slice` on that stage, then write all lens rows for that column
  - **Lens level:** "fill in all the pain points", "populate the customer row", "add cascade risks
    across the map" → call `get_slice` on that lens, then write that row across all stages
  - **Cell level:** single-cell questions and requests → write that one cell
- For all scopes: build with best available information first, then ask the single most important
  clarifying question to refine
- The existing user override exception is fully honoured at all scopes — "just write it" always
  means write immediately with no scope-detection friction

**Layer:** Agent — `agents/2_journey_map_assistant.xs`

---

**US-JMAI-02 — Add Build Sequence Order to the agent system prompt**

**Story:** As the AI agent, I want a defined build sequence to follow when executing a map-level
or stage-level build so I populate cells in dependency order — descriptions before pain points,
pain points before cascade risks — producing a coherent first draft rather than a randomly-filled
grid.

**Acceptance Criteria:**
- A new `## Build Sequence Order` section is added to the agent system prompt, immediately after
  `## Build Scope Detection`
- The section defines five phases for map-level builds:

  **Phase 1 — Frame the Journey**
  Call `update_journey_settings` with: `journey_scope`, `primary_actor`, `start_point`,
  `end_point`, `success_metrics`. Infer values from the user's request. If the primary actor is
  ambiguous, ask one question to confirm before proceeding.

  **Phase 2 — Structure the Stages**
  Call `scaffold_structure` to create stages in logical sequence. Infer stage names from the
  domain (e.g. for "customer onboarding": Awareness → Sign-up → Activation → First Value →
  Habit Formation). Include all known lens rows with correct `actor_type`.

  **Phase 3 — Actor Identity**
  Call `update_actor_identity` for each actor lens row with `persona_description`,
  `primary_goal`, and `standing_constraints`. Infer from context.

  **Phase 4 — Populate Cells in Lens Dependency Order**
  Use `batch_update` to write full lens rows efficiently in this order:
  `description` → `customer/actor` → `owner` → `supporting` → `painpoint` → `variable` →
  `systems` → `risk` → `trigger` → `notifications`

  **Phase 5 — Cross-Lens Consistency Pass**
  Call `get_map_state` after all cells are written. Scan for: cascade risk cells that don't
  reference actual pain points found; escalation triggers without measurable thresholds;
  notification cells missing system or recipient. Surface inconsistencies as review suggestions —
  do NOT rewrite confirmed cells.

- For **stage-level** builds: execute Phase 4 only, for the requested stage column
- For **lens-level** builds: execute Phase 4 for the requested lens row only, across all stages
- The build sequence does not override the user override exception — "skip it" or "just fill it"
  always takes precedence over sequence rules

**Layer:** Agent — `agents/2_journey_map_assistant.xs`

---

**US-JMAI-03 — Add Cascade Ripple Analysis to the agent system prompt**

**Story:** As the AI agent, I want to recognise when a write affects other cells in the map so I
can surface a "things to review" note after structurally significant changes — behaving like a PM
who naturally notices downstream effects rather than treating every write as isolated.

**Acceptance Criteria:**
- A new `## Cascade Ripple Analysis` section is added to the agent system prompt, immediately
  before `## Output format`
- The section defines which cell types are "structurally significant" and what to check after
  each write:
  - `painpoint` written or changed → after writing, call `get_slice` on the same stage and check:
    `risk` cells for references to this pain, `variable` cells tracking it, `trigger` cells with
    thresholds tied to it
  - `variable` written or changed → check: `trigger` cells in same stage for threshold alignment,
    journey-level `success_metrics` for relevance
  - `description` written or changed → check: `customer` cell for same stage (does experience
    still match what happens?), `painpoint` cell for same stage (is friction still relevant?)
  - Actor identity changed via `update_actor_identity` → check: `supporting` cells across all
    stages naming this actor, `notifications` cells listing this actor as recipient
  - Stage added or removed via `mutate_structure` → check: `risk` cells in adjacent stages for
    now-invalid stage name references
  - Lens row removed via `mutate_structure` → check: `supporting` and `notifications` cells that
    referenced this role
- After identifying affected cells, the agent appends a single brief note to its reply:
  > "I also noticed [N] cells may need reviewing given this change — want me to update them?"
- The agent does NOT rewrite affected cells unprompted — it surfaces the finding and offers
- The agent NEVER rewrites confirmed cells regardless of cascade findings
- Ripple analysis is skipped if the user has explicitly said "just write it" / "skip it" in the
  same turn — do not add review noise to override-intent turns
- The ripple note counts toward the 60-word reply limit — keep it to one sentence

**Layer:** Agent — `agents/2_journey_map_assistant.xs`

---

**US-JMAI-04 — Update Interview Mode rules to reference build scope for map-level requests**

**Story:** As the AI agent, I want the Interview Mode rules updated to recognise when a user's
first message is a map-level build request so I switch into build mode rather than asking a single
interview question — giving the user a full draft map to react to instead of an empty grid with
one question pending.

**Acceptance Criteria:**
- The `## Interview mode rules` section in the agent system prompt is updated to add:
  > "If the user's first message is a map-level build request (detected per Build Scope Detection),
  > execute the Build Sequence Order immediately rather than asking a single interview question.
  > Return a brief confirmation once the build is complete, then ask the single most important
  > refinement question based on what was inferred."
- Existing interview rules (one question at a time, batch_update, actor identity capture) are
  unchanged for non-build-request turns
- The update is a single addendum to the existing section — not a rewrite

**Layer:** Agent — `agents/2_journey_map_assistant.xs`

---

### Recommended Build Order

All four stories touch only the agent system prompt. They can be written and tested sequentially
in one session:

```
US-JMAI-01 (scope detection) → US-JMAI-02 (build sequence) →
US-JMAI-03 (cascade ripple) → US-JMAI-04 (interview mode update)
```

Test each story by sending a representative prompt to the agent and verifying the behaviour
before moving to the next.

---

### Prompt Section Map (after all stories land)

The agent system prompt sections will be in this order:

```
## Context always available to you
## Your tools
## Core rules
## Actor type rules when adding lenses
## Structured actor field rules
## Actor identity rules
## Journey settings rules
## Interview mode rules          ← updated by US-JMAI-04
## Build Scope Detection         ← new (US-JMAI-01)
## Build Sequence Order          ← new (US-JMAI-02)
## Chat mode rules
## Interview probing strategies per lens type
## Dynamic context
## Answer quality gate
## Cascade Ripple Analysis       ← new (US-JMAI-03)
## Output format
```

---

### How This Relates to the Smart AI Chat Settings Epic

These are complementary but independent:

| | Smart AI Chat Settings | AI Agent Intelligence |
|---|---|---|
| **What it is** | User-facing dials that tune AI posture per session | Core agent reasoning capabilities |
| **Where it lives** | `smart_ai_settings` JSON column + PATCH endpoint + chat panel UI | Agent system prompt only |
| **Who configures it** | The user, per map | The product team, by shipping the prompt update |
| **Example** | "Use Deep Dive insight standard for this map" | "After writing a pain point, always scan for downstream cascade cells" |
| **Dependency** | Independent | Independent — ships first (no infrastructure needed) |
