# Blueprint Execution & Receipt Architecture — Epic PRD

**Status:** Planning — Future State
**Goal:** Enable a published journey map (blueprint) to serve as a live operational template
where every execution generates a receipt, deviations route to pre-wired exception maps,
and unsupported exceptions are captured, pooled, and promoted to future blueprint versions.

---

## Why This Exists

The prospect use case (leakage analysis) is a **static** story — you analyze what's happening
and produce a 3-year cost number. The enterprise use case is **live** — the blueprint runs
continuously, every transaction is measured against it, and the system learns over time.

This is the difference between a route planning *report* and a route optimization *system*.
The report tells you what went wrong last month. The system catches it in real time, routes
to the right recovery path, and gets smarter with every run.

**The pattern, proven in logistics (Telogis):**
- Schedule = published blueprint (what should happen)
- Route execution = one run against the blueprint (what did happen)
- Route response = the receipt (actual vs planned, per stage)
- Alert = supported exception (pre-wired recovery path fires)
- Unknown deviation = unsupported exception (captured, pooled, promoted)

---

## Prospect Mode vs Enterprise Mode

This epic is explicitly the **enterprise** use case. The two modes share the same
blueprint structure but serve completely different purposes:

| | Prospect Mode | Enterprise Mode |
|---|---|---|
| **Purpose** | Find leakage, build 3-year close number | Run live operations against the blueprint |
| **Actuals source** | Prospect tells you verbally (discovery inputs on cell) | System records automatically per execution |
| **Receipt** | Not applicable — analysis only | `workflow_execution` + `execution_cell_record` per run |
| **Exception handling** | Discussed conceptually during discovery | Pre-wired exception maps fire in real time |
| **Epic** | Leakage Analysis (LA-1 through LA-7) | This epic (RE-1 through RE-5) |

**Do not build receipt recording for prospect discovery sessions.** Discovery actuals
are written directly to `journey_cell.actual_duration` by the AI agent during interview.
Receipt recording only applies when the blueprint is live and executing against real transactions.

---

## The Receipt Data Model

A receipt is not a single record — it is a **header + line items**, exactly like an invoice.

```
workflow_execution          ← RECEIPT HEADER
│  who triggered it
│  which blueprint + version
│  start → end timestamp
│  overall status (completed / failed)
│  stage_outputs (JSON summary per stage)
│  exception_context (if unmatched deviation fired)
│
└── execution_cell_record[] ← RECEIPT LINE ITEMS  (new — Epic RE-2)
       one per actor cell per stage per run
       actual_duration at this cell
       actual_value (output metric)
       deviation_flag (on-target / leakage / overperformed)
       exception_fired (bool)
```

The header tells you the transaction. The line items tell you exactly what happened
at every cell — who did what, how long it took, whether it deviated, what it cost.

**`workflow_execution` already exists. `execution_cell_record` is new.**
Every story in this epic either extends the header or builds the line items.

---

## What Already Exists (Do Not Re-Build)

| Capability | Where |
|---|---|
| Receipt header | `workflow_execution` table |
| Parent → child receipt linking | `workflow_execution.parent_execution_id` |
| Exception context capture | `workflow_execution.exception_context` (free-form JSON) |
| Originating cell + link type | `workflow_execution.originating_cell_id` + `.execution_link_type` |
| Stage output recording | `workflow_execution.stage_outputs` (JSON keyed by stage_key) |
| Basic execution health | `GET /journey_map/{id}/execution_health` |
| Exception map wiring | `journey_link` with type `exception` |
| Sub-journey invocation | `invoke_map` tool + endpoint |

---

## Priority Stack

```
🟡 HIGH   Epic-RE-1  Blueprint Versioning
🟡 HIGH   Epic-RE-2  Execution Cell Record (per-cell actuals per run)
🟡 HIGH   Epic-RE-3  Unsupported Exception Pool & Aggregation
🟢 MED    Epic-RE-4  Exception Frequency Threshold & Promotion Workflow
🟢 MED    Epic-RE-5  Receipt Aggregation & Intelligence Layer
```

---

## Epic RE-1 — Blueprint Versioning
**Without version tracking, optimization feedback has no memory.**

### Context
When an unsupported exception gets promoted to a supported exception, the blueprint changes.
Receipts generated before vs after that change need to be distinguishable. Otherwise you
cannot answer: "Did adding Exception Map D reduce unsupported exceptions by 30%?"

The existing journey settings `version` field is free text — not a formal integer version.
This epic adds a formal `blueprint_version` counter that increments on publish.

### US-RE-01-01 — Add `blueprint_version` to journey_map schema
**Layer:** `tables/6_journey_map.xs`
**Change:** `int blueprint_version? default=1` — increments on every publish
**Rule:** Increments automatically in publish endpoint. Never manually set by user.

### US-RE-01-02 — Stamp `blueprint_version` on workflow_execution at start
**Layer:** `tables/19_workflow_execution.xs`
**Change:** `int blueprint_version_snapshot?` — the version of the blueprint at execution start
**Purpose:** Enables comparison of receipts across blueprint versions

