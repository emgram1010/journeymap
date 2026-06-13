# Test Strategy — Intelligence Layer Runtime Docs

> Documentation for what implementation agents must test later. No tests are added by this doc.

---

## P0 Test Areas

| Area | Required Test |
|---|---|
| Constraint engine | critical blocks, major warns, normal logs |
| Violation log | metadata includes rule, severity, trigger value, snapshot version |
| Execution status | on_time, late, early, missed, blocked, wrong_order |
| Leakage | missing fields return incomplete list; valid map returns non-zero 3-year number |

---

## Runtime Event Tests

- Duplicate `idempotency_key` does not double-count leakage
- Out-of-order event marks `wrong_order`
- Event with old `snapshot_version` is handled explicitly
- Missing required payload fields returns validation error

---

## Migration Tests

- Existing map with only `standing_constraints` still loads
- Existing `calculate_leakage` labor-only behavior still works
- Existing `automation_snapshot` publish still increments version
