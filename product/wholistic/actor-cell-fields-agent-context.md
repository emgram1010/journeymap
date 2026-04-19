# Holistic Fix Plan — Actor Cell Fields Agent Context

**Date:** 2026-04-18
**Related bug fix:** `product/bug-fixes/ai-agent-actor-cell-fields-not-populating.md`

---

## Problem Summary

The agent can write actor cell fields via `update_actor_cell_fields` but has no reliable way
to know the correct field key names at runtime, and no way to verify what it wrote. The hotfix
(adding a key reference table to the system prompt) unblocks the immediate bug but does not
address three deeper structural gaps.

---

## Gap 1 — Context injection shows labels, not keys

**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

The `## Cell Actor Fields — Current State` section injected into agent context shows:
```
Fields still to complete:
- AI Model / Agent
- Input Data
```

The agent needs `ai_model_agent` and `input_data` — not the human labels. If the system prompt
key table ever drifts from the actual schema, the agent will break again silently.

**Fix:** Change context injection to emit `key` alongside label for every actor field line:
```
- AI Model / Agent  [key: ai_model_agent]
- Input Data  [key: input_data]
```
This makes the correct key available at runtime, actor-type-agnostic, without relying on the
system prompt being up to date.

---

## Gap 2 — `get_map_state` and `get_slice` don't return `actor_fields` or `actor_type` on cells

**Files:** `tools/2_get_map_state.xs`, `tools/8_get_slice.xs`

The cell objects returned by both tools contain:
`{ id, stage_key, lens_key, content, status, is_locked, change_source }`

Missing: `actor_type` (from parent lens) and `actor_fields` (current field values).

This means:
- The agent cannot detect which cells are actor-typed without cross-referencing the lens list
- The agent cannot verify what was actually written after calling `update_actor_cell_fields`

**Fix:**
- `get_map_state` cells: add `actor_type` and `actor_fields` to each cell object
- `get_slice` cells: same — include when the parent lens has an `actor_type`

---

## Gap 3 — `update_actor_cell_fields` tool instructions don't list valid keys

**File:** `tools/12_update_actor_cell_fields.xs`

The tool's `instructions` block only shows a generic customer example:
```
{ emotions: "Anxious", entry_trigger: "Order confirmed" }
```

No reference to other actor types. The agent reads this at point-of-use — it's the most
impactful place to put the key reference.

**Fix:** Add a per-actor-type key table directly to the tool instructions block, mirroring
what was added to the system prompt in the hotfix.

---

## Gap 4 — No single source of truth for actor field keys

**Files:** `webapp/protype-2/src/constants.ts`, `tools/12_update_actor_cell_fields.xs`,
`agents/2_journey_map_assistant.xs`, `apis/journey_map/52_..._ai_message_POST.xs`

Field key lists are defined independently in each layer. A rename or addition in `constants.ts`
will not automatically propagate to the context injection or agent prompt.

**Fix (long-term):** Define actor field schemas in a single shared config or table record that
all layers reference. Scope TBD — likely a backend config table or a shared `.xs` constants file.

---

## Priority Order

| # | Fix | Files | Effort | Impact |
|---|---|---|---|---|
| 1 | ✅ Done — System prompt key reference | `agents/2_journey_map_assistant.xs` | Low | Unblocks bug |
| 2 | Context injection shows keys | `52_..._ai_message_POST.xs` | Low | Runtime resilience |
| 3 | Tool instructions list keys | `tools/12_update_actor_cell_fields.xs` | Low | Point-of-use clarity |
| 4 | `get_map_state` / `get_slice` return `actor_fields` | `tools/2_get_map_state.xs`, `tools/8_get_slice.xs` | Medium | Read/verify capability |
| 5 | Unified field key source of truth | Multiple | High | Long-term drift prevention |
