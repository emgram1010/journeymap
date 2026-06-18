# Observability

> If the watcher cannot explain what it saw, the leakage number loses trust.

---

## Current Code Reality

- `agent_tool_log` and `agent_turn_log` already support AI traceability.
- `event_log` exists as generic `action` + `metadata`.
- `automation_connection` tracks push status and `last_error_message`.

---

## Metrics To Track

| Metric | Why |
|---|---|
| runtime events received | Volume baseline |
| duplicate events rejected | Idempotency health |
| events rejected by auth | Security health |
| hard violations | Blocking process failures |
| soft violations | Leakage signal |
| missed stages | Execution reliability |
| leakage calculation failures | Data completeness gap |
| snapshots published | Contract version changes |
| webhook push failures | Integration health |

---

## Logging Rule

All runtime decisions should log enough metadata to answer:

```text
What event arrived?
Which snapshot scored it?
Which checks passed/failed?
What did the runtime do next?
What cost did it assign?
```
