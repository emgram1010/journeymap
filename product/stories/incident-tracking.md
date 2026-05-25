# Incident Tracking — Epic Suite

**Goal:** Enable any enterprise application to push exceptions into emgram via MCP or REST. emgram matches each exception to a known use-case flow (journey map), tracks incidence counts, derives the full actor and stage blast radius, and surfaces AI-generated resolution guidance — all without breaking the existing journey map UI.

---

## Architecture Overview

```
Enterprise App / Ticketing System
          ↓  POST /exception/ingest  (or MCP tool: log_exception)
   Exception Intake API
          ↓
   Pattern Fingerprint Engine
     ↓ match found          ↓ no match
  Increment incidence    Create new exception_pattern
  Follow existing flow   Map to journey stage
          ↓
   Actor Blast Radius (stage × lens)
          ↓
   metrics lens: error_rate ↑, stage_health ↓
   financial lens: revenue_at_risk updated
          ↓
   AI Resolution Engine → suggest_resolution
          ↓
   Return to calling app via MCP response
```

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Exception storage | New `exception_pattern` table + `exception_event` table | Separates the pattern (reusable) from each occurrence (time-series) |
| 2 | Pattern fingerprinting | Deterministic hash of `app_id + error_code + stage_key` | Cheap to compute, stable across occurrences, overridable by AI semantic match |
| 3 | Stage mapping | `stage_key` passed in intake payload OR AI infers from error context | Caller knows their domain best; AI fallback for generic payloads |
| 4 | Actor impact derivation | Query all lenses at the matched stage, return typed blast radius | Reuses existing lens/cell model — zero new schema needed for impact |
| 5 | stage_health write-back | MCP/AI writes to `metrics` lens cell via existing `update_actor_cell_fields` tool | Reuses locked/confirmed guards already in place |
| 6 | `change_source` extension | Add `"mcp"` to the existing enum | Frontend already renders per `change_source`; one new badge needed |
| 7 | MCP server location | `mcp_servers/` directory (already scaffolded) | Consistent with existing project structure |
| 8 | UI safety for MCP writes | `is_locked` + `status: "confirmed"` block all writes regardless of source | No special MCP bypass — same rules as AI agent writes |

---

## Vocabulary

| Term | Definition |
|---|---|
| **exception_pattern** | A reusable fingerprint for a class of exceptions (error code + app + stage) with a resolution and incidence count |
| **exception_event** | A single occurrence of an exception — time-stamped, linked to a pattern |
| **fingerprint** | Deterministic key derived from `app_id + error_code + stage_key` used to match new exceptions to known patterns |
| **blast radius** | The set of actors (lenses) and their field states at the impacted stage |
| **stage_health write-back** | The act of updating the `metrics` lens cell's `error_rate` and `stage_health` when an exception hits a stage |
| **MCP write** | A cell or lens update triggered by an MCP tool call, identified by `change_source: "mcp"` |
| **resolution** | AI-generated guidance stored on the pattern — reused for all future matching occurrences |

---

## Epic IT-1 — Exception Pattern Foundation (Data Model & Intake)

**Goal:** Create the data model and intake endpoint that receives exceptions from external systems.

---

### US-IT-01 — `exception_pattern` table

**As a** backend system
**I need** a table to store known exception fingerprints, their resolved flows, and incidence counts
**So that** repeat exceptions can be matched instantly without re-analysis.

**Table schema:**
```
exception_pattern {
  id                  int
  created_at          timestamp
  updated_at          date
  account_id          int → account
  journey_map         int → journey_map       // which map this pattern belongs to
  stage_key           text                    // which stage is impacted
  app_id              text                    // identifier for the source application
  error_code          text                    // error code / exception class
  fingerprint         text (unique index)     // hash of app_id + error_code + stage_key
  title               text                    // human-readable pattern label
  description         text                    // AI or human description of the pattern
  resolution          text                    // AI-generated or human-authored fix
  resolution_source   enum [ai, human]
  incidence_count     int  default=0
  last_seen_at        timestamp
  status              enum [open, resolved, monitoring]
}
```

**Acceptance criteria:**
- Table created with all fields above
- `fingerprint` has a unique btree index
- `incidence_count` defaults to 0
- `last_seen_at` is updated on every new occurrence
- `account_id` is required — patterns are account-scoped

