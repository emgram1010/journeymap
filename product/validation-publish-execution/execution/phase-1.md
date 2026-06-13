# Execution — Phase 1: Per-Stage Structured Output Schema

**Problem this phase solves:** The `workflow_execution` table exists and tracks run-level status — but `stage_outputs` is a free-form JSON blob. There is no enforced schema per stage entry. Two runs of the same map can produce completely different key names. The `execution_health` endpoint infers completion by checking whether `output` exists in a blob — not by reading a structured status field. You cannot build reliable per-stage analytics, gates, or audit trails on top of unstructured data.

**Goal:** Replace the free-form `stage_outputs` blob with a structured `per_stage_log` array. Each entry in the array has a defined, enforced schema with required fields: stage key, actor, status enum, timestamps, validation result, and skip reason. Every write to the log is append-only. The record is immutable after the run closes.

**Analogy:** This is the difference between a driver texting "I did the stops" and a TMS writing a timestamped, structured stop record for each delivery — with status, duration, exception notes, and signature captured.

**Exit condition for this phase:** Every new `workflow_execution` produces a `per_stage_log[]` with a structured entry per stage. `save_workflow_state` writes individual entries. `execution_health` reads from structured fields — not from blob inference.

---

## US-EXE-01 — Define the Per-Stage Log Entry Schema

**What:** Specify the canonical schema for a single stage log entry. This schema is the contract — all writers (AI agent tools, human inputs, orchestrator) must conform to it.

**Per-stage log entry schema:**
```json
{
  "stage_key": "s3",
  "stage_label": "Duration Reality Check",
  "actor": "ai_agent | human | hybrid",
  "status": "complete | blocked | delayed | skipped | novel_exception",
  "started_at": "ISO 8601 timestamp",
  "completed_at": "ISO 8601 timestamp",
  "duration_ms": 4200,
  "output_summary": "Confirmed 12-minute average duration from prospect. Variance flagged.",
  "validation_passed": true,
  "validated_by": "ai | human | both",
  "skip_reason": null,
  "novel_exception_flag": false,
  "novel_exception_description": null
}
```

**Field rules:**
- `status` is a required enum — no free-text status values
- `skip_reason` is required (non-null) when `status = skipped` or `status = blocked`
- `novel_exception_description` is required (non-null) when `novel_exception_flag = true`
- `validation_passed` is required — cannot be omitted or null for completed stages
- `output_summary` is limited to 500 characters — not a full transcript dump

**Acceptance criteria:**
- Schema documented and agreed before any backend work begins
- Schema is referenced in `save_workflow_state.xs` as the enforced input shape
- Any stage entry missing required fields is rejected — not silently accepted

---

## US-EXE-02 — Add per_stage_log and Assignment Fields to workflow_execution Table

**What:** Extend the `workflow_execution` Xano table with the fields needed to support structured per-stage logging and dispatch assignment.

**New fields to add:**
| Field | Type | Description |
|---|---|---|
| `per_stage_log` | JSON array | Array of per-stage log entries (schema from US-EXE-01) |
| `assigned_to_type` | enum | `ai_agent \| human \| hybrid` — who ran this execution |
| `assigned_to_id` | int (nullable) | User ID or agent ID — nullable for AI-only runs |
| `map_version` | int | `automation_snapshot.version` pinned at dispatch time |
| `gate_sign_in_passed_at` | timestamp | When Gate 1 (Sign In) passed — null if not yet reached |
| `gate_sign_out_passed_at` | timestamp | When Gate 3 (Sign Out) passed — null if not yet reached |

**Acceptance criteria:**
- All six fields added to `workflow_execution` table schema in Xano
- Existing records have null values for new fields — no migration of historical data required
- `per_stage_log` defaults to empty array `[]` on record creation

---

## US-EXE-03 — Update save_workflow_state to Write Structured Stage Entries

**What:** Update `save_workflow_state.xs` (and `ai/tool/save_workflow_state.xs`) to accept individual per-stage log entries and append them to `per_stage_log` — one entry at a time, in the order stages are completed.

**Write behavior:**
- Each call to `save_workflow_state` with a stage entry appends to `per_stage_log` — it does NOT overwrite the array
- Existing entries are immutable — a stage entry already written cannot be patched or updated
- If a stage key already exists in `per_stage_log`, the write is rejected with: "Stage [stage_key] already logged for this execution. Entries are immutable."
- The run is only marked `completed` when `gate_sign_out_passed_at` is written — not before

**Input extension for save_workflow_state:**
```
stage_entry? {
  stage_key: text
  actor: enum (ai_agent | human | hybrid)
  status: enum (complete | blocked | delayed | skipped | novel_exception)
  output_summary: text?
  validation_passed: bool
  validated_by: enum (ai | human | both)
  skip_reason: text?
  novel_exception_flag: bool?
  novel_exception_description: text?
}
```

**Acceptance criteria:**
- `save_workflow_state` accepts `stage_entry` input and appends to `per_stage_log`
- Duplicate stage key writes are rejected
- Existing `stage_outputs` blob is preserved for backward compatibility — new runs use `per_stage_log`
- `execution_health` endpoint is updated to read from `per_stage_log[].status` instead of blob inference
