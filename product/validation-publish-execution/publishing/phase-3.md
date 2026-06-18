# Publishing — Phase 3: Certified Snapshot & Version Pinning

**Problem this phase solves:** When a map is published today, the `automation_snapshot` is compiled — but executions read from the live map, not the snapshot. If someone edits the map after it goes active, any in-progress or future executions see the updated version, not the version that was certified. The plan and the certified manifest are the same object. In logistics terms: the dispatcher keeps editing the route after the driver has already left.

**Goal:** Make the published `automation_snapshot` the immutable execution contract. Executions are dispatched against a specific snapshot version — not the live map. Edits to the map after publish do not affect in-flight or pending executions. A "stale" map (edited since last publish) is surfaced clearly so users know re-certification is needed.

**Dependency:** Phase 2 (gate enforcement) must be complete. Version pinning only makes sense once publish is a meaningful certification event.

**Exit condition for this phase:** Every `workflow_execution` record is pinned to the `automation_snapshot` version active at dispatch time. Post-publish map edits surface a "Re-publish required" signal. A publish history log is queryable.

---

## US-PUB-07 — Pin Map Version at Dispatch Time

**What:** When `invoke_map` creates a `workflow_execution`, record the `automation_snapshot` version active at that moment. The execution reads all stage data from the pinned snapshot — not from a live `get_map` call.

**Implementation:**
- Add `map_version` (int) field to `workflow_execution` table — FK to `automation_snapshot.version` for the map
- On `invoke_map`, query the latest `automation_snapshot` for the target map and write its `version` to `map_version`
- Any tool or agent reading stage data during execution reads from `automation_snapshot.graph` at `map_version` — not from `journey_stage` / `journey_cell` tables directly
- If no published snapshot exists for the map → `invoke_map` rejects with: "Map has not been published. Cannot dispatch an uncertified map."

**Why this matters:**
- A map edit mid-run cannot change the instruction set the agent is following
- The execution record is a faithful account of what the agent was told to do — not what the map currently says
- Audits and replays are accurate — you can reconstruct exactly what instructions were active

**Acceptance criteria:**
- `workflow_execution.map_version` is populated on every new execution record
- `invoke_map` rejects dispatch if no published snapshot exists
- Stage data during execution is sourced from the snapshot graph, not live tables

---

## US-PUB-08 — Publish History Log

**What:** Every successful publish event writes an immutable publish history record. This gives map owners a full audit trail of when each version was certified, by whom, and what gate checks passed.

**Publish history record schema:**
```json
{
  "map_id": 162,
  "version": 3,
  "published_at": "ISO timestamp",
  "published_by": "user_id or agent_id",
  "published_by_type": "human | ai",
  "gate_1_passed": true,
  "gate_2_passed": true,
  "gate_3_passed": null,
  "gate_3_applicable": false,
  "snapshot_id": 45
}
```

**Expose via:** `GET /journey_map/{id}/publish_history`
- Returns all publish records for the map, newest first
- Each record links to its `automation_snapshot` by `snapshot_id`

**Acceptance criteria:**
- Every `publish_map` success writes a publish history record
- `GET /journey_map/{id}/publish_history` returns full version history
- Records are immutable — no patch or delete on publish history
- `gate_N_applicable: false` distinguishes "gate did not apply" from "gate was not run"

---

## US-PUB-09 — Stale Map Detection and Re-publish Warning

**What:** If a map is edited after its last publish, surface a clear "Re-publish required" signal. Execution against a stale map is flagged — the agent and user both know the execution is running against an older certified version.

**Stale detection logic:**
- Compare `journey_map.updated_at` against `automation_snapshot.compiled_at` for the latest version
- If `updated_at > compiled_at` → map is stale

**Where to surface stale signal:**
1. `get_map` response — add `is_stale: true | false` and `stale_since: ISO timestamp` to the map record
2. UI — show a "Re-publish required" badge on the map header when `is_stale = true`
3. `invoke_map` — if map `is_stale`, include a warning in the response: `"warning": "Map has been edited since last publish. Execution is running against snapshot v{N}. Consider re-publishing."`

**Rules:**
- Stale does not block execution — the pinned snapshot is still valid
- Stale does surface a warning — users and agents must be aware
- Re-publish clears the stale flag and pins a new snapshot version

**Acceptance criteria:**
- `get_map` response includes `is_stale` and `stale_since` fields
- `invoke_map` includes a stale warning when applicable
- Re-publish clears `is_stale` by updating `automation_snapshot.compiled_at`