---

### US-IT-02 — `exception_event` table

**As a** backend system
**I need** a time-series log of every individual exception occurrence
**So that** incidence history, trends, and actor impact snapshots are preserved per event.

**Table schema:**
```
exception_event {
  id                  int
  created_at          timestamp
  account_id          int → account
  pattern_id          int → exception_pattern
  journey_map         int → journey_map
  stage_key           text
  app_id              text
  error_code          text
  raw_payload         json      // full exception payload from the caller
  actor_blast_radius  json      // snapshot of impacted actors at time of event
  resolved_at         timestamp?
  resolution_applied  text?
}
```

**Acceptance criteria:**
- Every call to the intake API creates one `exception_event` row
- `actor_blast_radius` is populated at intake time from the current lens/cell state at `stage_key`
- `raw_payload` stores the full inbound JSON for debugging

---

### US-IT-03 — `POST /exception/ingest` intake API

**As an** enterprise application or ticketing system
**When I** send an exception payload to emgram
**I want** the system to fingerprint it, match or create a pattern, and return the resolution and actor impact immediately
**So that** my application gets actionable context in a single API call.

**Endpoint:** `POST /exception/ingest`
**Auth:** `account` API key (not user token — machine-to-machine)

**Input:**
```json
{
  "account_id": 42,
  "app_id": "checkout-service",
  "error_code": "PAYMENT_GATEWAY_TIMEOUT",
  "stage_key": "checkout",
  "journey_map_id": 7,
  "title": "Payment gateway timed out at checkout",
  "raw_payload": { "stack_trace": "...", "env": "production" }
}
```

**Response:**
```json
{
  "pattern_id": 12,
  "is_new_pattern": false,
  "incidence_count": 14,
  "resolution": "Retry with exponential backoff; escalate to infra on count > 10",
  "resolution_source": "ai",
  "stage_key": "checkout",
  "blast_radius": [
    { "actor_type": "customer", "friction_points": "no tracking visibility", "emotions": "frustrated" },
    { "actor_type": "financial", "revenue_at_risk": 12400 },
    { "actor_type": "metrics", "stage_health": 3.1, "error_rate": 0.18 }
  ],
  "event_id": 338
}
```

**Acceptance criteria:**
- Fingerprint computed as `sha256(app_id + "|" + error_code + "|" + stage_key)`
- If fingerprint matches existing pattern: increment `incidence_count`, update `last_seen_at`, return existing resolution
- If no match: create new `exception_pattern` with `status: open`, trigger AI resolution (async or sync)
- `blast_radius` is always computed fresh from current lens/cell state at `stage_key`
- `exception_event` row created on every call
- Returns HTTP 200 for known patterns, 201 for new patterns

---

### US-IT-04 — Pattern fingerprint function

**As a** backend system
**I need** a reusable function that generates a stable fingerprint from exception inputs
**So that** the same exception class always maps to the same pattern regardless of minor payload variations.

**Behavior:**
- Inputs: `app_id`, `error_code`, `stage_key`
- Output: SHA-256 hex string (truncated to 32 chars for readability)
- Strips whitespace and lowercases all inputs before hashing
- Returns the same fingerprint for `"PAYMENT_TIMEOUT"` and `"payment_timeout"` from the same app

**Acceptance criteria:**
- Function is a reusable Xano function (not inlined in the API)
- Deterministic — same inputs always produce the same output
- Used by both the intake API and the MCP `log_exception` tool

---

## Epic IT-2 — Pattern Matching & Self-Learning

**Goal:** The system improves over time — unknown exceptions become known, and the AI resolution compounds in value with every incident.

---

### US-IT-05 — Match exception to existing pattern

**As the** intake API
**When I** receive an exception
**I want** to query `exception_pattern` by fingerprint first
**So that** known exceptions are resolved instantly without AI invocation.

**Acceptance criteria:**
- Lookup is by `fingerprint` (indexed) — single DB read
- If match found: skip AI, return stored `resolution` immediately
- Match is account-scoped — patterns from other accounts are never returned
- Pattern `incidence_count` incremented atomically
- `last_seen_at` updated to `now`

---

### US-IT-06 — Create new pattern on no match

**As the** intake API
**When I** receive an exception with no matching fingerprint
**I want** to create a new `exception_pattern` record and queue AI resolution
**So that** the system self-learns and the pattern is available for all future occurrences.

