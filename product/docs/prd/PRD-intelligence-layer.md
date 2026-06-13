# PRD: Intelligence Layer — Blueprint / Watcher / Signal Platform

> **Human stakes:** The operator using this may have just lost their job. Every feature in this PRD
> exists to help them see — in dollars — where their operation is losing money.

---

## Problem

Business operations bleed money through process deviation. Steps skipped, time over-run, wrong
people doing the wrong tasks, no proof of completion. This is universal — cleaning businesses,
consulting practices, field service, healthcare, logistics — every service operation has this problem.

Today, two categories address it:
- **BPM tools** (IBM, Camunda): programmer-first, requires IT, costs $100K+
- **Process mining** (Celonis): reverse-engineers from existing ERP logs, enterprise-only, $300K+

**Neither works for a solo entrepreneur.** Neither lets a non-technical operator build a blueprint
first, attach a watcher to it, and see their leakage in under 20 minutes.

---

## Solution

An AI-native, forward-looking process intelligence platform with 3 mechanisms:

1. **Blueprint** — Any operator describes their process in conversation. An AI agent builds a
   structured journey map. The map is the operational contract.

2. **Watcher** — Real-world events arrive via webhook. The runtime engine checks each event against
   the published map: sequence, duration, completion, constraints. Every deviation is recorded.

3. **Signal** — Deviations are converted to dollars: `time_over × cost_rate × annual_frequency`.
   The 3-year cost of inaction is always surfaced. It makes the invisible visible.

---

## Users

| User | Who they are | What they need |
|---|---|---|
| **Operator** | Solo entrepreneur, small business owner, displaced worker | Build a map through conversation, see leakage in dollars, fix it |
| **AI Agent** | The builder/watcher agent acting on the operator's behalf | Clear skills, tools, and readiness rules to build and monitor maps |
| **Reviewer** | A partner or advisor helping the operator | Read maps, understand stage health, interpret leakage numbers |

---

## Scope

**In scope:**
- Journey map creation (L1 / L2 / L3)
- AI-guided prescription interview (intelligence_layer.md)
- Discovery pitch mode (discovery_pitch.md)
- Runtime conformance (4 checks via webhook)
- Leakage math (`calculate_leakage`)
- Scenario cloning and comparison
- Map publishing and snapshot compilation
- Map linking (exception, anti_journey, sub_journey)

**Out of scope (in this PRD):**
- Dispatch layer pre-flight validation → see `PRD-runtime-engine.md`
- Constraint severity enforcement → see `PRD-runtime-engine.md`
- Leakage scenario comparison UI → see `PRD-leakage-analysis.md`

---

## Epics Under This PRD

| Epic | Status | Description |
|---|---|---|
| `intelligence-layer-epic.md` | ✅ Shipped | L1/L2/L3 map level system + prescription interview |
| `leakage-analysis-epic.md` | ✅ Shipped | calculate_leakage tool + measurement_frequency |
| `three-level-journey-enablement-epic.md` | ✅ Shipped | sub_journey linking between levels |
| `link-map-mcp-epic.md` | ✅ Shipped | exception / anti_journey / sub_journey link types |
| `scenarios-mcp-epic.md` | ✅ Shipped | clone_scenario + compare_scenarios |

---

## Success Metrics

- Operator describes their operation → leakage number in < 20 minutes, no IT required
- All 4 runtime checks pass on every L3 map before publish (checklist in `atomic_runtime_template.md`)
- `calculate_leakage` returns a non-zero 3-year number on every published L3 map
- Discovery pitch produces a directionally credible leakage number in 4–6 questions

---

## Non-Goals

- Do not build a generic reporting dashboard
- Do not require operators to understand webhooks, JSON, or API concepts
- Do not build features that serve neither Blueprint, Watcher, nor Signal

---

## References

- `product/docs/00-PLATFORM-VISION.md` — Human stakes and positioning
- `product/docs/01-ARCHITECTURE.md` — Technical model
- `product/docs/releases/MVP-DEFINITION.md` — Minimum sellable intelligence layer
- `product/docs/ux/USER-FIRST-RUN-JOURNEY.md` — First 10–20 minute operator experience
- `product/docs/ux/USER-LANGUAGE-GUIDE.md` — User-facing language translation
- `emgram-skills/skills/intelligence_layer.md` — Prescription interview skill
- `emgram-skills/skills/discovery_pitch.md` — Sales mode skill
- `emgram-skills/skills/atomic_runtime_template.md` — L3 readiness checklist
