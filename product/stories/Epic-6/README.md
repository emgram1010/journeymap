# Epic-6 — Delete safety and data integrity

Started 2026-10-18, from a founder question rather than a planned initiative:

> *"If I delete an architecture or journey map, will it cause any issues — orphan records, in the Intelligence Layer module, or any other module, plan and/or execution?"*

The answer was yes, and it had already happened: 583 orphaned cells, 78 lenses, 55 stages, 3 versions, one plan and two templates pointing at maps that no longer exist. Both delete buttons are live in the UI today, behind a confirm that says nothing about what will be lost.

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [DEL-1 — Map & Architecture Delete Safety](EPIC-DEL-1-map-and-architecture-delete-safety.md) | A map in use can't be deleted; a deleted map takes its own content with it; its frozen versions never go, so live work keeps its instructions | To-do |

## Build order

`US-DEL-1-01` → `US-DEL-1-02` → `US-DEL-1-05` → `US-DEL-1-03` → `US-DEL-1-04`

Story 01 ships before 03, deliberately: once a map in use cannot be deleted at all, the only maps that can reach a cascade are ones nothing references.

## Needs a founder decision

| | Decision |
|---|---|
| **US-DEL-1-03** | Cascade (destroy the map's content with it) or soft-delete (hide, keep)? Recommendation and trade-offs are in the story. |
| **US-DEL-1-04** | Explicit approval to delete the ~719 existing orphan rows. Dry-run report first, on a clone. |

## The one thing not to break

`journey_map_version` is what stands between a deleted map and a broken job — a job reads its instructions from the frozen snapshot, not the live map. Execution is safe today **only because nothing has ever cleaned those versions up**, and nothing in the code says why they must survive. US-DEL-1-02 turns that accident into a rule with a guard behind it.