**Acceptance criteria:**
- New pattern created with `status: open`, `incidence_count: 1`
- `title` defaults to `"{error_code} at {stage_key}"` if not provided in payload
- AI resolution is triggered (see US-IT-10)
- Response includes `is_new_pattern: true` and a `null` resolution until AI completes
- If AI resolution runs synchronously, `resolution` is populated in the same response

---

### US-IT-07 — Incidence trend tracking

**As a** platform operator
**I want** to query incidence counts and trends per pattern
**So that** I can identify which exceptions are recurring and prioritize fixes.

**Endpoint:** `GET /exception/patterns` (account-scoped)

**Response includes per pattern:**
- `incidence_count`
- `last_seen_at`
- `status`
- `stage_key` + `journey_map` title
- `resolution_source`

**Acceptance criteria:**
- Results sorted by `incidence_count DESC` by default
- Filterable by `status`, `stage_key`, `app_id`
- Returns 0 results (not 404) when no patterns exist for the account

---

## Epic IT-3 — Actor & Stage Impact Mapping

**Goal:** When an exception fires, emgram instantly derives which actors are impacted at the affected stage and updates live health metrics.

---

### US-IT-08 — Derive actor blast radius at intake

**As the** intake API
**When I** process an exception for a known `stage_key`
**I want** to query all lenses at that stage and return each actor's current field state
**So that** the calling system knows exactly who is impacted and how.

**Behavior:**
- Query all `journey_lens` records for the `journey_map_id`
- For each lens, query the `journey_cell` at `stage_key × lens_key`
- Return actor type + relevant `actor_fields` per cell
- Prioritize: `customer.friction_points`, `customer.emotions`, `financial.revenue_at_risk`, `metrics.stage_health`, `internal.handoff_dependencies`

**Acceptance criteria:**
- Blast radius included in every intake response
- Cells with no content return `null` fields (not omitted)
- Locked cells are included in blast radius (read-only — locking does not hide impact)
- Snapshot stored in `exception_event.actor_blast_radius`

---

### US-IT-09 — Stage health write-back on exception

**As the** incident tracking system
**When an** exception hits a stage
**I want** the `metrics` lens cell at that stage to have its `error_rate` incremented and `stage_health` recalculated
**So that** the journey map health score reflects real production incident data.

**Behavior:**
- After intake, check if a `metrics` actor lens exists on the journey map
- If yes: read current `error_rate` and `stage_health` from the cell at `stage_key`
- Increment `error_rate` (as a rate — capped at 1.0, decayed over time via a configurable window)
- Recalculate `stage_health` using the existing `infer_stage_metrics` logic
- Write back via `update_actor_cell_fields` with `change_source: "mcp"`

**Acceptance criteria:**
- Write is skipped if the metrics cell is `is_locked: true` — no exception
- Write is skipped if the metrics cell has `status: "confirmed"` — no exception
- `change_source` is set to `"mcp"` on all write-backs (see US-IT-15)
- If no metrics lens exists, write-back is silently skipped
- `stage_health` health label thresholds unchanged: ≥ 8 healthy, 5–7 at_risk, < 5 critical

---

### US-IT-10 — Financial impact update on exception

**As the** incident tracking system
**When an** exception hits a stage with a financial lens
**I want** `revenue_at_risk` to be updated based on incidence count and pattern severity
**So that** the financial lens reflects the real cost of recurring incidents.

**Behavior:**
- Read current `revenue_at_risk` from `financial` lens cell at `stage_key`
- Compute delta: `incidence_count × estimated_revenue_per_incident` (configurable per pattern or account default)
- Write updated value via `update_actor_cell_fields` with `change_source: "mcp"`

**Acceptance criteria:**
- Write respects `is_locked` and `status: "confirmed"` — skipped if either is set
- Delta computation uses `exception_pattern.incidence_count` (post-increment value)
- If `revenue_at_risk` was null, sets it to the delta value
- `change_source: "mcp"` always set on write

---

## Epic IT-4 — AI Resolution Engine

**Goal:** The AI agent analyzes each new exception pattern and generates a resolution that is stored, reused, and improved over time.

---

### US-IT-11 — `get_exception_context` tool

