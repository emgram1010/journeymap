# Journey Map Level Architecture — Epic PRD

**Status:** Planning
**Goal:** Enable AI agents to interview any user (regardless of experience), prescribe
the correct map level (L1/L2/L3), build it with the right fields at the right depth,
and produce a map that both AI agents and humans can read as operational context.

---

## Why This Exists

Green users don't know what an L3 is. They say "map out how Jesse handles inquiries."
The AI has to be smart enough to hear that, run a silent prescription check, determine
it's an L3 Atomic Stage Map, and start collecting Ring 2 fields — without ever saying
"what map level do you want?"

Two prong goal:
1. **Interview prong** — guide the user to surface the right domain, actor, and depth
2. **Build prong** — produce a map with enough structured context that both AI agents
   and humans can use it for process visibility, cost analysis, and operational handoff

---

## The Three Map Levels

| Level | Name | Purpose | Leakage Math? | Primary Output |
|---|---|---|---|---|
| L1 | Architecture Map | Domain overview — what businesses/processes exist | ❌ No | Executive context |
| L2 | Actor Journey Map | One actor's end-to-end process | ⚠️ Partial | Capacity + process visibility |
| L3 | Atomic Stage Map | One actor, one discrete task — metric-ready | ✅ Yes | 3-year cost-of-inaction |

**Navigation rule:** L1 links → L2 via `sub_journey`. L2 links → L3 via `sub_journey`.
**One schema. One map type. Tagged via `map_level` field.**

---

## Field Requirements by Level

### L1 — Minimum Required Fields
| Layer | Fields |
|---|---|
| Map settings | `title`, `journey_scope`, `primary_actor`, `map_level="architecture"` |
| Stages | Label only |
| Lenses | Description lens — narrative only |
| Links | `sub_journey` → L2 maps |

### L2 — Minimum Required Fields
| Layer | Fields |
|---|---|
| Map settings | L1 fields + `key_stakeholders`, `start_point`, `end_point`, `duration` |
| Stages | Label + `stage_goal` (exit condition) |
| Actor identity | `persona_description`, `primary_goal`, `standing_constraints`, `cost_rate_value` + unit |
| Cells | `time_duration_value` + unit, `actor_fields` (emotions, friction, task_objective) |
| Links | `sub_journey` → L3 maps |

### L3 — Full Field Set (leakage-ready)
| Layer | Fields | Required for math? |
|---|---|---|
| Map settings | L2 fields + `map_level="atomic"`, `parent_map_id` | navigation |
| | `measurement_frequency`, `measurement_period_label` | ✅ annual compounding |
| | `average_deal_value`, `miss_rate`, `conversion_rate` | ✅ revenue at risk |
| Stages | `stage_goal` (exit condition), `primary_actor_lens` | ✅ leakage signal |
| Actor identity | `persona_description`, `primary_goal`, `standing_constraints` | AI + human context |
| | `cost_rate_value` + `cost_rate_unit` | ✅ per-stage cost |
| Cells | `time_duration_value` + `time_duration_unit` | ✅ time-on-task |
| | `planned_duration`, `actual_duration` | ✅ gap = leakage |
| | `actor_fields.metrics[]` with `flag: "leakage"` | ✅ waste signal |
| Links | `exception` → exception handling maps | recovery path |

---

## Priority Stack

```
🔴 CRITICAL  Epic-JMA-1  Level Prescription Interview (AI-led)
🔴 CRITICAL  Epic-JMA-2  L3 Field Collection Protocol + Guard Rails
🟡 HIGH      Epic-JMA-3  L1 and L2 Build Protocols
🟡 HIGH      Epic-JMA-4  Map Level Navigation (L1→L2→L3 linking)
🟢 MEDIUM    Epic-JMA-5  AI Context Layer (ai_summary per level)
🟢 MEDIUM    Epic-JMA-6  Leakage-Ready Validation Gate
```

---

## Epic JMA-1 — Level Prescription Interview
**The AI must determine the right map level before building anything.**

### Context
Green users describe their domain in plain language. The AI listens, asks targeted
questions, and silently prescribes L1/L2/L3. It never asks "what map level do you want?"
It asks about scope, actor specificity, and insight goal — then builds accordingly.

### US-JMA-01-01 — Domain identification question
**Agent:** Journey Map Assistant
**Trigger:** Any map build request or [GREET] on empty map
**Script:**
> "What type of business or operation are we mapping? What's the main thing it tries to deliver?"
**AI writes:** `journey_scope` + infers domain tags for `ai_summary`

### US-JMA-01-02 — Primary actor identification question
**Script:**
> "Who is the person or system that does the actual work we want to understand?"
**AI writes:** `primary_actor`
**Branch:** if multiple actors named → prescribe L1 first, then L2/L3 per actor

### US-JMA-01-03 — Scope check (L1 vs L2/L3 gate)
**Script:**
> "Are you trying to understand the overall business flow, or one specific person's process?"
**Branch:**
- Overall flow → prescribe L1, set `map_level="architecture"`
- Specific actor → continue to granularity check

