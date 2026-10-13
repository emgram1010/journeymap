# OBS-1 — Observability: Heartbeat, Error Logging and Health Page

**Epic ID:** OBS-1
**Feature:** When anything succeeds or fails, it is recorded in plain terms, and the product manager can see what broke, who can fix it, and hand the AI everything it needs, without reading code.
**Status:** Planning
**Depends on:** — (build first; every other epic emits events through it)
**Goal:** Every important step records a **success** (the "heartbeat") or a **failure** with a stable error code, a correlation reference, and a plain-English explanation. A **Health page** shows system status, open problems and who can fix each. A **diagnostic bundle** (one click or one AI tool call) gives an engineer or the AI the full story.

---

## MVP scope (after review, 2026-10-12)

| In the MVP | Deferred (post-MVP) |
|---|---|
| US-OBS-1-01 event columns · 02 helper and correlation id · 03 error catalog · 04 client events · 05 heartbeat and daily audit · 07 Health page (admin-only, without Acknowledge) · bundle builder and **Copy** button from 08 · **new** 10 admin-only access · **new** 11 offline buffer for client diagnostics · **new** 12 correlation-id spike | 06 issue acknowledgement (and table 92) · the AI tool part of 08 · 09 retention tiers (MVP keeps the existing 90-day policy) |

Tests for deferred stories (FT-OBS-1-07, FT-OBS-1-09) run when those stories are built.

## Who this is for

The person supporting the product is a **product manager, not an engineer**. So:
- Problems are described in plain language, not stack traces.
- Every problem says **who can fix it**: the user, the product manager, or an engineer/AI.
- Every user-facing error carries a short **Reference** the user can quote (the correlation id).
- The AI gets the same facts in a structured bundle.

## Existing Architecture (reuse, do not duplicate)

- `static/tables/3_event_log.xs` — append-only user/telemetry log: `user_id`, `account_id`, `action`, `metadata`. Retention 90 days via `retention_policy` and the daily `prune_event_log` task. **There is no heartbeat table today.**
- `static/tables/73_retention_policy.xs` — configurable retention per table.
- `agent_tool_log`, `agent_turn_log` — AI chat diagnostics (separate purpose; untouched).
- Earlier observability work for the AI builder (`product/stories/ai-builder-reliability-observability-epic.md`) — different scope (AI build phases); reuse its vocabulary where helpful.

## Decision (default; confirm)

**Extend `event_log` additively** instead of creating a parallel "heartbeat" table: one place for success and failure events, one retention mechanism. The Health page presents it as the heartbeat. Alternative: a new `ops_event` table.

## Non-Goals

- No third-party monitoring service. No paging/SMS. No email digest in the MVP (future). No logging of personal or secret values.

---

## Conventions (used by every epic)

- **Event name:** `<EPIC>.<step>` in `action`, plus `outcome` (`success | rejected | failure`). Example: `PUB-1.publish_version` + `success`.
  - `success` = it worked (the heartbeat). `rejected` = the system correctly refused (validation, permission, readiness). `failure` = something broke unexpectedly.
- **Error code:** `E-<EPIC>-<NNN>` (for example `E-PUB-001`). Defined once in the **error catalog**.
- **Correlation id:** generated once per user action, passed from the app through the API and every function, stored on each event, and shown to the user as "Reference".
- **No sensitive data in events:** log ids and field *names*, never values of attributes, notes, emails, tokens or passwords.

---

## Stories

### US-OBS-1-01 — Extend `event_log` (additive)

**File:** `static/tables/3_event_log.xs`

New nullable columns: `severity` (info/warn/error), `outcome` (success/rejected/failure), `feature` text (epic code), `step` text, `entity_type` text, `entity_id` int, `correlation_id` text, `error_code` text, `message` text (plain English), `duration_ms` int.
New indexes: `(outcome, created_at desc)`, `(feature, created_at desc)`, `(correlation_id)`, `(entity_type, entity_id)`.

**Acceptance:** existing rows and writers are unaffected; new columns default to null; existing prune task still works.

### US-OBS-1-02 — Event helper and correlation id

**Files:** `functions/log_event.xs`, `webapp/protype-2/src/ops/logEvent.ts`

- Backend `log_event(feature, step, outcome, entity, error_code, message, duration_ms, correlation_id)` writes a row; it **never throws** (a logging failure must not break the user action; it falls back to a minimal row and increments a counter).
- Every API entry point creates or accepts a correlation id; every error response includes it.

**Acceptance:** helper tolerates missing optional inputs; a simulated logging failure does not fail the caller.

### US-OBS-1-03 — Error catalog (one source of truth)

**File:** `webapp/protype-2/src/ops/errorCatalog.json` (also read by the backend)

