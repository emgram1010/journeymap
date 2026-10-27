# Phase 7 — Exceptions: the happy path forks

> **Building this? Read [START-HERE.md](START-HERE.md) first.** It is the onboarding file for a
> fresh AI session: what this phase is, what is already settled, the build order, the hard limits,
> and the two traps that have already cost this project real time.

**Status:** EXC-1 built 2026-10-26 — waiting for founder review (see the epic's Test Results). Drafted 2026-10-25 after EST-1's Opus review pass closed phase-6.
**Source of truth for the design:** `product/emgramprd.md` §2 (three layers), §7.4 EX-5 / EX-7, §9 (variance signals), §10 (settled decisions). The item-specific parts lean on `product/learnings/item-rate-framework-prd.md` §8 (planning and execution hooks).
**Rule:** one epic = one feature. Every epic has unit (`UT-`), functional (`FT-`) and, where there is UI, Playwright (`E2E-`) tests, **plus a Governance section** and an **MVP scope** block. An epic is done only when its in-scope tests pass **and the existing suites stay green**.

## Goal

- A map can already say *when work leaves this journey, it goes to that map* (an `exception` link on a cell). Today that link is a picture. After this phase it does something.
- While doing the work, a performer can say *this part of the job is leaving the happy path* — and the system starts a **child job** on the linked map, pinned to that map's published version, tied back to the job and step it came from.
- The parent job keeps going. Nothing waits unless someone says so.
- Generic by design: a torn rental item going to a vendor, a failed delivery attempt, a lead that needs legal review, a return that needs a claim. Any work type, any stage, any linked map.

## The simple picture

```
WRITE ONCE (intelligence layer)              HAPPENS EVERY TIME (execution)

parent map                                   parent job #482
  … stage ─┐                                   … step in progress ─┐
           │ exception link                                        │ "send to <linked map>"
           ▼                                                       ▼
linked map (own stages, own version)         child job #482-A  (pinned to linked map vN)
  s1 → s2 → s3 → outcome A / outcome B         same stages; tagged "from #482 · <stage>"

MAP LAYER   parent map ──exception link──▶ linked map      (journey_link — exists)
JOB LAYER   job #482   ──parent_work_item_id──▶ job #482-A (column exists, never written — until now)
```

Vocabulary that must stay straight (it was the hard part in the design conversation):

| Word | Layer | Meaning |
|---|---|---|
| **Linked map** (exception / sub-journey) | Intelligence | The recipe for what happens off the happy path. Written once. |
| **Child job** | Plan + execution | One run of that recipe, started from one step of one parent job. Happens every time. |
| **Exception link** | Intelligence | Work *leaves* this journey here. Can spawn a child job. |
| **Sub-journey link** (from a method) | Intelligence | *How* to do this stage for these items. Informational; steps shown to the performer (EXE-M-1). Never spawns a job. |

## MVP build order

| # | Epic (feature) | Depends on | MVP delivers | Model |
|---|---|---|---|---|
| 1 | [EXC-1 Exceptions become child jobs](EPIC-EXC-1-exception-child-jobs.md) | phase-4 JOB-1, LOG-1, BLK-1; phase-6 EST-1 | Readiness warns when a linked map isn't published; one "send to linked map" action on a step (and on the job in the planner) that creates a child job, moves item counts when the job has them, records why, and shows the link both ways; Health **Exceptions** panel | Sonnet; **Opus** for the spawn transaction (US-03) and the review pass |
| — | PLN-M-1, EXE-M-1 | 1 | Already stubbed in [phase-6 QUEUED](../phase-6/QUEUED-planning-and-execution.md). EXE-M-1's *flagging* (counts handled in-house at a `per_flagged_unit` stage) is the sibling of this phase's *splitting* (counts that leave). Not authored here. | — |

**Model column:** the AI announces the model at the start of the epic and asks you to switch if needed (`/model sonnet`, `/model opus`). Any bug that fails twice → Opus. The spawn endpoint is a multi-table transaction that edits frozen lines on a live job — Opus writes that story, and an Opus review pass closes the epic.

## New tables

> **Numbers are a record, not a reservation.** Xano assigns ids on creation. Record the id Xano gives and name the local file after it.

| local # | Table | Epic | Notes |
|---|---|---|---|
| **140** (assigned 2026-10-26) | `work_item_exception` | EXC-1 | One row per spawn: parent job + step, child job, which link, why, which counts moved, who, source. Append-only history. **Ask the founder before pushing.** |

**Existing tables touched:** none structurally. `work_item.parent_work_item_id` (JOB-1, always `0` today) finally gets written. `work_item_line` rows on the parent are reduced/removed and created on the child — by this feature's endpoint only, inside one transaction, with EST-1's freeze rule (`E-EST-007`) deliberately bypassed for this one sanctioned writer and logged as such.

## What already exists (verified 2026-10-25 — reuse, do not rebuild)

| Piece | Where | State |
|---|---|---|
| Exception / anti-journey / sub-journey links on a cell | `journey_link` (table 14); picker in `App.tsx` (`cellLinkType`); "Parent Journey Context Strip" on the child map | Built |
| Links ride in the published snapshot | `functions/pub/build_map_snapshot.xs` → `snapshot.links[] {stage_key, lens_key, link_type, target_map_id}` | Built |
| Parent slot on a job | `work_item.parent_work_item_id` | Column exists; `554` writes `0` unconditionally (ISSUES-BACKLOG #19; BLK-1 "Still open") |
| Blocked + reason, one fixed list | LOG-1: `activity_log.reason_code` (`waiting_on_someone`, `missing_information`, `something_went_wrong`, `other`), endpoint `563` | Built (PRD EX-5) |
| Job created from a version, one task per cell | `554` + `jobs/tasks_from_version` | Built; needs extracting into a shared function so spawn and 554 are one implementation |
| Item counts on a job; estimate; refresh of untweaked slots | EST-1: `work_item_line`, `estimate/estimate_job`, `607`'s refresh section | Built; refresh logic to be hoisted into a function both 607 and the spawn can call |
| Machine hook for "when condition X, switch to linked map" | `stage_automation_config.exception_condition`, `linked_map_id` | Table exists, unused; **not** in this phase, but the spawn endpoint must be callable with `source = ai|system` so it can be wired later (PRD EX-9) |

## Existing, overlapping initiative

`product/validation-publish-execution/` is **not edited**. Its `BLOCKED` / `NOVEL_EXCEPTION` states (US-VAL-07/08, US-EXE-07/08) are AI-run outputs, deferred by D-39. This phase gives the *human* performer the equivalent action and leaves one endpoint for the AI path to call later. Same vocabulary (`blocked` + reason) — no second status list.

## Deferred (post-phase-7)

| Item | Why not now |
|---|---|
| Items **returning** to the parent order after the child finishes (re-merge lines) | Founder: "depends on the item." The child map's own last stage decides the outcome (back to stock / retire / charge). Returning to the *same parent order* is rare — covered by `blocked` + reason on the parent until then. |
| Automatic spawn from an AI/automation condition | Needs the AI run path (deferred D-39). Endpoint is ready for it. |
| Showing a method's sub-journey **steps** on a task | EXE-M-1 (how-to, not exception). |
| `flagged_quantity` writers (counts handled in-house) | EXE-M-1. Splitting (this phase) and flagging (EXE-M-1) must stay two different numbers. |
| Depth limit on child-of-child jobs | Allowed naturally (a child can spawn). Health counts depth; cap it only if it is ever abused. |
| Rolling child cost/time **up** into the parent | BLK-1 decision: two variances, reported side by side, never mixed. Revisit only with a measured need. |

## Governance in one page (applies to every epic)

| Area | Rule | Where it lives |
|---|---|---|
| Database | Primary keys, declared references, enums, cancel-never-delete for jobs, append-only exception history, `db.transaction` for multi-row writes, schema audit passes | GOV-1 standards |
| Input | The server always re-checks. Junk rejected with a plain message; the user's typing kept. Codes under `E-EXC-` in `errorCatalog.json` | VAL-1 rules |
| Visibility | Every spawn, rejection and failure logs an event with `feature = EXC-1` and a Reference. An unpublished linked map is a `warn` at readiness **and** a rejection at spawn time | OBS-1 |
| Support | Health page gains an **Exceptions** panel: open children by stage/reason/linked map; children whose parent was cancelled; linked maps that are unpublished | OBS-1 |

## Test conventions

- **Unit:** `node --test` + tsx in `webapp/protype-2/src/*.test.ts`; add each new file to `npm test`.
- **Functional:** Xano `workflow_test` files in `workflow_tests/`, numbered: EXC-1 = **33**. Workflow tests cannot be run from a session (CLAUDE.md); drive each assertion through `runWorkspaceFunction` and say so in Test Results.
- **UI:** Playwright specs in `webapp/protype-2/e2e/` — `exceptions.spec.ts`.
- **UI reachability:** every action button this phase adds needs one test that it is genuinely hittable, not just clickable by the driver. `.click()` scrolls the element into view and dispatches straight at it, so it passes on a button a person cannot press — which is exactly how ITEM-1 shipped an unusable Save (2026-10-25). See the boxed rule in EXC-1's Test Plan.
- **Golden fixtures:** `exception-split-golden.json` (parent lines + moved counts → parent-after + child lines, plus every rejection) shared by the backend and its TypeScript twin.
- **Regression gate:** `npm test`, `workflow_tests/1–32`, `33` once added, and existing e2e specs stay green.
- **Real data:** a **clone** of map **193** (`item-turnaround`) as the parent, plus a small published "repair" map in the same architecture as the linked map; a clone of **178** as the no-items parent (whole-job exception, no counts). Never the originals.

## If something breaks (for the product manager)

- Open `/health` → **Exceptions**. It lists every child job still open, which parent and step it came from, and why.
- "That map hasn't been published" when sending work to a linked map is **not** a bug. Open the linked map, publish a version, try again. Readiness warned about it earlier on the parent map.
- A child job is a normal job: it shows in the backlog, gets scheduled, gets done, has its own variance. Cancelling the parent does **not** cancel its children — Health flags them so you can decide.
- The parent's numbers shrink when counts move to a child. That is the point: Wash and Inventory stop estimating items that will never arrive. Tweaked slots keep the planner's number and raise a `warn`, exactly as EST-1 does.
