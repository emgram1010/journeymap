# emgram Inspiration: The Spirit of Last-Mile Logistics

> Read this before building any feature. It is the north star.

---

## Where This Came From

The founder's domain is **last-mile logistics** (Telogis / Verizon Connect Fleet).
In that world, companies solved a hard operational problem with precision:

> "How do I know if the real world followed the plan — and what did it cost me when it didn't?"

emgram takes that same solved problem and applies it to **every business operation** — not just trucks.

---

## The 3 Mechanisms to Always Honor

### 1. The Blueprint
Logistics calls it a **Route**. emgram calls it a **Journey Map**.

It is not a flowchart. It is not a checklist.
It is a **machine-readable contract** that defines:
- What steps exist and in what order
- Who is qualified to do each step
- How long each step should take
- What "done" looks like at each step

**The map stores the business's operational DNA.**

### 2. The Watcher
Logistics calls it the **Job Monitor**. emgram calls it the **Runtime Engine**.

It watches real-world events and asks one question:
> "Did reality match the contract?"

It does not execute the process. It witnesses it and scores it.
Four checks — same in both worlds:
- Right step, right order? → `sequence_ok`
- Within time? → `duration_ok`
- Completion proven? → `goal_met`
- Actor qualified? → `constraints_ok`

### 3. The Signal
Logistics calls it an **Alert + cost rate**. emgram calls it **Leakage**.

Every deviation from the blueprint has a financial cost:
`time_over × actor_cost_rate × annual_frequency = leakage`

This turns a process observation into a business case.
This is what makes the intelligence layer actionable.

---

## The Key Leap emgram Makes

Logistics is domain-specific (trucks, drivers, GPS).
emgram is **domain-agnostic**.

The same 3 mechanisms work for:
- A nurse skipping a care step
- A sales rep bypassing qualification
- A contractor starting work without sign-off
- An onboarding process that takes 3x longer than planned

**Any business process. Any actor. Any system sending events.**

---

## The One-Line Architecture Statement

> Companies build the blueprint of how their business should operate.
> The runtime watches every real execution against it.
> The leakage converts every deviation into a financial cost.

**The map is the intelligence. The runtime is the proof. The leakage is the cost of not following your own rules.**

---

## The Cost Translation — Fuel to Execution Cost

One of the clearest analogies from logistics is the **fuel price input**.

In a transportation management system, the route planner doesn't just track driver time.
They also track what it costs to run the route beyond the driver:
- Gas price (e.g., $3.50/gallon average) × gallons consumed per job
- Vehicle wear (e.g., $0.18/mile) × miles driven
- Platform/dispatch fee per delivery

These are **non-labor operational costs** — they fire on every execution regardless of whether anything went wrong.

### The Spirit Translation (NOT logistics vocabulary)

The intelligence layer borrows this concept — but the language must stay domain-agnostic.
"Fuel" and "mileage" belong to trucks. The intelligence layer serves nurses, consultants, contractors, and recruiters too.

The universal concept is: **"What does it cost to run this step — beyond the person doing it?"**

| Logistics (spirit only — do not use) | Intelligence Layer (use this) |
|---|---|
| Fuel cost per job | **Execution cost** — resource cost incurred per run of this stage |
| Vehicle wear per mile | **Consumption rate** — cost that scales with output/usage |
| Delivery platform fee | **Per-event cost** — flat cost that fires every time this stage runs |
| Overtime premium | **Variance cost** — extra cost when stage exceeds planned bounds |

### Why This Matters

The current leakage math only measures **actor time**:
`time_over × cost_rate = leakage`

But a solo entrepreneur's real cost per job is:
`labor + execution cost + per-event cost + variance cost`

When a cleaning business owner's supply cost rises from $4 to $6 per job, their leakage model
shifts — without them seeing it. An intelligence layer that captures all cost components
surfaces the full picture, not just the labor slice.

**The fuel analogy is the reminder: never let "cost" mean only "labor time." Real operations
have cost components beyond the actor. The intelligence layer must hold all of them.**

---

## What to Reference for Deep Research

- `telogis-tde-architecture-analysis.md` — schema-level constraint features from Telogis TDE tables
- `fleet-route-lifecycle-analysis.md` — Plan → Dispatch → Execute lifecycle mapping
- `spirit-translation-logistics-to-intelligence-layer.md` — full feature translation table
