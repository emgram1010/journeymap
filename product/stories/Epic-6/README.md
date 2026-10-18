# Epic-6 — Delete safety and data integrity

Started 2026-10-18, from a founder question rather than a planned initiative:

> *"If I delete an architecture or journey map, will it cause any issues — orphan records, in the Intelligence Layer module, or any other module, plan and/or execution?"*

The answer was yes, and it had already happened: 583 orphaned cells, 78 lenses, 55 stages, 3 versions, one plan and two templates pointing at maps that no longer exist. Both delete buttons are live in the UI today, behind a confirm that says nothing about what will be lost.

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [DEL-1 — Map & Architecture Delete Safety](EPIC-DEL-1-map-and-architecture-delete-safety.md) | A map in use can't be deleted; a deleted map takes its own content with it; its frozen versions never go, so live work keeps its instructions | **01, 02, 03, 05 done** · 04 is a dry run; deleting the rows needs your go |

## Build order

~~`US-DEL-1-01`~~ → ~~`US-DEL-1-02`~~ → ~~`US-DEL-1-05`~~ → ~~`US-DEL-1-03`~~ → `US-DEL-1-04` *(dry run done)*

The first three shipped on 2026-10-18 and are verified live. **A map in use can no longer be deleted, from either the map delete or the architecture cascade.**

⚠️ **It came too late for one map.** "Quote Request Handling (test)" was deleted from the app at 03:29 UTC that morning, hours before the guard existed. Its 3 frozen versions survived, so the 3 jobs running from it still have their full instructions — which is exactly the argument US-DEL-1-02 makes. Details in the epic's Test Results.

Story 01 ships before 03, deliberately: once a map in use cannot be deleted at all, the only maps that can reach a cascade are ones nothing references.

## Needs a founder decision

| | Decision |
|---|---|
| ~~**US-DEL-1-03**~~ | ✅ Answered 2026-10-18: **cascade**. Built and verified. |
| **US-DEL-1-04** | The dry-run report is in the epic. Deleting the 719 rows is the one step still waiting on a go. All three dead links point at map 205 — recoverable from its frozen version if you want it back first. |

## The one thing not to break

`journey_map_version` is what stands between a deleted map and a broken job — a job reads its instructions from the frozen snapshot, not the live map. Execution is safe today **only because nothing has ever cleaned those versions up**, and nothing in the code says why they must survive. US-DEL-1-02 turns that accident into a rule with a guard behind it.
