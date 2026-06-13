# PRD: Leakage Analysis — Cost Intelligence and Scenario Comparison

> The leakage number is the close. It transforms a process observation into a business case.
> It is the reason a solo entrepreneur fixes their operation instead of living with it.

---

## Problem

Operators know something is wrong. They don't know how much it costs. The gap between
"I feel like we're losing time on intake" and "your intake process costs you $47,000 over 3 years"
is the entire value of this platform.

Today, `calculate_leakage` works — but only when all required fields are populated. In practice:
- Many maps are missing `measurement_frequency` (the compounding multiplier)
- `leakage_ratio` is estimated, not derived from violation log data
- Scenario comparison surfaces a health score but not the dollar delta between scenarios
- The discovery pitch produces a number in conversation but nothing persists to the map

Current code reality:
- `calculate_leakage` is labor-only today: cell duration × lens cost rate × measurement frequency.
- It returns `incomplete_cells[]` when required time/cost fields are missing.
- It does not yet read runtime event history or violation counts.

---

## Solution

### Core Leakage Formula (Already Implemented)

```
stage_cost_per_event  = time_duration_value × cost_rate_value
annual_leakage        = stage_cost_per_event × measurement_frequency × leakage_ratio
cost_of_inaction_3yr  = annual_leakage × 3
```

The 3-year number is always surfaced. It is the close.

### Improvements Needed

**1. Leakage ratio from violation log (P0 dependency)**

Today `leakage_ratio` is manually estimated. Once the violation log (P0) ships:
- `leakage_ratio` = `total_violations / total_executions` — computed automatically from event data
- `calculate_leakage` becomes accurate, not estimated

**2. Dollar delta on scenario comparison (P1)**

`compare_scenarios` returns health scores. Add:
- `leakage_delta` = Scenario A annual_leakage − Scenario B annual_leakage
- `roi_of_change` = `leakage_delta × 3` (3-year savings from switching scenarios)
- Surface as: "Scenario B saves you $X over 3 years compared to your current process"

**3. Discovery pitch → map persistence (P1)**

When a discovery pitch produces a leakage estimate, persist it to the demo map:
- `actual_duration` from the conversation
- `cost_rate_value` from the conversation
- `measurement_frequency` from the conversation
- Mark cells as `draft` status — not production
- This makes the demo map reviewable and upgradeable to production

**4. Leakage readiness guardian (P1)**

Before `calculate_leakage` runs, check all required fields and return a structured gap list:
```json
{
  "ready": false,
  "missing": [
    { "stage_key": "s2", "field": "planned_duration", "impact": "duration_ok check disabled" },
    { "map_level": "settings", "field": "measurement_frequency", "impact": "leakage = $0" }
  ]
}
```
Today it returns $0 silently. The guardian makes the gap visible.

**5. Stage cost components — full cost picture per stage (P2)**

The current leakage math only captures actor labor. Every real operation has additional costs
that fire on every stage execution regardless of whether anything went wrong.

The intelligence layer must capture all of them — without using domain-specific language
(no "fuel", no "mileage" — those are logistics nouns, not platform vocabulary).

```json
{
  "stage_cost_components": [
    { "label": "Staff labor",      "type": "labor",       "rate": 28.00, "unit": "per_hour" },
    { "label": "Transaction fee",  "type": "per_event",   "rate": 3.50,  "unit": "per_event" },
    { "label": "Supplies used",    "type": "consumption", "rate": 4.20,  "unit": "per_unit",
      "quantity_key": "units_consumed" },
    { "label": "Rush premium",     "type": "variance",    "rate": 15.00, "unit": "per_event",
      "trigger": "duration_exceeded" }
  ]
}
```

| Component type | When it fires | Domain example |
|---|---|---|
| `labor` | Always — actor time × rate | Staff hour, contractor rate |
| `per_event` | Every execution regardless of duration | Background check fee, platform fee, supply kit |
| `consumption` | Scales with quantity used | Supplies per job, API calls per transaction |
| `variance` | Only when stage exceeds planned bounds | Rush fee, overtime, rework cost |

**Leakage formula expands to:**
```
total_stage_cost = labor + per_event + consumption + variance
leakage_delta    = (total_actual - total_planned) × leakage_ratio × measurement_frequency
```

**Why this matters for the close:** Saying "time alone" in the discovery pitch signals that the
full cost is higher. Cost components are what makes that true — and what makes the real number
larger than the estimate the prospect first hears.

---

## Leakage Readiness Checklist (Current — from atomic_runtime_template.md)

A stage is leakage-ready when it has:
- [ ] `time_duration_value` + `time_duration_unit`
- [ ] `cost_rate_value` + `cost_rate_unit` on actor identity
- [ ] At least one `actor_fields.metrics[]` entry with `flag: "leakage"`
- [ ] `stage_goal` set on stage contract
- [ ] `planned_duration` on primary actor cell

Map-level requirements:
- [ ] `measurement_frequency` — non-null, non-zero integer
- [ ] `measurement_period_label` — non-null string

---

## Epics Under This PRD

| Epic | Priority | File |
|---|---|---|
| Scenario Leakage Comparison | P1 | `product/stories/scenario-leakage-comparison-epic.md` |
| Leakage Readiness Guardian | P1 | TBD — new epic needed |
| Discovery Pitch Persistence | P1 | TBD — new epic needed |
| Stage Cost Components | P2 | TBD — new epic needed |

---

## Success Metrics

- `calculate_leakage` always returns a reason when leakage = $0 (not silent)
- `compare_scenarios` always returns a dollar delta, not just a health score
- Discovery pitch conversation produces a demo map with leakage pre-populated
- P0 violation log data feeds `leakage_ratio` — estimated ratio replaced with computed ratio

---

## The Close

The leakage number is always presented in this order:
1. Cost per event: "Each time that happens, it costs roughly $X in time alone"
2. Annual cost: "Across [frequency] per year, that's $X annually"
3. 3-year cost: "Over three years, you're looking at $X sitting in that one step"

Round numbers. Use "time alone" to signal the full cost is higher. Never say the process is broken — reflect the numbers back.

---

## References

- `product/docs/01-ARCHITECTURE.md` — Leakage math formula
- `product/docs/02-VOCABULARY.md` — Leakage terms
- `product/docs/releases/MVP-DEFINITION.md` — Minimum sellable leakage workflow
- `product/docs/architecture/RUNTIME-EVENT-CONTRACT.md` — Future event source for computed leakage ratios
- `emgram-skills/skills/intelligence_layer.md` — Leakage-ready cell requirements
- `emgram-skills/skills/discovery_pitch.md` — Discovery pitch leakage formula
- `product/stories/leakage-analysis-epic.md` — Original leakage epic
- `product/stories/scenario-leakage-comparison-epic.md` — Scenario comparison epic
