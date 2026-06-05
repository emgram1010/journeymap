# Skill: Intelligence Layer — Prescribe the Right Journey Map

## Purpose
An AI agent uses this skill to interview the user and prescribe the correct
journey map type and depth needed to surface real operational insights.
Not every map yields leakage data. This skill determines which level to build.

---

## 🚨 HARD RULES

1. **Never build a map before completing the level prescription interview** — high-level maps produce zero leakage insight
2. **An Atomic Stage Map is always required for leakage analysis** — L1 and L2 maps are navigation only
3. **One primary actor per stage** — if two actors share a stage, split it or link a sub-journey
4. **Every stage must pass the 5 Guard Rail Tests before it is considered metric-ready**
5. **Do not accept vague stage names** — "handle operations" is invalid; "driver confirms job completion on-site" is valid

---

## The Three Map Levels

| Level | Name | Purpose | Yields Leakage? |
|---|---|---|---|
| L1 | Architecture Map | Business domain overview — for executives and domain understanding | ❌ No |
| L2 | Actor Journey Map | One actor's end-to-end process — for capacity and process analysis | ⚠️ Partial |
| L3 | Atomic Stage Map | One actor performing ONE discrete task — for metric capture and leakage detection | ✅ Yes |

**Rule:** L1 links to L2 via `sub_journey`. L2 links to L3 via `sub_journey`.
Exceptions at any level link to exception-handling maps via `link_map` type `exception`.

---

## Prescription Interview — Ask These in Order

### Step 1 — Identify the Domain
> "What type of business or operation are we mapping?"
> "What is the primary outcome this operation tries to deliver?"

*Goal: understand the domain so you can name stages correctly.*

### Step 2 — Identify the Primary Actor
> "Who is the person or system that does the actual work we want to measure?"
> "Is there one actor or multiple actors involved in this process?"

*If multiple actors: build L1 first, then a separate L2/L3 per actor.*

### Step 3 — Determine the Right Level
Ask these three questions in sequence. Stop when you have enough to prescribe.

**Q1 — Scope check:**
> "Are you trying to understand the overall business flow, or a specific person/system's process?"
- Overall flow → prescribe L1 Architecture Map
- Specific actor → continue to Q2

**Q2 — Granularity check:**
> "Do you want to see what [actor] does across their whole day/shift, or just one specific task they perform?"
- Whole shift / end-to-end → prescribe L2 Actor Journey Map
- One specific task → prescribe L3 Atomic Stage Map

**Q3 — Insight goal check:**
> "Do you need to identify where time or money is being lost, or is this more for documentation and process visibility?"
- Leakage / cost analysis → prescribe L3 Atomic Stage Map (required)
- Documentation / visibility → L1 or L2 is sufficient

### Step 4 — Stage Validity (for L3 only)
Before building each stage, run the 5 Guard Rail Tests:

| Test | Question to ask | Fail = |
|---|---|---|
| Single Actor | "Who is the ONE person or system that owns this step's output?" | Multiple owners → split |
| Time-on-Site | "How long does this actually take in the real world?" | No answer → stage too vague |
| Completion Signal | "What tells you this step is done?" | No signal → stage_goal missing |
| Exception | "What happens when this goes wrong?" | No failure mode → stage too abstract |
| Isolation | "Can this step produce a result on its own, without other steps?" | No → needs sub-journey |

---

## Leakage-Ready Cell Requirements

A stage cell is leakage-ready when it has ALL of the following:
- `time_duration_value` + `time_duration_unit` — how long the actor spends here
- `cost_rate_value` + `cost_rate_unit` — what this actor's time costs
- At least one output metric in `actor_fields.metrics[]`
- At least one metric flagged `"flag": "leakage"` — the waste signal
- A `stage_goal` set on the stage — the completion / exit condition

Map-level requirements for compounding math:
- `measurement_frequency` — how many times per year this runs
- `measurement_period_label` — "per job", "per shift", "per week"

---

## Leakage Math (built from cell data)

```
stage_cost_per_event  = time_duration_value × cost_rate_value
annual_leakage        = stage_cost_per_event × measurement_frequency × leakage_ratio
3yr_cost_of_inaction  = annual_leakage × 3
```

`leakage_ratio` = proportion of events where the leakage metric fires
(e.g. 57 hard violations out of 1327 jobs = 0.043)

**The 3-year number is the close.** Always surface it.

---

## Telogis-Inspired Field Mapping (Reference)

These are the proven field concepts from enterprise logistics intelligence.
Apply the same concepts to any industry:

| Telogis concept | Intelligence Layer field | Where it lives |
|---|---|---|
| `time_on_site` | `time_duration_value` | actor_fields on cell |
| `cost_per_hour` | `cost_rate_value` (per_hour) | actor identity |
| `overtime_cost_per_hour` | leakage rate when capacity exceeded | actor_fields metric, flag: leakage |
| `normal_working_time` | planned duration (baseline) | cell content |
| `max_working_time` | capacity ceiling | standing_constraints on actor |
| `fixed_cost` | base cost per instance | journey settings |
| `load_capacity` | throughput limit | actor_fields metric |
| `Signature` (completion) | stage_goal exit condition | stage contract |
| `Alert` (exception fired) | exception sub-journey | link_map type: exception |
| `ShiftPattern` | measurement_frequency | journey settings |

---

## Output — What to Build

After the interview, prescribe ONE of the following:

**Prescribe L1** when:
- User needs executive overview or domain documentation
- Multiple actor types are involved and scope is unclear
- This is the first map in a new architecture

**Prescribe L2** when:
- User wants to understand an actor's full process
- Capacity analysis is the goal (total hours, total cost across a shift)
- L1 already exists and needs drill-down

**Prescribe L3** when:
- User wants to find where time or money is leaking
- Prospect discovery interview is in progress
- Scenario comparison is the goal
- ANY of the 5 Guard Rail Tests can be answered for each stage

**Always link levels** — use `link_map` type `sub_journey` to connect L1 → L2 → L3.