**As the** AI resolution agent
**I need** a tool to read the full context of an exception pattern
**So that** I can generate an informed resolution without hallucinating details.

**Tool:** `get_exception_context`

**Input:** `pattern_id`

**Response:**
```json
{
  "pattern": { "title", "error_code", "app_id", "stage_key", "incidence_count", "description" },
  "stage": { "label", "key", "display_order" },
  "blast_radius": [ ...actor impact objects... ],
  "recent_events": [ last 5 exception_event records ],
  "existing_resolution": "..." or null
}
```

**Acceptance criteria:**
- Tool is read-only — no writes
- `recent_events` limited to last 5 by `created_at DESC`
- Returns `null` fields gracefully when data is missing — never throws

---

### US-IT-12 — `suggest_resolution` tool

**As the** AI resolution agent
**I need** a tool to write an AI-generated resolution back to the exception pattern
**So that** the resolution is persisted and reused for all future matching occurrences.

**Tool:** `suggest_resolution`

**Input:**
- `pattern_id` (int)
- `resolution` (text) — the AI-authored fix/optimization
- `confidence` (decimal 0–1)

**Behavior:**
- PATCH `exception_pattern` with `resolution`, `resolution_source: "ai"`, `status: "monitoring"`
- Log to `agent_tool_log` with `tool_category: "write"`

**Acceptance criteria:**
- Resolution is only written if `confidence ≥ 0.6`
- If `confidence < 0.6`, pattern `status` stays `open` and resolution is not written
- Existing human-authored resolutions (`resolution_source: "human"`) are never overwritten by AI
- Tool trace logged with `input_summary: "Pattern {id}: {title}"`

---

### US-IT-13 — AI resolution triggered on new pattern

**As the** intake API
**When I** create a new `exception_pattern`
**I want** the AI resolution agent to be called automatically
**So that** a resolution is available as fast as possible without manual intervention.

**Behavior:**
- After creating the pattern, call the AI agent with `get_exception_context` + `suggest_resolution` tools
- If the AI call completes within the request timeout (10s): return resolution in the intake response
- If it exceeds timeout: return `resolution: null` in response; resolution written async

**Acceptance criteria:**
- AI agent uses `claude-sonnet-4-5` (consistent with existing agents)
- System prompt includes: pattern context, blast radius, stage health, financial impact
- Resolution is stored even if intake response already returned `null`
- AI is not re-invoked for existing patterns unless user explicitly requests re-analysis

---

## Epic IT-5 — MCP Server

**Goal:** Expose emgram's exception intelligence as a standard MCP server so any enterprise AI agent can call it natively.

---

### US-IT-14 — MCP `log_exception` tool definition

**As an** enterprise AI agent (e.g. Claude Desktop, Cursor, a custom GPT)
**I want** to call `log_exception` via MCP
**So that** I can report exceptions from any application without custom REST integration.

**File:** `mcp_servers/incident_tracking.xs`

**MCP tool name:** `log_exception`

**Input schema:**
```json
{
  "account_id": "integer, required",
  "app_id": "string, required — identifier for the source application",
  "error_code": "string, required — exception class or error code",
  "stage_key": "string, optional — journey stage key; AI infers if omitted",
  "journey_map_id": "integer, optional — scopes to a specific map",
  "title": "string, optional",
  "raw_payload": "object, optional — full exception payload"
}
```

**Output schema:** Same as `POST /exception/ingest` response

**Acceptance criteria:**
- MCP tool wraps the existing intake API — no duplicate logic
- Account scoped via API key in MCP auth header
- Tool description clearly explains: "Reports an exception to emgram. Returns pattern ID, incidence count, AI resolution, and actor blast radius."
- `stage_key` is optional — if omitted, AI infers from `error_code` and `raw_payload` context

---

### US-IT-15 — MCP `get_resolution` tool definition

**As an** enterprise AI agent
**I want** to retrieve the stored resolution for a known exception pattern
**So that** I can surface the fix to my users without re-triggering the full intake flow.

**MCP tool name:** `get_resolution`

**Input schema:**
```json
{
  "account_id": "integer, required",
  "pattern_id": "integer, optional",
  "fingerprint": "string, optional — alternative to pattern_id"
}
```

**Response:** `{ pattern_id, title, resolution, resolution_source, incidence_count, status, last_seen_at }`

