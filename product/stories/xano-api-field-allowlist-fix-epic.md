# Xano API Field Allowlist Fix — Epic

**Status:** Ready for Development
**Goal:** Ensure the three Xano PATCH endpoints that service L3 Atomic map data
actually persist the Intelligence Layer fields they receive — closing the gap where
`time_duration` and `cost_rate` were silently dropped by the server-side `input` block
allowlists before ever reaching the database.

---

## Why This Exists

The frontend (US-ATM-01 through US-ATM-04) now sends `time_duration_value`,
`time_duration_unit`, `cost_rate_value`, and `cost_rate_unit` to Xano.
The Xano API endpoints were never updated to declare these fields in their `input`
blocks, so the server strips them on arrival — they never reach the `db.patch` call.

This is a silent failure: the UI appears to save, the response returns 200, but the
values are never written to the database and leakage math produces no output.

**Root cause per endpoint:**

| Endpoint | File | Missing Fields |
|---|---|---|
| `PATCH /journey_cell/update/{id}` | `44_...PATCH.xs` | `time_duration_value`, `time_duration_unit` |
| `PATCH /journey_lens/actor_fields/{id}` | `63_...PATCH.xs` | `cost_rate_value`, `cost_rate_unit` |
| `PATCH /journey_map/settings/{id}` | `62_...PATCH.xs` | ✅ already correct — no fix needed |

---

## Scope

**In scope:**
- Add `time_duration_value` + `time_duration_unit` to `input` block of file `44`
- Add `time_duration_value` + `time_duration_unit` to `response` block of file `44`
- Add `cost_rate_value` + `cost_rate_unit` to `input` block of file `63`
- Add `cost_rate_value` + `cost_rate_unit` to `$allowed_fields` list of file `63`
- Push updated `.xs` files to Xano via CLI

**Out of scope:**
- Frontend changes (covered in atomic-map-ui-fields-epic.md)
- Leakage calculation logic (covered in leakage-analysis-epic.md)
- Any other endpoint not listed above

---

## User Stories

### US-FIX-01 — journey_cell PATCH accepts time_duration fields
**File:** `apis/journey_map/44_journey_cell_update_journey_cell_id_PATCH.xs`

**Problem:** `time_duration_value` and `time_duration_unit` are sent by the frontend
but stripped because they are absent from the `input` block. The `$input|pick:($raw_input|keys)`
pattern in the `db.patch` call only persists fields declared in `input`.

**Changes:**
1. Add to `input` block:
   ```
   decimal time_duration_value?
   enum time_duration_unit? { values = ["minutes", "hours", "days", "weeks"] }
   ```
2. Add to `response` block:
   ```
   time_duration_value : $journey_cell.time_duration_value
   time_duration_unit  : $journey_cell.time_duration_unit
   ```

**Acceptance Criteria:**
- PATCH request with `time_duration_value: 15, time_duration_unit: "minutes"` returns those values in the response
- Values are readable from `journey_cell` DB record after the call
- Existing fields (`content`, `status`, `is_locked`, `actor_fields`) continue to work unchanged
- Leakage math tool (`calculate_leakage`) reads non-null `time_duration_value` on at least one cell

---

### US-FIX-02 — journey_lens actor_fields PATCH accepts cost_rate fields
**File:** `apis/journey_map/63_journey_lens_actor_fields_journey_lens_id_PATCH.xs`

**Problem:** `cost_rate_value` and `cost_rate_unit` are absent from both the `input`
block and the explicit `$allowed_fields` list. The frontend currently bypasses this via
a raw `/journey_lens/{id}` PATCH, but this is fragile and inconsistent. The dedicated
endpoint should accept these fields natively.

**Changes:**
1. Add to `input` block:
   ```
   decimal cost_rate_value?
   enum cost_rate_unit? { values = ["per_minute", "per_hour", "per_day", "per_week", "per_event"] }
   ```
2. Add to `$allowed_fields` var:
   ```
   "cost_rate_value"
   "cost_rate_unit"
   ```

**Acceptance Criteria:**
- PATCH to `/actor_fields/{id}` with `cost_rate_value: 45.00, cost_rate_unit: "per_hour"` persists both fields
- Values are readable from `journey_lens` DB record after the call
- Raw PATCH bypass in `xano.ts` (`updateLensActorFields`) can be simplified to use the single endpoint
- Existing actor identity fields (`persona_description`, `primary_goal`, etc.) continue to work unchanged

---

### US-FIX-03 — Push updated endpoints to Xano and verify
**Trigger:** US-FIX-01 and US-FIX-02 are complete locally

**Steps:**
1. Run `xano workspace push` — confirm only files `44` and `63` appear in changeset
2. Verify no `Duplicate table name` errors in push output
3. In Xano UI: test PATCH on a real cell — confirm `time_duration_value` round-trips
4. In Xano UI: test PATCH on a real lens — confirm `cost_rate_value` round-trips
5. Run `calculate_leakage` MCP tool on a prepared L3 map — confirm no `incomplete_cells` for these fields

**Acceptance Criteria:**
- Push succeeds with 0 errors
- Both fields verified via Xano API explorer or live test
- `calculate_leakage` returns a non-null `per_event` cost when at least one cell + lens is populated

---

## Build Order

```
US-FIX-01   journey_cell PATCH input fix      (independent)
US-FIX-02   journey_lens actor_fields fix     (independent)
US-FIX-03   Push + verify                     (depends on FIX-01 and FIX-02)
```

---

## Relationship to Other Epics

| Epic | Relationship |
|---|---|
| `atomic-map-ui-fields-epic.md` | The UI sends these fields — this fix makes the server accept them |
| `leakage-analysis-epic.md` | Leakage math is blocked until these fields reach the DB |
| `intelligence-layer-epic.md` | MCP tools already write to these fields — this fixes the REST path |
