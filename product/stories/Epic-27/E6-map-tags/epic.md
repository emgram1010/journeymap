# TAG-1 — Map tags and filtering

**Epic ID:** TAG-1 (E6 in the founder's list)
**Status:** ✅ Built and verified live 2026-11-21. Gaps are listed in Test Results.
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

**Built and verified live 2026-11-21 (Fable 5.2).** Tests ran against the test account (13, map 261).

**First check (section 6):** `search_maps` reads `journey_map.tags`, a column that does not exist, so it
is always empty. No tag concept existed. Nothing to extend; the dead reference was left alone.

**What was built**
- Tables `map_tag` (168) and `journey_map_tag` (169), both with unique indexes.
- Functions `tags/tag_key` (419), `remove_from_map` (420), `add_to_map` (421), `rename_tag` (422),
  `delete_tag` (423), `copy_links` (424), `overview` (425).
- Tools `tag_map` (198), `untag_map` (199), `list_tags` (200); `list_maps` (54) gained `tag`,
  `parent_map_id`, `top_level_only`, and returns `tags` and `parent_map_id`.
- Endpoints `GET map_tags` (673), `POST map_tag_change` (674).
- Clone (tool 67, endpoint 126) copies tags; `journey/delete_map_cascade` (171) removes a map's tag links.
- App: tag chips and a tag filter on Your Journey Maps and on a business's map grid, with rename and delete.
- All three tools are in the connector and both copilots.

| Test | Result |
|---|---|
| T-TAG-01-1 add, list, remove | Pass (tool, live) |
| T-TAG-01-2 "Ops", " OPS " one tag | Pass: second add answered `already`, name stayed "Ops" |
| T-TAG-01-3 add twice | Pass (`already`, no error) |
| T-TAG-01-4 published map unchanged | Pass by design: no publish or snapshot code reads the tag tables (searched). **Not run as a publish-then-compare** |
| T-TAG-01-5 clone copies tags | Pass: clone 304 carried "Operations"; fixture deleted after |
| T-TAG-01-6 name rules, limits | Name rules pass (HTML refused, E-TAG-002). **20 and 200 limits not exercised live** |
| T-TAG-01-7 rename; rename onto an existing name | Pass: `merge_needed` first, `merged` with merge true, a map with both kept one |
| T-TAG-01-8 delete in use | `confirm_needed` returned with the count. **Confirmed delete not run** (the tag was left on map 261 for the screen check) |
| T-TAG-01-9 two parallel creates | **Not run.** The unique index is in place and the loser path re-reads |
| T-TAG-01-10 second account | Pass: account 2 listed 0 tags, could not tag map 193 from account 13 ("Not Found"), could not delete account 13's tag |
| T-TAG-01-11 AI near-match | Pass: "Ops team" returned `suggest`, created nothing; `create_new` then created it |
| T-TAG-02-1 no filters identical | Pass: 15 maps, same ids in the same order, only the two new fields added |
| T-TAG-02-2 tag filter any case | Pass ("OPS", "operations") |
| T-TAG-02-3 parent, top level | Pass: `top_level_only` 9 of 15; unknown parent 0 |
| T-TAG-02-4 combined filters | **Not run** |
| T-TAG-02-5 unknown tag | Pass (0, no error) |
| T-TAG-02-6 parent in another account | Pass by scope (unknown parent 0) |
| T-TAG-02-7 counts | Pass: counts matched the one tagged map |
| T-TAG-02-8 archived maps | **Not run** |
| T-TAG-02-9 second account | Pass |
| Unit tests | `tagModel.test.ts` 6 of 6 |

**Different from the stories**
- The tools call the gate as a plain write, like `label_map`; no approval type was added (a tag is a label).
- A person typing a tag is not asked "did you mean"; only AI callers get the near-match step.
- Tags sit on the map lists, not on a map settings screen.
- Same-day maps have no fixed order in `list_maps` (the date has no time part). That was already true.

**Left on the test account:** tag "Operations" on map 261.

