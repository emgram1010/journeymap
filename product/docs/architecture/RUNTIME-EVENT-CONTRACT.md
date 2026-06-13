# Runtime Event Contract

> Purpose: define the stable shape external systems send when reporting real-world execution.

---

## Current Code Reality

- `workflow_execution` exists and stores run state, `stage_outputs`, and `validation_snapshot`.
- `event_log` exists but is generic: `action` + `metadata`.
- No dedicated runtime event table exists yet.
- `calculate_leakage` currently reads map/cell/lens fields, not event history.

---

## Minimum Event Payload

```json
{
  "event_id": "evt_001",
  "idempotency_key": "job-9981:s2:complete:v1",
  "source_system": "custom",
  "journey_map_id": 42,
  "snapshot_version": 7,
  "external_ref_id": "job-9981",
  "stage_key": "s2",
  "occurred_at": "2026-06-12T14:22:00Z",
  "actual_duration": 18.5,
  "completion_signal": "arrived_at_address",
  "payload": {}
}
```

---

## Required Fields

| Field | Why Required |
|---|---|
| `idempotency_key` | Prevents duplicate retry events from double-counting leakage |
| `source_system` | Audit/debugging across integrations |
| `journey_map_id` | Resolves the map contract |
| `snapshot_version` | Ensures the event is scored against the correct published snapshot |
| `external_ref_id` | Threads all stages for one job/case/call |
| `stage_key` | Identifies the stage contract |
| `occurred_at` | Allows ordering and missed/late calculations |
| `completion_signal` | Feeds `goal_met` |

---

## Event Ordering Rule

If an event arrives out of order, do **not** silently reorder it.

Default target behavior:
1. Record the event.
2. Mark `sequence_ok = false`.
3. Set `stage_status = wrong_order`.
4. If an `anti_journey` link exists for that source cell, return it in the response.

---

## Storage Recommendation

Short-term: use existing `event_log`.

```json
{
  "action": "runtime_event_received",
  "metadata": { "full_event_payload": "..." }
}
```

Future: create a dedicated runtime event table only when event volume/querying requires it.
