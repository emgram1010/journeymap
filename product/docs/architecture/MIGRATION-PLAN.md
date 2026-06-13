# Migration Plan

> New runtime contracts must not break existing maps.

---

## Current Legacy Fields

| Field | Current Meaning | Future State |
|---|---|---|
| `journey_lens.standing_constraints` | Human-readable actor constraints | Preserve as legacy text; add structured constraints later |
| `journey_cell.time_duration_value` | Stage duration input | Continue using for labor leakage |
| `journey_lens.cost_rate_value` | Actor labor rate | Continue using as labor component |
| `event_log.action + metadata` | Generic event storage | Use short-term for runtime/violation events |

---

## Migration Rules

1. Add new structured fields without deleting old fields.
2. Preserve legacy text in-place.
3. Let AI assist the user in converting text constraints into structured rules.
4. Maintain old leakage math until cost components ship.
5. Do not require old maps to republish unless runtime behavior depends on new fields.

---

## Rollback Principle

Every P0 runtime change should be reversible to the current behavior:

```text
free-text constraints + boolean runtime checks + labor-only leakage
```
