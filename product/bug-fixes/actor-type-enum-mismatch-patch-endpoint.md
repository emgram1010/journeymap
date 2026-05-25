# Bug — actor_type Enum Mismatch on PATCH /journey_lens/actor_fields

**Date:** 2026-05-09  
**File affected:** `apis/journey_map/63_journey_lens_actor_fields_journey_lens_id_PATCH.xs`  
**Status:** Open

---

## Symptom

When creating an Internal Employee actor lens, the PATCH call fails with a 400 error:

```
Xano PATCH /journey_lens/actor_fields/{id} failed (400):
{"code":"ERROR_CODE_INPUT_ERROR","message":"Input \"internal\" is not one of the allowable values.","payload":{"param":"actor_type"}}
```

---

## Root Cause

The `actor_type` enum in the PATCH endpoint (`line 11`) defines a **stale, incomplete subset** of values:

```
["customer", "operations", "ai_agent", "dev", "custom"]
```

But the `journey_lens` table schema (`tables/8_journey_lens.xs`) defines the full valid set:

```
["customer", "internal", "engineering", "handoff", "vendor", "financial", "operations", "ai_agent", "dev", "custom", "metrics"]
```

`"internal"` (and several others) are valid at the DB level but blocked by the API endpoint's enum before the request ever reaches the database.

---

## Fix Required

Update the `actor_type` enum values in `63_journey_lens_actor_fields_journey_lens_id_PATCH.xs` to match the table schema:

```
["customer", "internal", "engineering", "handoff", "vendor", "financial", "operations", "ai_agent", "dev", "custom", "metrics"]
```

---

## Notes

- User entered correct data — this is purely a code bug, not user error.
- Any actor type not in that short list will hit the same 400 error until fixed.
