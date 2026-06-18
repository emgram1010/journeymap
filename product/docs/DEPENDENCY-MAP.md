# Dependency Map — Intelligence Layer Docs

> Documentation-only planning artifact. This does not change runtime behavior.

---

## Build Rule

Do **not** treat all epics as sequential. Some can run in parallel if they do not share the same runtime contract.

---

## Hard Dependencies

| From | To | Why |
|---|---|---|
| `EPIC-P0-constraint-engine.md` | `EPIC-P0-violation-log.md` | Violation records need `severity` and `failure_mode` from the constraint model |
| `EPIC-P0-constraint-engine.md` | `EPIC-P1-dispatch-layer.md` | Dispatch runs constraint checks before execution starts |
| `EPIC-P0-violation-log.md` | `EPIC-P1-dispatch-layer.md` | Dispatch violations report should use the same violation payload shape |
| `RUNTIME-EVENT-CONTRACT.md` | webhook/security implementation | External systems need one stable payload contract |
| `SNAPSHOT-VERSIONING.md` | dispatch/runtime implementation | Runtime must know which snapshot version it is validating against |

---

## Parallel Work Allowed

| Epic | Can Run In Parallel With | Reason |
|---|---|---|
| `EPIC-P0-execution-status.md` | P0 constraint engine | Status can start from `planned_duration` vs `actual_duration`; constraint overrides can be added later |
| `EPIC-P1-completion-evidence.md` | P1 dispatch layer | Evidence strengthens `goal_met`; dispatch strengthens pre-flight validation |
| `EPIC-P2-stage-cost-components.md` | P0/P1 planning | Cost components are documentation/schema planning until leakage engine expands |

---

## Recommended Sequencing

```text
Track A: P0-1 Constraint Engine
Track B: P0-3 Execution Status Enum

Then:
Track A: P0-2 Violation Log

Then:
Track A: P1-1 Dispatch Layer
Track B: P1-2 Completion Evidence
```

---

## Important Correction To Roadmap Language

The rule is **not** “never start P1 while P0 is open.”

The correct rule is:

> Do not **ship dependent P1 runtime behavior** before its P0 contracts are complete.
> Independent P1 planning or evidence work may begin in parallel.