Each entry: `code`, `feature`, `user_message` (friendly, how to fix), `what_happened` (for the product manager), `likely_cause`, `owner` (`user | product_manager | engineer`), `severity`, `fix_hint`.

**Acceptance:** every code used anywhere exists in the catalog; every entry has all fields; messages contain no jargon or raw technical text.

### US-OBS-1-04 — Client events and global error capture

**Files:** `POST ops/event` endpoint; `webapp/protype-2/src/ops/globalErrorHandler.ts`

- The app reports failed requests, unhandled errors and notable successes (for example "performer tap saved") with the same shape.
- Rate-limited and de-duplicated so a broken screen cannot flood the log.

**Acceptance:** a forced front-end error produces one event with feature, error code and correlation id; floods are capped.

### US-OBS-1-05 — Heartbeat and daily integrity tasks

**Files:** `tasks/ops_heartbeat.xs` (every 5 minutes), `tasks/ops_integrity_audit.xs` (daily)

- Heartbeat writes `OPS.heartbeat` with: database reachable, time of the last successful publish version, last performer event, failures in the last 24 hours.
- Daily audit runs the GOV-1 integrity checks and writes one event with the result (success, or the count of findings).
- Health is computed from the latest heartbeat; a heartbeat older than 15 minutes is shown as **"No heartbeat"** (red).

**Acceptance:** tasks write events on success; a missed heartbeat is visible on the Health page.

### US-OBS-1-06 — Issue grouping and acknowledgement *(grouping in MVP; acknowledgement and table 92 deferred)*

**File:** `static/tables/92_ops_issue_ack.xs`

- Failures and rejections are **grouped on read** by `(feature, step, error_code)` into "issues" (nothing duplicated in storage).
- Table `ops_issue_ack`: `id`, `account_id`, `fingerprint`, `acknowledged_by`, `acknowledged_at`, `note`. A new failure after the acknowledgement time **reopens** the issue.

**Acceptance:** grouping is deterministic; acknowledging hides the issue until it happens again.

### US-OBS-1-07 — Health page (plain language)

**File:** `webapp/protype-2/src/health/HealthPage.tsx` (route `/health`)

- Top: status tile (green / amber / red from heartbeat and open issues), failures in 24 hours, open issues count.
- Issue list: plain-English title from the catalog, how many times, first and last seen, **who can fix it**, and the suggested fix.
- Drill-down: the full timeline for a correlation id or a job/plan/map (what happened, in order).
- Actions: **Copy diagnostic bundle**. (Acknowledge is deferred; see US-OBS-1-06.)
- Visible only to platform admins (US-OBS-1-10).

**Acceptance:** a non-technical user can read it without any code knowledge; each issue shows an owner and a next step.

### US-OBS-1-08 — Diagnostic bundle and AI tool *(bundle and Copy button in MVP; AI tool deferred)*

**Files:** `functions/build_diagnostic_bundle.xs`, `ai/tool/ops_diagnose.xs`

- Bundle for a correlation id or entity: catalog entry, the last N related events in order, involved entity ids and versions, app version, and the likely owner. **Redacted** (ids and field names only).
- Available as a **Copy for AI** button on the Health page and as a read-only AI tool, account-scoped.

**Acceptance:** bundle is structured, small, redacted, and tenant-safe.

### US-OBS-1-09 — Retention *(deferred; MVP keeps the existing 90-day policy)*

- Register rules in `retention_policy`: successes 30 days, rejections 90 days, **failures 365 days**. Update the prune task so it honours `outcome`.

**Acceptance:** after a prune run, old successes are gone and failures within a year remain.

### US-OBS-1-10 — Admin-only access (review finding F7)

- Add `user.is_platform_admin` (bool, default false; set manually for the founder).
- The Health page and every `ops/*` read endpoint require it. Customers never see it.
- System events (heartbeat, daily audit) carry no account; account events keep their `account_id` so they can be filtered.

**Acceptance:** non-admin calls are denied (`E-OBS-001`, logged); an admin sees system and account events.

### US-OBS-1-11 — Offline buffer for client diagnostics (review finding F17)

- When the app cannot reach the server, failed **diagnostic** events are kept in the browser (at most 50, at most 7 days) and sent when the connection returns.
- User actions are never replayed from this buffer, and it never holds sensitive values.

**Acceptance:** a failure that happened while offline appears on the Health page after reconnecting.

### US-OBS-1-12 — Correlation-id spike (review: unverified in Xano)

- Verify whether Xano middleware can attach a correlation id to every request and make it available to the stack. If yes, use it. If not, use an explicit optional `correlation_id` input on every endpoint, passed to every function.
- Either way, a test lists all phase-4 endpoints and fails if one does not return the Reference on errors.

