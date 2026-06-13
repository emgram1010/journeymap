# Constraint Ownership — Where Rules Live

> Purpose: prevent schema drift. A constraint must have one clear owner before implementation.

---

## Current Code Reality

Today constraints live as `journey_lens.standing_constraints` — a text field on the actor/lens.

That is useful for human context, but not enough for runtime enforcement.

---

## Ownership Model

| Constraint Type | Lives On | Why |
|---|---|---|
| Actor-wide standing rule | `journey_lens` | Applies to the actor across all stages |
| Stage exit rule | `journey_stage` | Defines what must be true for this stage to be complete |
| Actor-at-stage rule | `journey_cell` | Applies only when this actor performs this stage |
| Runtime assignment rule | dispatch/execution instance | Depends on who/what is assigned for this specific run |

---

## Target Fields

| Owner | Field | Example |
|---|---|---|
| Lens | `standing_constraints` legacy text | “Technician must be certified” |
| Lens | `actor_constraints[]` future structured rules | Availability, license, budget limit |
| Stage | `stage_goal` existing | “intake_form_submitted” |
| Stage | `stage_constraints[]` future rules | Required actor tags, max duration, required evidence |
| Cell | `actor_fields.constraints[]` future optional | “This actor must get manager approval at this stage” |
| Execution | `workflow_execution.validation_snapshot` existing | Dispatch/pre-flight validation report |

---

## Rule Of Thumb

If the rule describes **who the actor is**, it belongs to the lens.
If the rule describes **what this stage requires**, it belongs to the stage.
If the rule describes **this actor doing this stage**, it belongs to the cell.
If the rule depends on **this specific run**, it belongs to the execution/dispatch snapshot.

---

## Migration Guidance

Do not delete `standing_constraints`. Treat it as legacy human-readable context.

Future structured constraints should be introduced additively first, then agents can help migrate legacy text into structured rules.
