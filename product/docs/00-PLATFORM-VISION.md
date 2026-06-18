# Platform Vision — emgram Intelligence Layer

> Read this before building any feature.
> Every build decision should pass one test: **"Does this help someone who just lost their job run their operation better?"**

---

## The Human Stakes

Millions of people are losing their jobs. They are starting cleaning businesses, consulting practices, small logistics operations, service firms — because they have no other choice.

They have **domain knowledge** — they know how to do the work. What they don't have is **operational infrastructure**. No way to document how their process should work. No way to measure where time is being lost. No way to see — in dollars — what their broken process is costing them.

Enterprise companies have Celonis ($13B), SAP Signavio, IBM BPM. Those tools cost $300,000+ per year and require dedicated IT teams to configure.

**Nobody built this for the solo entrepreneur.**

emgram is that tool.

---

## Who This Is For

**Primary user: The operator.**
A solo entrepreneur, a small team lead, a service business owner, a displaced worker who just started their own operation. They are not a software engineer. They will not read a manual. They need to talk through their process and have a system tell them where money is leaking — in plain language, in dollars.

**Secondary user: The agent team.**
AI agents that build maps on the operator's behalf, watch execution against those maps, and surface leakage proactively. The operator never has to understand the technical layer — the agents handle it.

**The buyer is also the user.** There is no IT department. No procurement cycle. No integration team.

---

## The Problem We Solve

> "I know my process takes too long and costs too much. I just don't know exactly where or how much."

Every service operation has a gap between how work *should* happen and how it *actually* happens. That gap is invisible until it becomes a cash flow crisis.

emgram makes the gap visible — before the crisis.

---

## The Solution: 3 Mechanisms

### 1. The Blueprint (Journey Map)
The operator builds a structured map of how their business should operate — step by step, actor by actor, with time and cost anchored to each step. This is the operational contract.

The map is built through conversation with an AI agent. No forms. No configuration. No IT required.

### 2. The Watcher (Runtime Engine)
Real-world events are sent to the runtime via webhook. The engine compares each event against the blueprint and runs 4 checks: sequence, duration, completion, constraints.

Every deviation is recorded. Nothing is silently skipped.

### 3. The Signal (Leakage Math)
Every deviation has a cost: `time_over × cost_rate × annual_frequency = leakage`.

The 3-year cost of inaction is always surfaced. It turns a process observation into a business case. It is the close.

---

## What Success Looks Like

A solo entrepreneur describes their operation in a 10-minute conversation.
An AI agent builds the blueprint, attaches a watcher, and shows them their leakage number.
They see — for the first time — that their broken intake process costs them $47,000 over 3 years.
They fix it. They keep the money.

That is the product working.

---

## How emgram Is Different

| | Legacy BPM (IBM, Camunda) | Process Mining (Celonis) | **emgram** |
|---|---|---|---|
| Who can use it | IT developers | Enterprise data teams | Any operator |
| Builds the blueprint | Code (XML/BPMN) | Mined from ERP logs | AI conversation |
| Works without existing systems | ❌ | ❌ | ✅ |
| Forward-looking | ❌ | ❌ | ✅ |
| Cost/leakage math | ❌ | ❌ | ✅ |
| Entry price | $100K+ | $300K+ | Accessible |

**The key architectural difference:** Celonis reverse-engineers your process from system logs. emgram defines the process first, then watches whether reality follows. That's not a feature difference — it's a category difference.

---

## North Star Metric

> **Time from "I just started a business" to "I know exactly where I'm losing money"**

Target: under 20 minutes, no IT required, no prior process documentation needed.

---

## References

- `product/learnings/INSPIRATION.md` — The logistics analogy that founded this architecture
- `product/docs/01-ARCHITECTURE.md` — Technical model
- `product/docs/ROADMAP.md` — What to build next
