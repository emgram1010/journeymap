# Journey Map — Validation, Publishing & Execution PRD

## What We're Building

A journey map today is a well-written plan. What it is not yet is a certified, executable instruction set that a human or AI can follow with confidence. Right now, a map can be declared "complete" with missing fields, published without any quality gate, and executed without a single checkpoint to verify the output was correct. This initiative closes that gap across three connected problems.

## The Three Problems

**Validation** ensures the map is built correctly before anyone uses it. This means the AI that builds the map is held to a defined standard — not just "all cells filled" but every structured field required for leakage math is present, every stage has an exit condition, and a Validator actor inside the map has defined what "done" looks like for each step. If the map cannot pass a two-pass check, it is not complete.

**Publishing** makes the transition from draft to active mean something. Today, publish is a save button. After this initiative, publish is a certification event — a formal gate that verifies the map meets its required standard before it becomes available for use. A published map is a certified manifest. Executions run against the certified version, not the live editable map.

**Execution** tracks what actually happened when a human or AI ran the map. Each run produces a per-stage record: what was done, by whom, what status it reached, and why it was blocked or skipped. If a situation arises that the map never anticipated, the agent stops, flags it, and escalates — it does not guess. Over time, these execution records feed back into the map as improvement signals.

## Why It Matters

These three initiatives are sequential. You cannot have reliable execution without a meaningful publish gate. You cannot have a meaningful publish gate without a validated map. The order is: build it right → certify it → run it with accountability. Together they transform Emgram from a documentation tool into an operational system that both humans and AI agents can trust and follow to the letter.

## Scope

| Initiative | Folder | Phases |
|---|---|---|
| Validation | `product/validation/validation/` | Phase 1–3 |
| Publishing | `product/validation/publishing/` | Phase 1–3 |
| Execution | `product/validation/execution/` | Phase 1–3 |

Start with Validation Phase 1 — it requires no backend changes and unlocks everything downstream.
