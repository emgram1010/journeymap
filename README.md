# emgram — The Intelligence Layer

> **The person using this platform may have just lost their job.**
> They are not a software engineer. They are someone with domain knowledge
> who needs to see — in dollars — where their operation is bleeding money,
> so they can fix it and survive.

---

## What This Is

emgram is a **forward-looking process intelligence platform**.

Anyone can build a structured blueprint of how their business should operate.
The runtime watches every real execution against that blueprint.
The leakage math converts every deviation into a financial cost.

**The map is the intelligence. The runtime is the proof. The leakage is the cost of not following your own rules.**

---

## The 3 Mechanisms (Never Violate These)

| Mechanism | Name | What It Does |
|---|---|---|
| **Blueprint** | Journey Map | Machine-readable contract — defines what correct execution looks like |
| **Watcher** | Runtime Engine | Compares real-world events against the blueprint in real time |
| **Signal** | Leakage | Converts every deviation into a dollar amount |

Every feature built must serve one of these three. If it doesn't — it's noise.

---

## What Makes This Different

**Celonis** (the $13B Process Intelligence market leader) works **backward** — it mines logs from SAP/Oracle systems to reverse-engineer what your process looks like. Enterprise-only. $300K+ per year. Requires IT teams.

**emgram** works **forward** — any operator builds the blueprint first through conversation, then attaches a watcher to it. Works for any business domain. Any size. No IT required.

---

## Architecture in One View

```
L1 Architecture Map     ← executive overview, multiple actors
  └── L2 Actor Journey Map   ← one actor's end-to-end process
        └── L3 Atomic Stage Map  ← one discrete task (only level that yields leakage math)
```

**Runtime checks per stage (4):**
- `sequence_ok` — right step, right order?
- `duration_ok` — within planned time?
- `goal_met` — completion signal present?
- `constraints_ok` — actor qualified?

**Leakage math:**
```
stage_cost_per_event  = time_duration × cost_rate
annual_leakage        = stage_cost_per_event × measurement_frequency × leakage_ratio
cost_of_inaction_3yr  = annual_leakage × 3
```

---

## Where To Go

| I need to... | Go here |
|---|---|
| Understand the vision and human stakes | `product/learnings/INSPIRATION.md` |
| Build or update a journey map | `emgram-skills/instructions.md` |
| Run a discovery pitch / demo for a prospect | `emgram-skills/skills/discovery_pitch.md` |
| Know what level of map to build | `emgram-skills/skills/intelligence_layer.md` |
| Understand L3 runtime readiness rules | `emgram-skills/skills/atomic_runtime_template.md` |
| Understand the logistics inspiration (Telogis) | `product/learnings/spirit-translation-logistics-to-intelligence-layer.md` |
| Know what features are missing (P0 gaps) | `product/learnings/telogis-tde-architecture-analysis.md` |
| Understand the Plan→Dispatch→Execute lifecycle | `product/learnings/fleet-route-lifecycle-analysis.md` |

---

## Repo Structure (Key Paths)

```
emgram-skills/
  instructions.md          ← agent decision brain — read first every session
  skills/                  ← HOW to operate each capability

product/
  learnings/               ← WHY and WHERE ideas came from (research)
  stories/                 ← PRDs and epics

agents/                    ← AI agent definitions (XanoScript)
tools/                     ← MCP tool implementations
tables/                    ← Database schema
mcp_servers/               ← MCP server entry points
```

---

## The Inspiration

This platform borrows its core architecture from **last-mile logistics** (Telogis / Verizon Connect Fleet) — a domain that solved the same problem 10 years ago for trucks and drivers.

- The **Route** became the Journey Map
- The **Job Monitor** became the Runtime Engine
- The **Alert + cost rate** became Leakage math

The leap emgram makes: logistics is domain-specific (trucks, GPS, drivers).
emgram is **domain-agnostic** — the same 3 mechanisms work for any business operation, any actor, any system sending events.

See `product/learnings/INSPIRATION.md` for the full north star reference.