**Acceptance:** decision recorded in this file; the endpoint test passes.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-OBS-1-01 | Unit | Catalog validator: every entry has all required fields | Pass |
| UT-OBS-1-02 | Unit | Scan source for `E-XXX-NNN` codes; each exists in the catalog | Pass (fails when a code is missing) |
| UT-OBS-1-03 | Unit | Catalog message lint: no stack-trace words, no raw codes in `user_message` | Pass |
| UT-OBS-1-04 | Unit | `fingerprint(feature, step, code)` stable and order-independent of other fields | Same input → same value |
| UT-OBS-1-05 | Unit | `redact(payload)` removes values of attributes, notes, emails, tokens; keeps ids and keys | Pass |
| UT-OBS-1-06 | Unit | `healthStatus(heartbeatAge, openIssues)` thresholds (≤15 min green, none → red) | Correct states |
| UT-OBS-1-07 | Unit | Client de-duplication and rate cap | Flood collapses to the cap |
| UT-OBS-1-08 | Unit | `groupIssues(events)` | Correct counts, first/last seen |
| FT-OBS-1-01 | Functional (`workflow_tests/25_observability.xs`) | Successful call to a sample endpoint | One `success` event with feature, step, duration |
| FT-OBS-1-02 | Functional | Rejected call (validation) | One `rejected` event with catalog code and correlation id; user gets the friendly message and Reference |
| FT-OBS-1-03 | Functional | Forced failure | One `failure` event; user message friendly; no stack trace in response |
| FT-OBS-1-04 | Functional | Logging failure simulated | Caller still succeeds |
| FT-OBS-1-05 | Functional | Heartbeat task | Writes event with expected fields |
| FT-OBS-1-06 | Functional | No heartbeat for 20 minutes | Health reports red |
| FT-OBS-1-07 | Functional | Acknowledge an issue, then new failure | Reopens |
| FT-OBS-1-08 | Functional | Diagnostic bundle for a correlation id | Ordered events; redacted; other account denied |
| FT-OBS-1-09 | Functional | Retention prune | Old successes removed; failures under 365 days kept |
| FT-OBS-1-10 | Functional | Existing `event_log` writers and prune task | Unchanged behaviour |
| FT-OBS-1-11 | Functional | Non-admin calls an `ops/*` endpoint | Denied; `rejected` event |
| FT-OBS-1-12 | Functional | Every phase-4 endpoint error response | Includes the Reference |
| UT-OBS-1-09 | Unit | Offline buffer: cap 50, expiry 7 days, no sensitive values | Pass |
| E2E-OBS-1-01 | UI | Seed one failure → Health page | Shows plain-English issue, owner, suggested fix |
| E2E-OBS-1-02 | UI | Click "Copy diagnostic bundle" | Clipboard contains structured, redacted text |
| E2E-OBS-1-03 | UI | Force a front-end error | Friendly message with Reference; event logged |

**Completion gate:** all pass; existing `event_log` behaviour intact; `workflow_tests/1–9` green.

## Test Results

**2026-10-12 — Sonnet 5 build pass.**

- **Unit tests (webapp/protype-2, `npm test`): 115/115 passing**, including 25 new tests across `errorCatalog`, `fingerprint`, `redact`, `healthStatus`, `groupIssues`, `clientEventBuffer` (dedup/rate gate + offline buffer). Full existing suite stays green.
- **Typecheck (`npm run lint`): clean** except one pre-existing error in `e2e/chat-session-crud.spec.ts` unrelated to this epic (confirmed present with these changes stashed).
- **Functional (`workflow_tests/25_observability.xs`) and UI (`e2e/health-page.spec.ts`): written, NOT run.** Both require the backend to actually be pushed to the live Xano workspace — ask before doing that.
- **Backend XanoScript files are hand-verified against the XanoScript docs and existing repo patterns** (table/function/query/task syntax, `db.transaction`, `function.run`, `try_catch`, `redis.*`, `security.create_uuid`), but **not executed against live Xano**. Two specific risk areas flagged in code comments: `array.group_by` with a composite key in `group_issues.xs` (untested combination), and the correlation-id approach (US-OBS-1-12 — no "middleware" construct found in the docs, so an explicit client-generated id + header is used instead; not yet verified as the best available option on a live workspace).
- **Scope changes made during the build** (all noted in-file): the daily integrity-audit task is deferred to GOV-1 (doesn't exist yet) — only the 5-minute heartbeat task was built. `planner_agent.user_id` dependency correctly comes from P3A-1, not duplicated here.
- **Not done:** issue acknowledgement (US-OBS-1-06, table 92), the AI diagnostic tool (part of US-OBS-1-08), retention-tier changes (US-OBS-1-09) — all explicitly deferred per the epic's MVP scope.

**Still needed before this epic can be marked complete:** push to a real Xano workspace (with explicit go-ahead), then run `workflow_tests/25_observability.xs` and `e2e/health-page.spec.ts` for real, and resolve the two flagged risk areas above.
