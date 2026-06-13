# MVP Definition — First Usable Intelligence Layer

> MVP means a non-technical operator can see where money leaks without needing IT.

---

## MVP User Promise

An operator can describe one real process, receive an L3 atomic journey map, enter time/cost/frequency, and see a credible 3-year leakage number.

---

## MVP Scope

| Capability | Required For MVP? | Notes |
|---|---:|---|
| AI-guided map creation | ✅ | Existing journey map tools support this |
| L3 atomic map level | ✅ | Leakage math only valid here |
| Actor labor cost rate | ✅ | Existing `journey_lens.cost_rate_value` |
| Stage time duration | ✅ | Existing `journey_cell.time_duration_value` |
| Measurement frequency | ✅ | Existing `journey_map.measurement_frequency` |
| Calculate leakage | ✅ | Existing `calculate_leakage` tool |
| Runtime webhook conformance | ⚠️ | Needed for full watcher, but discovery MVP can start estimated |
| Constraint severity | ❌ for demo, ✅ for real runtime | P0 runtime accuracy item |
| Dispatch layer | ❌ | P1 |
| Stage cost components | ❌ | P2 |

---

## MVP Success Metric

Time from “I have a process” to “I see my 3-year cost of inaction” is under 20 minutes.

---

## MVP Non-Goals

- No generic dashboard
- No user-facing webhook configuration
- No full BPMN-style branching UI
- No industry-specific logistics nouns in the intelligence layer