### US-JMA-01-04 — Granularity check (L2 vs L3 gate)
**Script:**
> "Do you want to see what [actor] does across their whole day, or zoom into one specific task they perform?"
**Branch:**
- Whole shift / end-to-end → prescribe L2, set `map_level="actor-journey"`
- One specific task → prescribe L3, set `map_level="atomic"`

### US-JMA-01-05 — Insight goal check (override to L3)
**Script:**
> "Do you need to find where time or money is being lost, or is this more for documentation?"
**Branch:**
- Leakage / cost → force L3 regardless of prior answers
- Documentation → L1 or L2 is sufficient

**Acceptance Criteria — Epic JMA-1:**
- AI never asks "what map level do you want?"
- `map_level` is always set before the first stage is created
- Multi-actor domains default to L1 prescription with L2/L3 drill-down offer
- Prescription happens within 3 questions maximum

---

## Epic JMA-2 — L3 Field Collection Protocol + Guard Rails
**L3 is the only level that produces the 3-year number. It requires the full field set.**

### Context
Once L3 is prescribed, the AI shifts into structured data collection mode. For each stage,
it must run the 5 Guard Rail Tests silently and collect all Ring 2 fields through conversation
before declaring a stage metric-ready.

### US-JMA-02-01 — Collect map-level measurement fields
**Trigger:** L3 prescribed — before stage collection begins
**AI asks (one at a time):**
1. > "How many times per year does this process run? (e.g. 1,040 inquiries/year, 15,924 jobs/year)"
   → writes `measurement_frequency`
2. > "What's a good label for one instance? (e.g. 'per job', 'per inquiry', 'per shift')"
   → writes `measurement_period_label`
3. > "What's the average value of one successful outcome? (e.g. $350 per booking)"
   → writes `average_deal_value`
4. > "What percentage of those go unanswered or mishandled?"
   → writes `miss_rate`

### US-JMA-02-02 — Collect actor cost rate
**Trigger:** first actor lens created on L3 map
**AI asks:**
> "What does [actor]'s time cost? (e.g. $30/hour, $5/job)"
→ writes `cost_rate_value` + `cost_rate_unit` via `update_actor_identity`

### US-JMA-02-03 — Collect time-on-task per stage
**Trigger:** each stage in L3 phase 4 interview
**AI asks:**
> "How long does [actor] actually spend on '[stage name]' in the real world?"
→ writes `time_duration_value` + `time_duration_unit` via `update_cell`
**Also asks:**
> "How long should it take ideally?"
→ writes `planned_duration`

### US-JMA-02-04 — 5 Guard Rail Tests (silent — run before each stage is accepted)
**Trigger:** user describes a stage during L3 build
**Tests run in order:**

| Test | Check | Fail action |
|---|---|---|
| Single Actor | Is there ONE owner for this stage's output? | Split stage or link sub-journey |
| Time-on-Site | Can user give a real-world time for this step? | Stage too vague — ask to narrow |
| Completion Signal | What tells you this step is done? | Set `stage_goal` — don't proceed without it |
| Exception | What happens when this goes wrong? | Flag for exception map — link later |
| Isolation | Can this step produce a result on its own? | Needs sub-journey — create and link |

**AI behaviour:** if any test fails, ask ONE targeted question to resolve it before writing the stage.

### US-JMA-02-05 — Leakage metric capture per stage
**Trigger:** after time-on-task collected for a stage
**AI asks:**
> "What's the main thing that goes wrong here — what's the waste signal?"
→ writes to `actor_fields.metrics[]` with `flag: "leakage"`

**Acceptance Criteria — Epic JMA-2:**
- All map-level Ring 2 fields collected before stage fill begins
- Every L3 stage passes all 5 Guard Rail Tests before being written
- `planned_duration` + `actual_duration` captured for every stage
- At least one leakage metric per stage on L3 maps

---

## Epic JMA-3 — L1 and L2 Build Protocols
**Lighter build flows for documentation and capacity analysis maps.**

### US-JMA-03-01 — L1 build protocol
**Trigger:** `map_level="architecture"` prescribed
**AI collects:** domain description, top-level processes (become stages), actors involved (become lenses)
**AI does NOT collect:** measurement fields, cost rates, time durations
**AI writes:** description cells only — narrative context per stage
**Links:** offers to create L2 drill-down for each major actor identified

### US-JMA-03-02 — L2 build protocol
**Trigger:** `map_level="actor-journey"` prescribed
**AI collects:** actor identity (persona, goal, constraints), stage sequence, cost rate
**AI collects per stage:** time duration, actor experience (emotions, friction), pain points
**AI does NOT collect:** measurement_frequency, miss_rate, planned vs actual
**Links:** offers to create L3 for any stage where "I want to measure this more closely"

**Acceptance Criteria — Epic JMA-3:**
- L1 never prompts for cost or time fields
- L2 collects cost_rate but not measurement_frequency
- Both levels offer drill-down links to deeper maps at end of build

---