### US-RE-01-03 — Increment blueprint_version on publish
**Layer:** `apis/journey_map/journey_map_id/publish_POST.xs`
**Change:** On successful publish, increment `blueprint_version` by 1

**Acceptance Criteria — Epic RE-1:**
- Every published map has a numeric `blueprint_version`
- Every `workflow_execution` record stamps the version it ran against
- Version increment is automatic — no user action required

---

## Epic RE-2 — Execution Cell Record (Per-Cell Actuals Per Run)
**Stage outputs exist at the run level. This brings actuals to the cell level.**

### Context
`workflow_execution.stage_outputs` captures outputs per stage as a JSON blob.
For receipt-level intelligence, you need actual duration and outcome per actor cell per run —
not just per stage. This is the `execution_cell_record` table from Epic LA-6b,
promoted here as a prerequisite for receipt aggregation (RE-5).

### US-RE-02-01 — Create `execution_cell_record` table
**Layer:** New — `tables/execution_cell_record.xs`
**Fields:**
```
id                      int PK
workflow_execution_id   int FK → workflow_execution
journey_cell_id         int FK → journey_cell
blueprint_version       int — snapshot at time of run
actual_duration         decimal? — time actor spent at this cell
actual_value            decimal? — output metric value recorded
deviation_flag          enum { "on-target", "leakage", "overperformed" }
exception_fired         bool default=false
recorded_at             datetime
```

### US-RE-02-02 — Write execution_cell_record on stage completion
**Layer:** `apis/journey_map/journey_map_id/invoke_POST.xs`
**Change:** On each stage completion, write one record per actor cell in that stage
**Rule:** Blueprint (`journey_cell`) is never mutated. Only `execution_cell_record` is written.
**Guard:** Only fire when `workflow_execution.execution_mode` is enterprise (live run).
Never write execution_cell_records during prospect discovery sessions.

### US-RE-02-03 — Expose cell-level actuals in execution health endpoint
**Layer:** `GET /journey_map/{id}/execution_health`
**Change:** Add `cell_actuals[]` to response — avg actual_duration per cell across N runs

### US-RE-02-04 — Receipt retrieval endpoint (header + line items in one call)
**New:** `GET /journey_map/execution/{workflow_execution_id}/receipt`
**Purpose:** Return the full receipt for one run — header fields from `workflow_execution`
plus all `execution_cell_record` line items for that run, in stage order.
**Output:**
```json
{
  "receipt": {
    "execution_id": 99,
    "blueprint_id": 126,
    "blueprint_version": 3,
    "subject_label": "Acme Corp — Inquiry #1042",
    "started_at": "2026-06-04T09:15:00Z",
    "finished_at": "2026-06-04T09:47:00Z",
    "status": "completed",
    "total_actual_cost": 47.20,
    "exceptions_fired": ["supported: payment-failed", "unsupported: 1"]
  },
  "line_items": [
    {
      "stage_key": "s1", "stage_label": "Jesse Responds",
      "lens_key": "lens-1", "actor": "Jesse",
      "planned_duration": 5, "actual_duration": 25,
      "gap_minutes": 20, "gap_cost": 6.67,
      "deviation_flag": "leakage", "exception_fired": false
    }
  ]
}
```

**Acceptance Criteria — Epic RE-2:**
- One `execution_cell_record` per actor cell per stage per run
- Blueprint never touched by execution writes
- Cell-level actuals queryable by `workflow_execution_id` or by `journey_cell_id`
- Receipt endpoint returns header + line items in one call, in stage order
- Enterprise guard prevents writing receipts during discovery sessions

---

## Epic RE-3 — Unsupported Exception Pool & Aggregation
**Unknown deviations must be captured, not discarded.**

### Context
`workflow_execution.exception_context` already captures free-form exception data when
a run deviates from the happy path without a matching `journey_link`. This epic builds
the aggregation layer on top — so unsupported exceptions are pooled, counted, and surfaced
for blueprint review rather than silently buried in individual execution records.

### US-RE-03-01 — Create `unsupported_exception` table
**Layer:** New — `tables/unsupported_exception.xs`
**Fields:**
```
id                  int PK
journey_map_id      int FK → journey_map
blueprint_version   int — which version was running when this fired
stage_key           text — which stage deviated
actor_lens_key      text — which actor was involved
exception_summary   text — AI-generated one-line description of what happened
raw_context         json — full exception_context from workflow_execution
occurrence_count    int default=1 — increments when same pattern recurs
first_seen_at       datetime
last_seen_at        datetime
status              enum { "new", "under_review", "promoted", "dismissed" }
```

### US-RE-03-02 — Write to unsupported_exception on unmatched deviation
**Layer:** `apis/journey_map/journey_map_id/invoke_POST.xs`
**Change:** When deviation detected and no `journey_link` match found:
1. Check if identical pattern exists in `unsupported_exception` (same map + stage + actor)
2. If yes → increment `occurrence_count`, update `last_seen_at`
3. If no → create new record, AI generates `exception_summary`

