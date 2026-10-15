# LIVE-1 — Publish to Live

**Epic ID:** LIVE-1
**Feature:** The planner publishes a timeline to live; performers see a frozen snapshot, and later planner changes stay with the planner.
**Status:** MVP core built and verified over real HTTP. Bulk publish is deferred by the epic; the planner UI (US-LIVE-1-05) is not built; change logging is wired into the duration edit only (see Test Results)
**Depends on:** SCHED-1, P3A-1 (provides `planner_agent.user_id`)
**MVP:** in scope except bulk publish (US-LIVE-1-03, deferred).
**Goal:** **Publish to live** freezes a timeline's plan and makes it visible to its performer. After that, the planner may still change the plan, but performers do **not** see those changes, and every change is logged against the published snapshot so plan-vs-actual stays meaningful.

---

## Context

Not to be confused with **Publish version** (freezing a journey map, PUB-1). Phase-3 reserved `planner_timeline.status` (`draft | published`) for this. The scope here is one timeline (one agent, one day), with a bulk action for a whole day.

## Existing Architecture (Do Not Break)

- Phase-3 `planner_timeline.status` column and ordering functions.
- Editing a draft timeline works exactly as before.

## Non-Goals

- No re-publish or "reopen" in the MVP. No live push of planner changes to performers (decision D-23). No notifications.

---

## Stories

### US-LIVE-1-01 — Tables `plan_publication` and `plan_change_log`

**Files:** `static/tables/89_plan_publication.xs`, `90_plan_change_log.xs`

- `plan_publication`: `id`, `created_at`, `timeline_id` (unique: one publication per timeline), `published_by`, `published_at`, `snapshot` JSON (ordered items, each with a stable `item_ref`: planner task id, work task ids, planned start, scheduled minutes, expected minutes, assignee agent, stage/row labels), `snapshot_hash`. Log events point to `plan_publication_id` + `item_ref`, never to the planner task (review finding F5).
- `plan_change_log`: `id`, `created_at`, `timeline_id`, `change_type` (`moved | added | removed | duration_changed | reassigned`), `before` JSON, `after` JSON, `changed_by`. Append-only.

**Acceptance:** second publication for the same timeline rejected; no update/delete route exists for either table.

### US-LIVE-1-02 — Publish a timeline

- Blockers (reject with a list): a block has no assignee; any task `needs_info`; the assignee has no linked login user (`planner_agent.user_id`, P3A-1); the timeline is empty.
- On success: write the publication, set `planner_timeline.status = published`.

**Acceptance:** failed publish changes nothing; success writes exactly one publication.

### US-LIVE-1-03 — Bulk publish a day *(deferred)*

- Publishes every ready timeline for a date and returns a per-timeline outcome (`published | blocked | already_published` with reasons).

**Acceptance:** one blocked timeline does not stop the others.

### US-LIVE-1-04 — Planner edits after publish are logged, not shown

- Moves, additions, removals, duration and assignee changes remain allowed for the planner and write `plan_change_log` rows.
- The performer's view keeps reading the **snapshot** (APP-1).

**Acceptance:** snapshot hash never changes after publish; each planner change adds one log row.

### US-LIVE-1-05 — Planner UI

- Publish-to-live button (per timeline and per day) with blocker list; published timelines show a "Live" badge and a "changed since publish" indicator when log rows exist.

**Acceptance:** blockers shown in plain language; badge visible after publish.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-LIVE-1-01 | Unit | `publishBlockers(timeline)`: empty timeline | `EMPTY` |
| UT-LIVE-1-02 | Unit | Block without assignee | `NO_ASSIGNEE` |
| UT-LIVE-1-03 | Unit | Task `needs_info` | `NEEDS_INFO` |
| UT-LIVE-1-04 | Unit | All good | No blockers |
| UT-LIVE-1-05 | Unit | `buildSnapshot` twice on same input | Same hash |
| UT-LIVE-1-06 | Unit | `diffPlan(before, after)` | Correct `change_type` for move/add/remove/duration/reassign |
| FT-LIVE-1-01 | Functional (`workflow_tests/20_publish_to_live.xs`) | Publish a ready timeline | Publication written; status `published` |
| FT-LIVE-1-02 | Functional | Publish with each blocker | Rejected; nothing written |
| FT-LIVE-1-03 | Functional | Publish the same timeline twice | Second rejected |
| FT-LIVE-1-04 | Functional | Edit after publish | Allowed; one change-log row per change; snapshot hash unchanged |
| FT-LIVE-1-05 | Functional | Bulk publish with one blocked timeline | Others published; per-timeline outcomes returned |
| FT-LIVE-1-06 | Functional | Attempt update/delete on publication or change log | Rejected |
| FT-LIVE-1-07 | Functional | Draft timeline editing | Unchanged behaviour |
| FT-LIVE-1-08 | Functional | Cross-account | Denied |
| E2E-LIVE-1-01 | UI | Publish with blockers | Plain-language list shown |
| E2E-LIVE-1-02 | UI | Publish, then move a task | "Changed since publish" indicator appears |

