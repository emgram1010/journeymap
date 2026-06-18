# Snapshot Versioning

> Runtime must validate against a stable contract, not a moving draft map.

---

## Current Code Reality

`automation_snapshot` is one record per journey map, upserted on publish.
It has a monotonically increasing `version` and stores the compiled `graph` JSON.

This means the current table stores the latest compiled snapshot, not a historical append-only list.

---

## Runtime Rule

Every execution must bind to one snapshot version at start.

```text
dispatch/execution starts → read current automation_snapshot.version
                         → store snapshot_version in workflow_execution.validation_snapshot
                         → score all events against that version
```

---

## Republish During Active Execution

If a map is republished while an execution is active:

- Active execution continues against the snapshot version it started with.
- New executions use the latest snapshot version.
- The runtime must not change rules mid-run unless a future re-dispatch feature explicitly opts in.

---

## Gap

Because snapshots are upserted, full historical snapshot replay is limited.

Short-term mitigation:
- Store `snapshot_version` and a compact copy of validation-critical fields inside `workflow_execution.validation_snapshot`.

Future option:
- Convert `automation_snapshot` to append-only or add `automation_snapshot_history`.

---

## Required Fields In Execution Snapshot

- `journey_map_id`
- `snapshot_version`
- `validated_at`
- `stage_contracts[]`
- `constraint_contracts[]`
- `dispatch_actor_assignments[]` when dispatch exists