### US-RE-03-03 — Unsupported exception pool endpoint
**New:** `GET /journey_map/{id}/exception_pool`
**Returns:** all `unsupported_exception` records for this map, sorted by `occurrence_count DESC`
**Purpose:** Shows blueprint owner which unknown deviations are most common

**Acceptance Criteria — Epic RE-3:**
- Every unmatched deviation creates or increments an unsupported_exception record
- Pool endpoint returns ranked list of unknown deviations
- Duplicate patterns increment count instead of creating new records

---

## Epic RE-4 — Exception Frequency Threshold & Promotion Workflow
**When an unsupported exception recurs enough times, it earns a blueprint entry.**

### Context
The unsupported exception pool is useful for review. But the real value is automation:
when a deviation fires enough times, the system should flag it for promotion and guide
the blueprint owner through creating a new exception sub-journey map to handle it.

### US-RE-04-01 — Add `exception_promotion_threshold` to journey_map
**Layer:** `tables/6_journey_map.xs`
**Change:** `int exception_promotion_threshold? default=5`
**Meaning:** When `unsupported_exception.occurrence_count` hits this number,
auto-flag the record as `status = "under_review"` and surface to blueprint owner

### US-RE-04-02 — Threshold check on exception write
**Layer:** `apis/journey_map/journey_map_id/invoke_POST.xs`
**Change:** After incrementing `occurrence_count`, compare to `exception_promotion_threshold`.
If threshold hit → set `status = "under_review"`, notify blueprint owner

### US-RE-04-03 — Promotion workflow: exception → new exception map
**Layer:** New endpoint `POST /journey_map/{id}/promote_exception`
**Input:** `unsupported_exception_id`, `new_map_title`
**Behavior:**
1. Create new journey map (the exception sub-journey) from the exception summary
2. Link it to the originating stage via `link_map` type `exception`
3. Publish the updated blueprint (increments `blueprint_version`)
4. Set `unsupported_exception.status = "promoted"`

**Acceptance Criteria — Epic RE-4:**
- Threshold is configurable per blueprint
- Promotion creates a real linked exception map in one action
- Blueprint version increments on promotion publish

---

## Epic RE-5 — Receipt Aggregation & Intelligence Layer
**Individual receipts are logs. Aggregated receipts are intelligence.**

### Context
The existing `execution_health` endpoint returns basic failure rates and common failure reasons.
This epic extends it with the full receipt intelligence: cost per run, actual vs planned gaps,
exception rates (supported vs unsupported), and blueprint version breakdowns — the data
that closes the loop from execution back to blueprint optimization.

### US-RE-05-01 — Enhance execution_health with cost and gap data
**Layer:** `GET /journey_map/{id}/execution_health`
**Add to response:**
```json
{
  "avg_actual_cost_per_run": 47.20,
  "avg_planned_cost_per_run": 33.00,
  "cost_gap_per_run": 14.20,
  "cost_gap_annual": 14768.00,
  "supported_exception_rate": 0.12,
  "unsupported_exception_rate": 0.08,
  "by_blueprint_version": [
    { "version": 1, "runs": 120, "avg_cost": 52.00, "unsupported_rate": 0.14 },
    { "version": 2, "runs": 80,  "avg_cost": 47.20, "unsupported_rate": 0.08 }
  ]
}
```

### US-RE-05-02 — Expose enhanced health via MCP tool
**Layer:** `mcp_servers/journey_map.xs`
**Tool name:** `get_execution_health`
**Purpose:** AI agent can surface receipt intelligence during prospect or optimization conversation

**Acceptance Criteria — Epic RE-5:**
- Cost gap between planned and actual surfaced per run and annualized
- Supported vs unsupported exception rates shown separately
- Blueprint version breakdown shows optimization impact over time

---

## Build Order

```
── Foundation ───────────────────────────────────────────────────────
US-RE-01-01,02,03   blueprint_version schema + publish increment + execution stamp
US-RE-02-01         execution_cell_record table schema
US-RE-02-02         write line items on stage completion (with enterprise guard)
US-RE-02-03         cell actuals in execution_health
US-RE-02-04         receipt endpoint (header + line items in one call)

── Exception Intelligence ──────────────────────────────────────────
US-RE-03-01,02      unsupported_exception table + write on unmatched deviation
US-RE-03-03         exception pool endpoint
US-RE-04-01,02      promotion threshold config + threshold check on write
US-RE-04-03         promotion workflow endpoint

── Receipt Intelligence ────────────────────────────────────────────
US-RE-05-01         enhanced execution_health with cost + gap + version breakdown
US-RE-05-02         MCP tool exposure
```

---

## Relationship to Other Epics

| Epic | Dependency |
|---|---|
| LA-6b (Execution Cell Record) | RE-2 supersedes LA-6b — same table, built here |
| LA-5 (Leakage Math API) | RE-5 uses LA-5 cost fields as inputs to gap calculation |
| IL-3 (Map Invocation Protocol) | RE-2 and RE-3 write records inside the invoke endpoint |
| IL-4 (Execution Health) | RE-5 extends the health endpoint built in IL-4 |