**Acceptance criteria:**
- Either `pattern_id` or `fingerprint` must be provided
- Returns 404-equivalent MCP error if pattern not found for the account
- Does not trigger AI re-analysis — read-only

---

### US-IT-16 — MCP `get_incident_summary` tool definition

**As an** enterprise AI agent
**I want** to query all open patterns for an account
**So that** I can surface a health summary of which flows are most impacted.

**MCP tool name:** `get_incident_summary`

**Input schema:**
```json
{
  "account_id": "integer, required",
  "status": "string, optional — filter by open | resolved | monitoring",
  "limit": "integer, optional, default 10"
}
```

**Response:** Array of patterns sorted by `incidence_count DESC`, each with `stage_key`, `blast_radius` summary, `resolution`, `last_seen_at`

**Acceptance criteria:**
- Results are account-scoped — never cross-account leakage
- `blast_radius` is a summary (actor types + top field) — not the full snapshot
- Empty array returned (not error) when no patterns match

---

### US-IT-17 — MCP server auth & account scoping

**As a** platform operator
**I want** MCP tool calls to be authenticated per account
**So that** different enterprise customers cannot access each other's exception data.

**Behavior:**
- Each MCP request carries an `X-Account-Key` header (or Bearer token)
- Key is validated against the `account` table
- All queries are filtered by `account_id` derived from the key — never trust client-supplied `account_id` alone

**Acceptance criteria:**
- Invalid or missing key returns MCP protocol error with `code: "unauthorized"`
- Account key is separate from user auth tokens — designed for machine-to-machine use
- Key rotation does not require code changes (stored in `account` table)

---

## Epic IT-6 — UI Safety for MCP Writes

**Goal:** MCP-initiated cell writes must never corrupt the UI, override user-confirmed content, or bypass the existing lock model.

---

### US-IT-18 — Add `"mcp"` to `change_source` enum

**As the** data model
**I need** `change_source` to include `"mcp"` as a valid value
**So that** the frontend can distinguish MCP-originated writes from user and AI writes.

**Files:**
- `tables/9_journey_cell.xs` — add `"mcp"` to `change_source` enum
- `webapp/protype-2/src/types.ts` — update `CellChangeSource` type (currently `'user' | 'ai'`) to add `'mcp'`
- `webapp/protype-2/src/xano.ts` — update `XanoJourneyCell.change_source` type

**Acceptance criteria:**
- Enum becomes `["user", "ai", "mcp"]`
- No existing records are affected — `"mcp"` is additive only
- Frontend type updated — no TypeScript errors
- All existing `change_source === 'ai'` checks in the frontend still work (no regressions)

---

### US-IT-19 — MCP writes respect `is_locked` and `confirmed` guards

**As a** journey map author
**When I** lock a cell or mark it confirmed
**I want** MCP-triggered writes to be blocked at the API level
**So that** my verified data is never overwritten by automated exception tracking.

**Behavior:**
- All MCP write paths (stage_health write-back, financial update, actor_fields) call `update_actor_cell_fields`
- `update_actor_cell_fields` already skips `is_locked: true` and `status: "confirmed"` cells
- No new guard code needed — existing tool behavior covers this

**Acceptance criteria:**
- Attempting to write to a locked cell via MCP returns `{ applied: false, skip_reason: "locked" }`
- Attempting to write to a confirmed cell via MCP returns `{ applied: false, skip_reason: "confirmed" }`
- Skipped writes are logged in `agent_tool_log` with `output_summary: "Skipped — locked"` or `"Skipped — confirmed"`
- The intake API response includes a `skipped_writes` array listing cells that were not updated and why

---

### US-IT-20 — Frontend `change_source: "mcp"` badge

**As a** journey map viewer
**When I** see a cell that was last updated by an MCP exception write
**I want** a visual indicator distinguishing it from user edits and AI agent edits
**So that** I know the data came from automated incident tracking, not a conversation.

**Behavior:**
- Cells with `change_source: "mcp"` show a distinct badge (e.g. `⚡ Incident` in amber/orange)
- Existing badges: `AI` (blue/purple for `change_source: "ai"`), no badge for `change_source: "user"`
- Badge shown in the cell tile and in the cell detail panel

