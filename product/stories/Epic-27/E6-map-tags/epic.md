# TAG-1 — Map tags and filtering

**Epic ID:** TAG-1 (E6 in the founder's list)
**Status:** 📋 Written, not built (2026-11-21).
**Size:** M
**Model:** Sonnet 5.5.
**Depends on:** nothing. Can run in parallel with any other epic in this folder.
**Read first:** `../README.md`.

---

## 1. Goal

**Pain:** 25 or more maps in one flat list, so every AI scans them all to find one.

**Win:** maps are found by area or by parent in one call.

## 2. What exists today (repo files, 2026-11-21; live not compared)

| Fact | Where |
|---|---|
| `journey_map.parent_map_id` exists; `map_level` is architecture / actor-journey / atomic | `static/tables/6_journey_map.xs` |
| `journey_map` has **no** tags column | same file |
| `list_maps` filters by business, intent, status and level; it cannot filter by parent, and does not return the parent | `ai/tool/list_maps.xs` |
| `list_maps` loads the caller's maps and filters in a loop; it is scoped by `journey/visible_map_ids` and the chat's business | same file |
| `search_maps` is described as searching "ai_summary + tags" on published maps. **Unknown** what "tags" means there | connector description; verify first |
| `clone_scenario` deep-copies stages, lenses and cells | `apis/journey_map/126_…scenarios_clone_POST.xs` |
| A published version has a content hash that must match the frontend | PUB-1, `pub/canonical_hash.xs` |
| Archived and deleted maps are hidden by a marker table | `static/tables/131_journey_map_deleted.xs` |

## 3. Rule

**A tag is a label on a map, not part of the map.** Adding or removing one never creates a
version, never touches a cell, and never changes a published hash. Tags belong to one account
and are matched without regard to upper or lower case.

## 4. Do not break

- `list_maps` with no new filters returns exactly what it does today (checked before and after).
- No column is added to `journey_map` (no `updateTableSchema` on a table with text filters).
- The published-version hash and snapshot do not include tags.
- No account sees another account's tags.

## 5. Non-goals

- Tag colours, nested tags, tag permissions.
- Tagging plans, jobs or businesses (the pattern can be reused later; do not build it now).
- Auto-tagging by AI without being asked.

## 6. First check (before story 01)

Find out what `search_maps` means by "tags". If maps or versions already carry tags somewhere
(for example generated at publish), **extend that**; do not add a second kind of tag. Record
the answer in section 2 and tell the founder before building.

## 7. Stories

| File | Story |
|---|---|
| `US-TAG-1-01-tag-maps.md` | Add and remove tags; one tag list per account |
| `US-TAG-1-02-filter-maps-by-tag-and-parent.md` | `list_maps` filters, and a `list_tags` tool |

## 8. Completion gate

- "ops" and "Ops" are one tag.
- Tagging a published map leaves its version count and hash unchanged.
- `list_maps` with no new filters: identical output before and after, on the real account.
- A second account sees none of the first account's tags.
- Existing suites green. Test Results filled in.

## 9. Test Results

_Not run. Nothing built yet._