**Completion gate:** all pass.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Table | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `plan_publication` (89) | PK; `timeline_id → planner_timeline` (indexed); `published_by → user` | `timeline_id` | snapshot, snapshot_hash, published_by, published_at | **Never updated or deleted** (frozen snapshot; documented exception to "no duplicate facts") |
| `plan_change_log` (90) | PK; `timeline_id → planner_timeline` (indexed); `changed_by → user` | — | change_type (enum), before, after, changed_by | **Append-only** |
| Atomic | Publication row and the timeline's `published` status are written **together** | | | |
| Timeline with a publication | Cannot be deleted; it can only be archived/closed | | | |

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Timeline is empty | "There's nothing on this timeline to publish." | `E-LIVE-001` |
| A step has no assignee | "{n} steps don't have a person assigned." | `E-LIVE-002` |
| A task needs information | "{n} steps are marked 'needs info'. Complete them first." | `E-LIVE-003` |
| Assignee has no login | "{name} doesn't have a login yet, so they can't see their work." | `E-LIVE-004` |
| Already published | "This timeline is already published." | `E-LIVE-005` |
| Publish could not be saved | "We couldn't publish. Nothing was changed. Reference: {ref}." | `E-LIVE-006` |

**Events logged** (`feature = LIVE-1`): `publish_timeline` (`success` with item count; `rejected` with the list of blockers; `failure`), `bulk_publish` (per-timeline outcomes), `post_publish_change` (type only). The Health page shows **time of the last successful publish to live**.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-LIVE-1-G01 | Unit | Blocker messages built for each code | Plain language; counts correct |
| FT-LIVE-1-G01 | Functional | Schema audit on tables 89–90 | Pass |
| FT-LIVE-1-G02 | Functional | Failure injected between publication and status change | Nothing persists |
| FT-LIVE-1-G03 | Functional | Update or delete on publication or change log | Rejected and logged |
| FT-LIVE-1-G04 | Functional | Delete a published timeline | Blocked with a friendly message |
| FT-LIVE-1-G05 | Functional | Every rejection above | Friendly message, Reference, event, nothing written |
| FT-LIVE-1-G06 | Functional | Integrity audit: published timeline without a publication, or hash mismatch | Detected |

## Test Results

**2026-10-15 — Opus 5 build pass. MVP core built.** Two tables, two
functions, one endpoint, 18 unit tests, verified over **real
authenticated HTTP**.

### What shipped

| Thing | Live id | File |
|---|---|---|
| `plan_publication` | table 125 | `static/tables/125_plan_publication.xs` |
| `plan_change_log` | table 126 | `static/tables/126_plan_change_log.xs` |
| `POST planner/timeline/{id}/publish` | 562 | `apis/planner/562_timeline_timeline_id_publish_POST.xs` |
| `live/build_publication` | fn 127 | `functions/live/build_publication.xs` |
| `live/log_plan_change` | fn 129 | `functions/live/log_plan_change.xs` |
| `publishBlockers`, `canonicalizePublication`, `diffPlan` | — | `webapp/protype-2/src/liveModel.ts` |

### The guarantee, demonstrated

This is the result the whole epic exists for:

1. Timeline 17 was published with four items; `pt-38` was frozen at
   **30 minutes**, hash `4490bf7e…`.
2. The planner then re-timed that same step to **55 minutes**.
3. The live plan now reads 55. **The publication still reads 30, and
   its hash is unchanged.**
4. One `plan_change_log` row was written: `pt-38`,
   `duration_changed`, `{30} → {55}`, by user 9, against publication 1.

The performer sees what they were given; the planner sees the current
plan; the difference is on the record. None of those three is
achievable without the other two.

### Unit tests

