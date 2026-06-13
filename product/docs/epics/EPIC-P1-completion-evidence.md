# EPIC P1-2: Completion Evidence Model

**PRD:** `product/docs/prd/PRD-runtime-engine.md`
**Priority:** P1 — strengthens `goal_met` check from string-match to structured proof
**Inspired by:** Telogis `FormInstance` (Saved/Submitted status, Values map, OpenTime/CloseTime)
**Also inspired by:** Telogis `Signature` table (CaptureTime, linked to JobId + DriverId)

---

## Problem

`stage_goal` is a text string. The runtime checks `completion_signal == stage_goal`.
This is a string comparison — brittle and unverifiable.

An operator sets `stage_goal = "photo_uploaded"`. The external system sends
`completion_signal = "photo_uploaded"`. The runtime returns `goal_met: true`.

But was a photo actually uploaded? The runtime has no way to know. Any caller can
send any string and pass the check. There is no evidence model — no way to prove a
goal was met with structured data.

For compliance-sensitive journeys (healthcare intake, field inspection, legal sign-off),
a string match is not proof. The platform needs a structured evidence record.

---

## Solution

Add optional `completion_evidence` to atomic stage cells and a corresponding
evidence record in the event log when stages complete.

Current code reality: stage completion outputs already live in `workflow_execution.stage_outputs`. Initial evidence can be stored there and mirrored to `event_log` using `action = "stage_completion_evidence"`. Do not create a dedicated evidence table unless compliance/audit volume requires it.

### Stage Cell Evidence Requirements

```json
{
  "evidence_required": true,
  "evidence_type":     "form | signature | checklist | signal | photo",
  "evidence_schema":   {
    "required_fields": ["tech_id", "cert_number", "photo_ref"]
  }
}
```

When `evidence_required: true`:
- `goal_met = true` only when evidence is present AND matches `evidence_type`
- Missing or wrong evidence type → `goal_met = false` even if signal string matches

### Evidence Record (written to event_log on stage completion)

```json
{
  "event_type":        "stage_completion_evidence",
  "journey_map_id":    42,
  "stage_key":         "s4",
  "external_ref_id":   "job-9981",
  "evidence_type":     "form",
  "evidence_ref":      "form-instance-7712",
  "submitted_at":      "2026-06-12T14:22:00Z",
  "submitted_by":      "tech-447",
  "field_values": {
    "tech_id":     "447",
    "cert_number": "TX-9981-B",
    "photo_ref":   "s3://bucket/photo-9981.jpg"
  },
  "open_duration":     8.5,
  "snapshot_version":  7
}
```

### Evidence Types

| Type | Description | `goal_met` condition |
|---|---|---|
| `signal` | Default — string match only (current behavior) | `completion_signal == stage_goal` |
| `form` | Structured field submission | `evidence_ref` present + required fields populated |
| `signature` | Digital sign-off (actor ID + timestamp) | `submitted_by` present + `submitted_at` within stage window |
| `checklist` | All checklist items marked complete | All items in `evidence_schema.required_fields` = `true` |
| `photo` | Image reference uploaded | `evidence_ref` is a non-null URI |

---

## User Stories

### US-1: Require a form submission to complete a stage
**As an** operator running a compliance inspection journey,
**I want to** require a form to be submitted at a specific stage so that
**`goal_met` is only true when the form is actually filled in.**

Acceptance:
- [ ] `evidence_required: true, evidence_type: "form"` accepted on stage cell
- [ ] Runtime returns `goal_met: false` if inbound event lacks `evidence_ref`
- [ ] Evidence record written to event_log when form evidence received
- [ ] `open_duration` captured (time actor spent filling the form)

### US-2: Require a signature to advance past a critical stage
**As an** operator running a service delivery journey,
**I want to** require customer sign-off at the delivery stage so that
**no stage can be marked complete without a signature.**

Acceptance:
- [ ] `evidence_type: "signature"` on stage cell
- [ ] Inbound event must include `submitted_by` (signer ID) and `submitted_at`
- [ ] Without signature data → `goal_met: false`, violation logged if `severity: critical`

### US-3: View evidence history for a completed journey instance
**As an** operator reviewing an audit trail,
**I want to** see all evidence records for a specific job instance so that
**I can prove compliance to an external auditor.**

Acceptance:
- [ ] `GET /event_log?external_ref_id=job-9981&event_type=stage_completion_evidence` returns all records
- [ ] Each record includes type, submitted_by, submitted_at, field_values
- [ ] Records are ordered by submitted_at ASC

---

## Backward Compatibility

- `evidence_required` defaults to `false` — all existing maps continue to work unchanged
- Existing `completion_signal` string match remains the default `goal_met` check
- Evidence model is opt-in per stage — operators upgrade stages selectively

---

## References

- `product/learnings/telogis-tde-architecture-analysis.md` — Section 3: FormInstance + Section 7: Signature
- `product/docs/prd/PRD-runtime-engine.md` — Parent PRD
- `product/docs/epics/EPIC-P0-violation-log.md` — Violation log (evidence failures write here)
- `emgram-skills/skills/atomic_runtime_template.md` — Readiness checklist (update goal_met check post-ship)
- `product/docs/architecture/RUNTIME-EVENT-CONTRACT.md` — Evidence payload extension point
