# Telogis TDE → emgram Architecture Learnings
> Source: api.telogis.com/documentation — full table scrape, June 2026
> Purpose: Identify features to borrow for emgram's constraint engine & runtime

---

## 1. Constraint Severity Model (Condition table)

**Telogis pattern:**
- `Condition.Severity` → enum: `Normal | Major | Critical`
- `Condition.IsEnabled` → toggle without deletion
- `Condition.TimeToTrigger` → grace period before alert fires (soft window)
- `Condition.Aggressive` → fires immediately vs waits for confirmation report
- `ScheduleStart/Stop/Inverted` arrays → time-window scoping per day-of-week

**emgram gap today:** `standing_constraints` is a single text blob, no severity.

**Borrow:** Replace `standing_constraints` with structured `stage_constraints[]`:
```json
{
  "rule": "Technician must hold active cert",
  "severity": "critical",       // critical=hard-block, major=warn+leakage, normal=log
  "time_to_trigger": 0,         // grace period in minutes before violation fires
  "schedule_window": null,      // optional time-of-day scope
  "failure_mode": "block|warn|log"
}
```

---

## 2. Alert as Violation Log (Alert table)

**Telogis pattern:**
- `Alert.TimeOn / TimeOff` → duration of violation
- `Alert.ConditionId` → FK back to the rule that fired
- `Alert.JobId / DriverId / UnitId` → scoped to specific execution context
- `Alert.TriggerValue` → the actual value that caused the breach

**emgram gap:** No structured violation record when `constraints_ok = false`.

**Borrow:** When a constraint fires at runtime, write a `constraint_violation` event:
- `stage_key`, `lens_key`, `constraint_rule`, `severity`, `time_on`, `time_off`, `trigger_value`
- Hard violations → block event ingestion; soft violations → log + add to leakage delta

---

## 3. FormInstance as Completion Evidence (FormInstance table)

**Telogis pattern:**
- Driver submits a form to prove job completion
- `FormInstance.Status` → `Saved | Submitted` (draft vs committed)
- `FormInstance.Values` → Map<field, value> — structured proof
- `OpenTime / CloseTime / OpenDuration` — how long the actor spent on it
- `InstanceHistoryId` — tracks all revisions of the same submission

**emgram gap:** `stage_goal` is text. There's no evidence model — no way to prove a goal was met with structured data.

**Borrow:** Add optional `completion_evidence` to atomic stage cells:
- `evidence_type`: `form | signature | checklist | signal`
- `evidence_ref`: external ID or payload
- `submitted_at`: timestamp
- Runtime check: `goal_met = true` only when evidence is present + matches expected type

---

## 4. Job Table as Stage Execution Record

**Telogis pattern:**
- `Job.ExpectedArrivalTime / ExpectedDepartureTime` → planned times
- `Job.ActualArrivalTime / ActualDepartureTime` → real times (auto-populated)
- `Job.JobStatus` → `OK | Late | Early | Missed` — auto-computed from gap
- `Job.JobTypeId` → classifies the stop (Delivery, Pickup, Depot, etc.)

**emgram parallel:** `planned_duration` vs `actual_duration` already exists — but no `stage_status` enum.

**Borrow:** Add computed `stage_status` to execution events:
- `on_time | late | early | missed | blocked`
- Auto-set by runtime engine from planned vs actual delta
- Feed directly into leakage math (late + blocked = leakage)

---

## 5. Shift & ShiftPattern as Actor Availability Constraints

**Telogis pattern:**
- `Shift` → defines start time, end time, mandatory breaks
- `ShiftPattern` → recurring weekly template (Mon-Fri 8-5, etc.)
- `Driver.ShiftPatternId` → actor is bound to a pattern
- `HosEvent` → tracks duty status: `OffDuty | Driving | OnDutyNotDriving`

**emgram gap:** No concept of actor availability windows as constraints.

**Borrow:** Add `availability_window` to actor lens identity:
- `shift_start / shift_end` per day
- Runtime check: stage execution outside window = soft violation (warn) or hard block (if HoS-style regulatory)
- `HosEvent` equivalent = actor state log across stages

---

## 6. Tag System as Actor Qualification Matching

**Telogis pattern:**
- Tags are keywords on Drivers, Units, and Sites
- Jobs can require specific tags (e.g., "CDL-A", "Forklift-Certified")
- Tags must pre-exist in the Tag table — they can't be created on-the-fly

**emgram gap:** No structured skill/qualification matching between actor and stage.

**Borrow:** Add `required_tags: Set<Text>` to stage definition and `actor_tags: Set<Text>` to actor lens.
- Runtime check: `actor_tags ⊇ required_tags` → if false, hard block or soft warn based on constraint severity

---

## 7. Signature as Stage Sign-Off

**Telogis pattern:**
- `Signature` table — captures a digital signature as proof of event
- Linked to `JobId` and `DriverId`
- Has `CaptureTime` and location

**emgram gap:** No sign-off/acknowledgement model for stage completion.

**Borrow:** Add optional `sign_off_required: bool` to stage contract.
- When true: stage cannot advance until `completion_evidence.evidence_type = signature`
- Maps to `goal_met` check in the runtime 4-check loop

---

## 8. VehicleCapacityLimit as Hard Cap Constraint

**Telogis pattern:**
- `VehicleCapacityLimit.AmountLimit` — absolute max; cannot be exceeded
- `CapacityMetric.LoadTime / UnloadTime` — time cost of the capacity operation

**emgram parallel:** `planned_duration` is a soft guide, not a hard cap.

**Borrow:** Add `max_duration` (hard ceiling) distinct from `planned_duration` (soft SLA):
- `planned_duration` exceeded → soft violation, leakage logged
- `max_duration` exceeded → hard block, stage execution rejected
- This gives the binary enforcement Telogis uses for capacity without abandoning SLA measurement

---

## Summary: Priority Feature Gaps to Address

| Priority | Feature | Source Inspiration | emgram Impact |
|---|---|---|---|
| 🔴 P0 | Constraint severity (hard/soft) | Condition.Severity | Replaces `standing_constraints` text blob |
| 🔴 P0 | Constraint violation log | Alert table | Structured runtime error record |
| 🟠 P1 | Stage status enum | Job.JobStatus | `on_time/late/missed/blocked` |
| 🟠 P1 | Completion evidence | FormInstance | Proves `goal_met` with structured data |
| 🟡 P2 | Actor qualification tags | Tag system | Skill-matching at stage assignment |
| 🟡 P2 | Max duration hard cap | VehicleCapacityLimit | Separates SLA from hard ceiling |
| 🟢 P3 | Availability windows | Shift/ShiftPattern | Actor time-of-day constraints |
| 🟢 P3 | Stage sign-off | Signature | Cryptographic stage completion proof |