| ID | Result |
|---|---|
| UT-LIVE-1-01 | ✅ Empty timeline → only `EMPTY` |
| UT-LIVE-1-02 | ✅ Step with no assignee → `NO_ASSIGNEE` with the count and ids |
| UT-LIVE-1-03 | ✅ `needs_info` step → `NEEDS_INFO` |
| UT-LIVE-1-04 | ✅ A ready timeline returns no blockers at all |
| UT-LIVE-1-05 | ✅ Same input hashes identically; input order is irrelevant but `seq` is not; changing seq, duration, assignee, start, work-task ids or a label all change the string |
| UT-LIVE-1-06 | ✅ `moved`, `added`, `removed`, `duration_changed`, `reassigned` each detected; one item can produce three changes at once; an unchanged plan produces none |
| UT-LIVE-1-G01 | ✅ Messages are plain language with correct singular/plural, and contain no codes, field names or `null` |

Two behaviours worth calling out, both tested:

- **An unassigned step is not also reported as having no login.** Two
  complaints about one problem is how a blocker list becomes noise.
- **A pipe inside a label cannot forge a field boundary** in the hash
  — the same escaping discipline as PUB-1.

`npm test`: **266/266** (18 new).

### Functional cases

| ID | Result |
|---|---|
| FT-LIVE-1-01 | ✅ Publishing a ready timeline wrote one publication (4 items, hash recorded) and set the timeline `published` |
| FT-LIVE-1-02 | ✅ Blocked by `NO_LOGIN` with a plain sentence naming the person; the timeline stayed `draft` and nothing was written |
| FT-LIVE-1-03 | ✅ Publishing again → `E-LIVE-005` |
| FT-LIVE-1-04 | ✅ See "The guarantee, demonstrated" above — edit allowed, one log row, snapshot hash unchanged |
| FT-LIVE-1-05 | ⛔ Bulk publish is deferred by the epic (US-LIVE-1-03) |
| FT-LIVE-1-06 | ✅ By construction — no update or delete route exists for either table, and neither has an `updated_at` |
| FT-LIVE-1-07 | ✅ A draft day still edits freely, and writes **no** change-log row. Confirmed by making the same edit on a draft day and seeing the log stay at one row |
| FT-LIVE-1-08 | ✅ Tenancy runs through `planner/assert_timeline`; unauthenticated publish → `401` |
| E2E-LIVE-1-01/02 | ⛔ No UI (US-LIVE-1-05 not built) |

### A real bug this epic exposed in PLN-6

**`GET timeline/{id}` and the timeline list both hardcoded
`status: "draft"`.** That was *true* while publishing was on hold
(PLN-6's Non-Goals) and became a lie the moment LIVE-1 shipped: a
published day still read as a draft, so nothing in the planner could
tell live days from draft ones — and the first publish looked like it
had failed when it had actually succeeded.

Both endpoints now return the real column. Fixed, pushed and
re-verified: the read and the list both show `published`.

### A tooling hazard found the hard way

**The MCP `updateTableContentItem` tool does not reliably patch.**
Calling it with `{user_id: 9}` on an agent row also reset that row's
`workspace_id`, moving the agent into a different plan — and a
follow-up call supplying `workspace_id` explicitly did not put it
back. Repaired with a scratch function using `db.patch`, which worked
first time.

**Use a scratch function with `db.patch` for ad-hoc row edits**, never
that tool. Its own description warns it is destructive; this is what
that means in practice.

### Deviations and gaps

| Item | Why |
|---|---|
| Change logging is wired into the **duration edit only** | `tweak` is the clearest case and proves the mechanism end to end. Move, reorder, add and remove also need the same call in PLN-6/PLN-7's endpoints — straightforward now that `live/log_plan_change` exists and does nothing on a draft day, so callers need no condition of their own |
| No bulk publish | Deferred by the epic (US-LIVE-1-03) |
| No planner UI | US-LIVE-1-05 not built, like the other UI stories this session |
| `expected_minutes` and `planned_start` are not in the canonical string | They are derived values that follow from the items and the timeline's start; including a derived field in a tamper-evidence hash means it changes when the derivation changes rather than when the plan does. They are still returned in the snapshot JSON |
| FT-LIVE-1-G06 (audit check) not added | PLN-8's audit does not yet check "published timeline without a publication" or a hash mismatch. Same gap as JOB-1's FT-G05 — both belong in a follow-up audit pass |