**Acceptance criteria:**
- Badge renders for `change_source === 'mcp'` — no badge for `'user'`, existing `AI` badge for `'ai'`
- Badge is purely cosmetic — does not affect cell editability
- Badge style does not break existing cell tile layout (no reflow)
- Cell detail panel shows: `Last updated by: Incident Tracking (MCP)` when `change_source: "mcp"`

---

### US-IT-21 — MCP write audit in `agent_tool_log`

**As a** platform operator
**I want** every MCP-triggered cell write to appear in `agent_tool_log`
**So that** there is a complete audit trail of what was written, when, and why.

**Behavior:**
- Every write from the intake API (stage_health, financial, actor_fields) logs to `agent_tool_log`
- `tool_name`: `"mcp_stage_health_writeback"` / `"mcp_financial_update"` / `"mcp_actor_fields_update"`
- `tool_category`: `"write"`
- `input_summary`: `"Pattern {id} — {stage_key} stage"`
- `output_summary`: `"Applied"` or `"Skipped — {reason}"`
- `conversation`: null (MCP writes are not conversation-scoped)
- `journey_map`: the impacted map ID

**Acceptance criteria:**
- Log entry created for every attempted write, applied or skipped
- Skipped entries include skip reason in `output_summary`
- `agent_tool_log` query endpoint `GET /journey_map/{id}/tool-logs` already returns these (no new endpoint needed)

---

### US-IT-22 — No MCP write during UI-active session guard

**As a** journey map author
**When I** am actively editing the map in the browser
**I want** MCP writes to still complete but be surfaced as a notification banner
**So that** I am aware of live exception data being written without my session being disrupted.

**Behavior:**
- MCP writes proceed regardless of whether a user session is active (no blocking)
- The frontend polling / realtime channel detects `change_source: "mcp"` on cell re-fetch
- A non-blocking toast notification appears: `"⚡ Incident data updated {N} cells from live exception tracking"`
- Notification dismisses after 5 seconds; does not interrupt any open cell detail panel

**Acceptance criteria:**
- Notification fires when cells are refreshed and one or more cells have `change_source: "mcp"` with `last_updated_at` newer than the previous fetch
- Notification does not fire on initial map load
- Clicking the notification does nothing (informational only — no nav)
- If the user has a cell detail panel open for an MCP-updated cell, the panel refreshes its displayed values in place

---

## Out of Scope (this epic suite)

- Multi-map exception routing (routing one exception to multiple journey maps simultaneously)
- Real-time WebSocket push of exception events to the frontend (polling model is sufficient for v1)
- Exception pattern merging / deduplication UI
- SLA breach alerting / PagerDuty/OpsGenie outbound webhooks
- Custom fingerprinting rules (regex-based override of the default hash)
- Public exception pattern library (cross-account sharing)

---

## Recommended Implementation Sequence

```
US-IT-01 (exception_pattern table) →
US-IT-02 (exception_event table) →
US-IT-04 (fingerprint function) →
US-IT-03 (intake API — pattern match + create) →
US-IT-05 / US-IT-06 (match / create logic) →
US-IT-07 (incidence trend endpoint) →
US-IT-08 (blast radius derivation) →
US-IT-18 (add "mcp" to change_source enum + frontend types) →
US-IT-09 (stage health write-back) →
US-IT-10 (financial impact update) →
US-IT-19 (lock / confirmed guard validation) →
US-IT-20 (MCP badge in UI) →
US-IT-21 (audit log) →
US-IT-22 (session notification banner) →
US-IT-11 / US-IT-12 / US-IT-13 (AI resolution engine) →
US-IT-14 / US-IT-15 / US-IT-16 / US-IT-17 (MCP server)
```

## Dependencies

- `tables/9_journey_cell.xs` `change_source` enum must be updated (US-IT-18) before any MCP write-back stories are implemented
- `tools/12_update_actor_cell_fields.xs` is the write path for all cell updates — no new write tool needed
- `tools/15_infer_stage_metrics.xs` is the read path for stage_health recalculation — reused in US-IT-09
- `apis/journey_map/80_journey_map_journey_map_id_tool_logs_GET.xs` already exposes `agent_tool_log` — no new endpoint needed for US-IT-21
- US-IT-18 (type changes in `types.ts` and `xano.ts`) must land before US-IT-20 (badge rendering) to avoid TypeScript errors