## Epic JMA-4 — Map Level Navigation
**L1 → L2 → L3 must be linked so AI and humans can traverse the hierarchy.**

### US-JMA-04-01 — Auto-link L3 to parent L2 on creation
**Trigger:** L3 map created with `parent_map_id` set
**AI action:** call `link_map` with type `sub_journey` from the L2 stage cell → L3 map
**Guard:** verify `parent_map_id` exists and is `map_level="actor-journey"` before linking

### US-JMA-04-02 — Offer to create L2 from L1 stage
**Trigger:** L1 build complete
**AI prompt:** "Want me to build a detailed actor journey for [top actor]? I'll link it here."
**Action:** creates L2 map, sets `parent_map_id` = L1 map id, calls `link_map` sub_journey

### US-JMA-04-03 — Offer to create L3 from L2 stage
**Trigger:** L2 build complete OR user says "zoom into [stage]"
**AI prompt:** "Want to measure the cost and leakage at '[stage name]'? That needs an atomic map."
**Action:** creates L3 map, sets `parent_map_id` = L2 map id, calls `link_map` sub_journey

**Acceptance Criteria — Epic JMA-4:**
- Every L3 map has `parent_map_id` set and a `sub_journey` link from parent L2 stage
- AI offers drill-down at end of every L1 and L2 build
- Navigation is traversable: given an L3 map, AI can read parent L2 and L1 for full context

---

## Epic JMA-5 — AI Context Layer
**Every map must be readable by a future AI without scanning cells.**

### US-JMA-05-01 — ai_summary includes map_level context
**Trigger:** publish
**Format addition (L3):**
```
Level: L3 — Atomic Stage Map
Actor: [primary_actor]
Measurement: [measurement_frequency] [measurement_period_label]
Cost rate: [cost_rate_value] [cost_rate_unit]
Leakage stages: [comma-separated stage labels with leakage metrics]
```

### US-JMA-05-02 — AI reads map_level before every build operation
**Rule:** before any scaffold or fill operation, AI reads `map_level` from `get_map_state`
and applies the correct field collection protocol for that level
**Guard:** if `map_level` is null → run prescription interview before proceeding

**Acceptance Criteria — Epic JMA-5:**
- Published L3 maps have leakage-relevant fields in `ai_summary`
- AI never applies L3 field collection to an L1 or L2 map
- `map_level` null triggers prescription interview automatically

---

## Epic JMA-6 — Leakage-Ready Validation Gate
**A stage is not done until it can produce a leakage number.**

### US-JMA-06-01 — Leakage-ready check per stage (L3 only)
**Trigger:** end of each stage interview in L3 build
**Check:** does this stage have ALL of:
- `time_duration_value` set
- `cost_rate_value` set on the actor lens
- `stage_goal` set
- At least one `actor_fields.metrics[]` entry with `flag: "leakage"`
**If incomplete:** AI surfaces exactly which field is missing and asks the one question to fill it

### US-JMA-06-02 — Map-level leakage-ready check
**Trigger:** L3 build complete
**Check:** does the map have `measurement_frequency` + `measurement_period_label` set?
**If incomplete:** AI asks for it before surfacing the leakage calculation
**Then:** call `calculate_leakage` and present the result — always surface the 3-year number

**Acceptance Criteria — Epic JMA-6:**
- AI never declares an L3 build complete until all stages pass leakage-ready check
- `calculate_leakage` is always called at end of L3 build
- 3-year cost-of-inaction is always surfaced in the closing message

---

## Build Order

```
── Foundation ───────────────────────────────────────────────────────
US-JMA-01-01 through 01-05   Level prescription interview questions
US-JMA-02-01                 Map-level Ring 2 field collection (L3)
US-JMA-02-02                 Actor cost rate collection
US-JMA-02-03                 Time-on-task per stage collection
US-JMA-02-04                 5 Guard Rail Tests
US-JMA-02-05                 Leakage metric capture

── L1/L2 Protocols ─────────────────────────────────────────────────
US-JMA-03-01                 L1 build protocol
US-JMA-03-02                 L2 build protocol

── Navigation ───────────────────────────────────────────────────────
US-JMA-04-01                 Auto-link L3 to parent L2
US-JMA-04-02                 Offer L2 from L1 stage
US-JMA-04-03                 Offer L3 from L2 stage

── Intelligence ─────────────────────────────────────────────────────
US-JMA-05-01                 ai_summary includes map_level context
US-JMA-05-02                 AI reads map_level before every build
US-JMA-06-01                 Leakage-ready check per stage
US-JMA-06-02                 Map-level leakage-ready check + 3yr surfacing
```

---

## Relationship to Other Epics

| Epic | Dependency |
|---|---|
| Leakage Analysis (LA-1→LA-7) | Provides the Ring 2 fields this epic collects |
| Intelligence Layer (IL-0→IL-4) | Provides MCP tools this epic calls |
| Blueprint Execution & Receipt (RE-1→RE-5) | L3 maps are the blueprints RE executes against |
| Agent Interview Protocol (JMA-1) | Feeds into Journey Map Assistant system prompt |
