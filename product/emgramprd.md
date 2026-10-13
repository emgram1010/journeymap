# Emgram — Product Requirements Document

**Status:** Draft v0.3 · 2026-10-11 (all open questions resolved; MVP scope defined)
**Purpose of this document:** one self-contained source of truth. A new AI session (or a new teammate) should be able to read only this file and understand the vision, the reasoning, the decisions already made, the current state of the codebase, and what to do next — without the founder re-explaining.

---

## 0. Read this first (orientation for a new session)

### What this product is, in one paragraph

Emgram is a **generic planning-and-execution platform driven by a process definition**. A company describes *how a kind of work should go* (a **journey map**), then **plans** real jobs against it, **executes** them in an app that records what actually happened, and lets that record **improve the process** over time. It is **not** a logistics product, or a sales product, or any single-industry product. The founder's background is logistics, so many of the founder's examples come from it, but **every example is an illustration of a pattern, never a literal requirement.** The job of the AI is to extract the *spirit* of an example and express it in a form that works for **any** kind of work: sales, equipment processing, field service, intake, healthcare, manufacturing, and so on. **When reasoning, never assume trucks, drivers, addresses, routes or delivery windows are core.** They are optional attributes some work types declare.

### The loop

```
Define the process  →  Plan jobs against it  →  Publish to live  →  Execute & record
        ▲                                                                       │
        └────  AI reviews months of records, proposes a new version  ◄──────────┘
                (a human approves — FUTURE PHASE, not in the MVP)
```

### Where things stand (as of 2026-10-11)

| Area | State |
|---|---|
| Journey map product (build maps, stages × actors × cells, AI-assisted fill, links, publish) | **Exists** and is in use. Example map: id **178** `leads-to-sales-baseline` (8 stages, 7 lenses, 56 cells, 24 filled). |
| Planner frontend | **Exists** (`webapp/planningFrontendv2`, mounted in `webapp/protype-2` at `/planner`), but stores everything in `localStorage`. Branch: `planner-simplify-ui`. |
| Planner backend (phase 3) | **Planned, not built.** Epics `EPIC-PLN-1…9` in `product/stories/phase-3` (untracked in git). Table files `74_…79_` are reserved but do not exist yet. |
| MVP foundation epics (phase 4) | **Written and reviewed, not built.** 17 epic files plus a README in `product/stories/phase-4/`, each with an MVP-scope block, a Governance section and test cases (see §13). Revised 2026-10-12 after an independent review. `EPIC-LEAN-1` is deferred (its file is missing; the MVP uses existing cell fields). |
| Overlap with the earlier initiative | **Resolved** (D-39). See §8.6. |
| Execution module | **Does not exist.** Only an AI run engine (`workflow_execution`) exists, which is a different thing. |

### MVP scope (decided 2026-10-11)

**In the MVP (revised 2026-10-12 after review):** governance first (observability with an admin-only Health page, data-integrity standards, validation) → define a process using **existing** cell fields and a real stage owner → readiness gate and one immutable version → tiny plan template and plan instance → add jobs → schedule (one item per task), assign, tweak durations → **Publish to live** → performer app (connected; Done allowed without Start) → append-only activity log → per-task variance with outlier flags.

**MVP minimum the journey map must produce** (five fields; everything else is optional; all stored in **existing** fields):
- **Map:** work type name (`journey_map.title`, not empty or a default).
- **Each stage:** name, order, **owner** (`owner_lens_id`), a row whose "does planned work?" switch is on.
- **The owner's cell (and any other work cell the user starts):** **task** (`actor_fields.task_objective`) and **expected duration** (`time_duration_value` + unit). *Done when* (`actor_fields.success_criteria`) is optional.
- Added automatically, never typed: version, statuses, order.

**Not in the MVP (future phases, see §11 backlog):** role registry, lean-cell migration (LEAN-1), blocks and continuous stages, configurable completion rules, bulk publish, stale detection, stage aggregates, issue acknowledgement, AI diagnostic tool, AI-proposed process improvements, offline performer app, pause capture, per-work-type blocked reasons, structured tools list, capacity constraints, automated sequencing.

### Working agreements for the AI (how the founder likes to work)

- **Explain first, then write.** When asked to explain or review, explain in chat. Do not create or edit files until asked. Do not modify documents that weren't part of the request without asking; if you find a mistake in an earlier document, say so and ask before fixing it.
- **Lead with the decision / short answer.** Keep answers concise. High level first, detail only when asked.
- **Use first principles** and say which principle drives a recommendation.
- **The founder is ADHD/INTP-leaning**: chunked, scannable answers, tables, one clear question at a time, no walls of text, no re-litigating settled decisions (see §10).
- **Treat the founder's statements as direction, not gospel**: validate, refine, point out gaps, then ask clarifying questions.
- **Examples are illustrations, not literal.** When the founder gives an example (a delivery, a lead, a sofa), do not build for that example. Ask what pattern it demonstrates, then design the generic concept (e.g. "stairs" → a job attribute that may affect duration; "driver" → a performer holding a role). Use domain words only inside clearly labelled examples.
- **Never assume any one industry.** Test every idea against at least two unrelated work types before accepting it as generic.
- **Safety bias:** changes to existing tables are additive, flag-gated, with tests and rollback. Confirm before any destructive or outward-facing action (e.g. Xano schema pushes).
- **Tests are part of every epic** (unit tests plus workflow tests; existing suites must stay green).
- **The founder is a product manager and the support person, not an engineer.** Design everything to be diagnosable without reading code: plain-language errors, a Health page, error codes with an owner, and an AI-readable diagnostic bundle. Never ship a feature that can fail silently.
- **Verify what already exists before adding anything** (tables, fields, logging, tooling). Reuse and extend; do not duplicate.

---

## 1. Summary

### What we are building

A **business-process loop** on one platform:

1. **Define** — the *journey map* describes a work type: its stages, who does what at each stage, expected inputs/outputs/durations.
2. **Plan** — a *planner* turns real jobs into a schedule against that definition, from a reusable plan template.
3. **Execute** — performers (people now, AI agents later) work through the jobs in an app that shows stages and tasks and records status and timing as they go.
4. **Learn** *(future phase, not in the MVP)* — the accumulated record is analyzed (by AI, with human approval) to improve the definition, which then flows back into planning and execution.

### Why

- **Plans are guesses.** Planners schedule from memory and habit; nothing tells them whether expected durations are right.
- **Processes live in people's heads.** If a process isn't written down in a structured way it can't be planned against, measured, or improved.
- **Execution data is thrown away.** Even where work is tracked, the data rarely flows back to fix the process or the next plan.
- **People forget.** Anyone busy doing the work will not reliably *report* what went wrong. The system must **detect variance on its own** from actions people already take (start, finish, change status).

### The pitch

> Define the process once, plan and run real work against it, and let the recorded reality continuously improve the process.

---

## 2. Principles (first principles that govern every decision)

1. **Three layers, three verbs.** *Definition* (what should happen) → *Commitment* (what will happen, when, by whom) → *Record* (what happened). Each layer owns its own facts and never overwrites another's.
2. **Reference, don't copy.** Every downstream row points back to its journey cell. A fact is stored in exactly one place; anything derivable is derived, not stored.
3. **Structure only what is scheduled, counted, compared or gated.** Everything else stays text (insight).
4. **Snapshots over live links for anything in flight.** Work in progress is pinned to a published version; editing a map never changes it.
5. **Stages are dynamic; statuses are fixed.** Stages come from the work type. Statuses are identical everywhere: *not started, in progress, blocked, done, skipped*.
6. **The system detects variance; people don't report it.**
7. **The record is append-only.** Corrections are new events, never edits.
8. **AI proposes, humans approve.** Process changes arrive as a draft new version with evidence.
9. **Add, don't rewrite.** Changes to existing tables are additive and flag-gated, with a tested rollback.
10. **Core is generic; domain specifics are optional attributes.** Location, time windows, load and similar items are attributes a work type may declare, never assumptions of the core.
11. **Controlled vocabulary where machines must learn.** Enums, numbers and yes/no beat free text for anything the AI will analyze.
12. **The database is protected by the server, helped by the UI.** Every table follows relational standards (primary keys, declared and indexed references, unique natural keys, enums, explicit delete behaviour, append-only history, atomic writes). The UI validates for the user's benefit; the API always validates again. Junk is rejected with a friendly message and the user's typing is kept.
13. **Every important step leaves a trail.** Successes (the heartbeat) and failures are both recorded with a stable error code and a Reference the user can quote. Nothing fails silently.
14. **Supportable by a non-engineer.** The person supporting the product is a product manager. Problems are described in plain language, say who can fix them, and can be handed to an engineer or the AI as a clean, redacted diagnostic bundle.

---

## 3. Users

| User | Needs |
|---|---|
| **Process owner / analyst** | Build and version journey maps; see where the process leaks; approve AI-proposed improvements |
| **Planner** (whoever schedules the work: a dispatcher, a team lead, a coordinator) | Build plans from a template, add jobs, sequence them, tweak durations, publish to live |
| **Performer** (whoever does the work; an AI agent in future) | See what to do, when, and expected duration; mark progress with minimal taps |
| **Manager** | Plan vs. actual, exceptions, capacity, cost |

---

## 4. Core concepts (glossary)

| Term | Meaning |
|---|---|
| **Work type** | A kind of work. Each work type is one **journey map**. |
| **Journey map** | The process definition: stages (columns) × actors/lenses (rows). Each cell is a contract for one actor at one stage. |
| **Journey map version** | A frozen, published snapshot of a map. Live work pins to a version. |
| **Cell (lean core)** | `task`, `input`, `output`, `done_when`, duration (from existing columns), plus `friction` and `notes` text. See phase-4 LEAN-1. |
| **Actor role** | A role defined once ("Sales Coordinator", "Driver", "QA Inspector") that journey lenses and planner agents both reference. The planner assigns people or agents when building a plan; plan templates do not name roles or people. |
| **Job / work item** | One real instance of a work type (one order, one lead, one returned item). |
| **Job attributes** | Controlled key/values describing the job (e.g. item type, floors, priority). The map declares which attributes a job of that type may or must supply. |
| **Work task** | One job × one stage. Holds status only; its definition is read from the pinned version. |
| **Plan template** | A reusable calendar shape (e.g. a 2-week window, start times, defaults) that references journey-map versions. It does not name roles or people. |
| **Plan instance** | A **copy** of a plan template into which jobs are added and sequenced. |
| **Block** | A run of consecutive work tasks of one job, for the same role, that the process owner marked as continuous (see `continuous_with_previous`). Shown as one schedulable item. **Derived, not stored.** |
| **Publish to live** | Making a plan instance visible to performers so they can execute it. Distinct from **Publish version** (freezing a journey map). Use these two full labels in the UI and docs to avoid confusion. |
| **Activity log** | Append-only events recording what performers did and when. |
| **Variance** | The computed difference between expected, scheduled and actual. |

### The scheduling shape (generic core vs. optional attributes)

Any schedulable item exposes this to the planner:

| Core (always) | Optional (a work type may declare) |
|---|---|
| **Who** (role, then a person or agent) | Where (location) |
| **When** (planned start) | Time window |
| **How long** (duration) | Load / capacity used |
| **What must come first** (stage order) | Priority, item type, any domain attribute |

### Three durations, three owners

| Number | Owner | Can change? |
|---|---|---|
| **Expected** | Journey map (cell duration) | Only via a new version |
| **Scheduled** | Plan (the planner's per-job tweak) | By the planner, before and after publish to live |
| **Actual** | Execution log | Never edited; append-only |

---

## 5. Worked examples (same loop, different work types)

*These columns are illustrations only. None is special, and no requirement may depend on any of them. If a design works for one column but not the others, it is not generic.*

| | Last-mile logistics (example) | Leads to sales | Returned-equipment processing |
|---|---|---|---|
| Work type(s) | Delivery; Pickup/returns | Leads-to-sales | Return processing |
| Job | One order | One lead | One returned item/batch |
| Stages (dynamic) | Dispatch, Load, Drive, Drop-off, Confirm | Initial contact → … → Handoff to booking | Check, QA, Clean, Rack, Inventory |
| Roles | Dispatcher, Warehouse, Driver | Sales Coordinator, Customer | Receiver, QA, Cleaner, Stocker |
| Optional attributes | Address, window, stairs, item type | Channel, budget | Item type, condition |
| Continuous stages | Drive → Drop-off → Confirm (one stop) | none (days apart) | possibly Check → QA |
| Planner grouping | Delivery + pickup jobs into one route, manually | Follow-ups into a daily list | Batches by cleaning type |

A pickup stop's output can spawn a processing job (existing sub-journey/exception links).

---

## 6. The flow

```
 JOURNEY MAP                PLAN                         EXECUTION                 LEARN
 ───────────                ────                         ─────────                 ─────
 build map
 readiness gate ✔
 publish ► version v3 ─┐
                       ├─► plan template (references v3)
                       │      │ copy
                       │      ▼
                       │   plan instance ◄── add jobs (manual now; order system later)
                       │      │ jobs become work tasks (job × stage)
                       │      │ planner sequences, assigns roles→people, tweaks durations
                       │      │ continuous stages appear as one block
                       │      ▼
                       │   PUBLISH TO LIVE ─────►  performer app: today's items,
                       │                            expected duration, status
                       │                                   │ start / end / status
                       │                                   ▼
                       │                            activity log (append-only)
                       │                                   │
                       │                                   ▼
                       │                            variance computed automatically
                       │                            (expected vs scheduled vs actual)
                       │                                   │ weeks / months of data
                       │                                   ▼
                       └────────── new version ◄──── AI review → proposed changes
                                    (human approves)        → approve → publish v4
```

---

## 7. Requirements

Priority: **P0** = required for the first end-to-end loop · **P1** = soon after · **P2** = future.

### 7.1 Journey map — the process definition

| ID | Requirement | Pri |
|---|---|---|
| JM-1 | A map is a work type; stages, actors and cells are the process definition. | P0 |
| JM-2 | Cells use the lean core (task, input, output, done-when, duration, friction, notes). Existing text is preserved via additive migration. | P0 |
| JM-3 | Cell duration reuses the existing `time_duration_value`/`time_duration_unit`; one canonical minutes conversion. `actual_duration` on the cell is the *observed baseline*, distinct from execution actuals. | P0 |
| JM-4 | Each lens references an **actor role** registry entry. | P0 |
| JM-5 | Each stage has a real owner reference (replacing the text key) — **MVP**. An `exit_condition`, a configurable `completion_rule` and a `continuous_with_previous` flag come later (MVP rule: a stage is done when all its work tasks are done or skipped). | P0 (owner) / Future (rest) |
| JM-6 | The map declares the **job intake schema**: attributes a job of this type must or may supply, with controlled types (enum, number, yes/no, short text). | P1 |
| JM-7 | **Readiness gate** before publish: structure complete; flow coherent (each stage's output matches the next stage's input); numbers believable. Blockers stop publish; warnings can be overridden with a note. | P0 |
| JM-8 | **Publish** creates an immutable **version** snapshot; in-flight work stays pinned to its version. | P0 |
| JM-9 | A dry-run simulation (one synthetic job through every stage) is part of the gate. | P1 |
| JM-10 | **MVP minimum:** work type name; per stage a name, order and owner (a work-doing row); a task and expected duration on the **owner's cell and on any other work-doing cell the user has started**. Stored in existing fields (`task_objective`, `time_duration_*`; done-when in `success_criteria`). Everything else is optional. | P0 |
| JM-11 | **MVP readiness:** a stage is *ready* (green) when it has a name, an owner role, a task and a duration. All stages ready enables **Publish version**. The input/output hand-off check is added later. | P0 |
| JM-12 | **Required vs. freeform is visible in the UI.** Required fields live in place (map settings, stage header, cell panel) and use structured inputs: dropdowns, number-plus-unit pickers, short text. They carry a "Required" tag. Freeform content sits below under "Notes (optional)". Each stage shows a ready/not-ready mark, the map shows a progress line ("6 of 8 stages ready"), and a checklist panel lists exactly what is missing with jump links. Publish version is disabled until all stages are ready, with a reason shown. Customer-type rows show no required tags. | P0 |
| JM-13 | **MVP:** each journey-map row has a **"Does this row do planned work?"** switch, defaulting to Yes for Internal and AI Agent and No for every other type; a stage's owner must be a row with it on. **Later (ROLE-1):** a shared role registry picked from a list, with the switch moved onto the role. | P0 (switch) / Future (registry) |

### 7.2 Plan — commitment

| ID | Requirement | Pri |
|---|---|---|
| PL-1 | A plan template defines the planning window, start times and defaults, and references map versions. It does not name roles or people; the planner assigns people/agents while building the plan instance. | P0 |
| PL-2 | Creating a plan instance **copies** the template; later template edits never alter existing instances. | P0 |
| PL-3 | Jobs can be added manually (later by an external system through the same fields). Adding a job generates its work tasks from the pinned version. | P0 |
| PL-4 | A plan instance accepts jobs from **several work types**; the planner decides what to group (no automatic pooling in this phase). | P0 |
| PL-5 | **MVP:** the planner sequences jobs and assigns any active person; **each stage is its own scheduled item**. **Later:** continuous stages form one block, and assignment is suggested by role. | P0 / Future |
| PL-6 | Default scheduled duration = expected duration from the map. The planner may tweak it **per job only**, at **block** level, with an optional reason chosen from the job's attributes. | P0 |
| PL-7 | The planner enters job attributes manually. Each value records its **source** (manual now; external system later) and time entered. Attributes do **not** change durations automatically. | P0 |
| PL-8 | Soft warning (not a block) when a job needs a role no one in the plan has; jobs missing required attributes show `needs_info`. | P1 |
| PL-9 | Changes the planner makes after publish to live (move/add a job) are recorded against the published snapshot so plan-vs-actual stays meaningful. | P1 |
| PL-10 | Automated sequencing/optimization. | P2 |
| PL-11 | **Flow order:** (1) build the map and **Publish version**; (2) create a **plan template**, a tiny reusable shape (window, start times, which published map(s) it accepts) that *points to* map versions and copies no tasks; (3) create a **plan instance** from the template for a real period; (4) add jobs manually, and each job's tasks are generated from its pinned map version (pulled, never pushed); (5) sequence, assign, tweak; (6) **Publish to live**. | P0 |

### 7.3 Publish to live

| ID | Requirement | Pri |
|---|---|---|
| RL-1 | **Publish to live** freezes a snapshot of a plan instance and makes it visible to performers. It is a different action from **Publish version** (freezing a map) and carries a different label everywhere. | P0 |
| RL-2 | Changes the planner makes after publish to live are visible **only to the planner**. They are not pushed to performers, and they are logged as plan changes against the snapshot. | P0 |

### 7.4 Execution — record

| ID | Requirement | Pri |
|---|---|---|
| EX-1 | Performer app (web or mobile) shows assigned items: order, planned time, expected duration, status. | P0 |
| EX-2 | Performers change work-task status (not started, in progress, blocked, done, skipped). The status set is fixed for every work type (and will be used by AI runs too). **Done is allowed straight from Not started**; the start is then recorded as unknown and flagged. | P0 |
| EX-3 | Every work task has a **start time and end time** captured from the status actions the performer already takes. No separate reporting step. | P0 |
| EX-4 | Everything is written to an **append-only activity log** (who or which agent, what, when, source). Corrections are new events. | P0 |
| EX-5 | Moving to **Blocked** captures a reason from **one short fixed list shared by every work type** (one tap; e.g. waiting on someone, missing information, something went wrong, other), because exceptions are needed for learning. | P0 |
| EX-6 | A stage advances automatically when its `completion_rule` is satisfied. | P0 |
| EX-7 | Exceptions can start a linked sub-journey or exception journey (existing link types). | P1 |
| EX-8 | Offline operation with later sync. **Not in the MVP** — the MVP performer app requires a connection. | Future |
| EX-9 | AI agents as performers writing to the same log. | P2 |

### 7.5 Variance — computed, never self-reported

| ID | Requirement | Pri |
|---|---|---|
| VA-1 | **The performer does not report variance.** The system computes it from start/end times, status changes and the plan snapshot. | P0 |
| VA-2 | Per work task: actual duration (end − start; there is **no pause capture in the MVP**), start lateness vs. planned start, completion vs. window (when a window attribute exists). | P0 |
| VA-3 | Per stage: expected vs. actual. Per block: scheduled vs. actual. | P0 |
| VA-4 | Planner tweaks are stored (scheduled ≠ expected) and surfaced as variance signals ("jobs with attribute X routinely run +50%"). | P0 |
| VA-5 | Variance is queryable by job attributes, stage, role, work type and time range. | P1 |
| VA-6 | Attribute-related variance is **inferred** by comparing duration variance against job attributes. Performers are never asked to flag "declared vs. observed". | P1 |
| VA-7 | Work tasks whose elapsed time is unusually long versus expected are **flagged as outliers** for someone to explain, instead of being silently trusted (this replaces pause capture in the MVP). | P0 |

### 7.6 Learn — close the loop *(future phase — not in the MVP)*

The MVP captures the data that makes this possible (attributes, reasons, timestamps, planner tweaks) but does **not** build AI-proposed process improvements.

| ID | Requirement | Pri |
|---|---|---|
| LN-1 | After sufficient data (weeks to months), AI analyzes logs against the current map version and proposes **small, evidenced** changes (e.g. "stage 3 ran 40% over in 62 jobs; suggest 25 → 35 min"). | Future |
| LN-2 | AI may propose duration and description changes first. Adding/removing/reordering stages is a later, higher-bar capability. | Future |
| LN-3 | Proposals appear as a **draft new version**; a human approves, the gate runs, and the version is published. | Future |
| LN-4 | New versions flow into plan templates for *future* instances; in-flight and published-to-live work stays on its pinned version unless migrated explicitly. | Future |
| LN-5 | From attribute + duration data, AI derives candidate **duration modifiers** (e.g. attribute X adds 10 min, item type Y ×1.5) for planner review. | Future |

### 7.7 Governance — data integrity, validation, observability

| ID | Requirement | Pri |
|---|---|---|
| GV-1 | Every new table has a primary key, `created_at`, declared and indexed references, unique natural keys, enums for finite sets, and a documented delete behaviour (restrict, cascade or archive). A schema audit in the test run fails on a non-compliant new table. | P0 |
| GV-2 | Facts are stored once and referenced. Immutable snapshots (map version, plan publication) are the only documented exception. | P0 |
| GV-3 | Append-only tables (activity log, plan change log, plan publication, map version) have no update or delete path. | P0 |
| GV-4 | Multi-row operations (publish version, add job, record event, publish to live, create instance) are atomic. Failure leaves no partial data. | P0 |
| GV-5 | Edits detect concurrent changes and refuse to overwrite ("someone else changed this"). | P0 |
| GV-6 | A scheduled integrity audit finds orphans and mismatches (for example a task whose log disagrees with its status) and reports them as issues. | P0 |
| GV-7 | Tenant isolation: every endpoint checks account ownership through shared guard functions. | P0 |
| VL-1 | A shared field-rules registry is applied in the UI and again on the server. Junk (empty, whitespace-only, over-length, HTML, control characters, invalid numbers/dates/enums, duplicates, dangling references) is rejected before it is stored. | P0 |
| VL-2 | Rejections return a standard shape (code, field, friendly message, Reference) and keep the user's input in the form. No stack traces or internal names reach users. | P0 |
| OB-1 | Every important step records an event: **success** (the heartbeat), **rejected** (correctly refused) or **failure** (unexpected). Events carry feature, step, entity, duration, error code and a correlation Reference. Existing `event_log` is extended; no parallel table. | P0 |
| OB-2 | One **error catalog** defines every error code: friendly message, what happened, likely cause, **who can fix it** (user / product manager / engineer), and a fix hint. | P0 |
| OB-3 | A **Health page** shows system status, failures, open issues in plain language with owner and suggested fix, a timeline by Reference or job, and Acknowledge. | P0 |
| OB-4 | A scheduled **heartbeat** (every 5 minutes) and daily integrity audit write events; a missing heartbeat turns the page red. | P0 |
| OB-5 | A redacted **diagnostic bundle** is available as a Copy button and as a read-only AI tool. It contains ids and field names, never attribute values, notes, emails or tokens. | P0 |
| OB-6 | Retention: successes 30 days, rejections 90 days, failures 365 days. | P1 |

---

## 8. Data architecture

### 8.1 What exists today (verified in the repo, `static/tables/`)

| Table | Notes |
|---|---|
| `journey_architecture` (13) | Groups related maps. |
| `journey_map` (6) | `title`, `status` (draft/active/archived), `map_level` (architecture/actor-journey/atomic), `parent_map_id`, `journey_architecture`, `version` (**text only, no snapshot history**), settings text fields (intent, scope, start/end point, success metrics, …), `account_id`, `owner_user`. |
| `journey_stage` (7) | `journey_map`, `key` (stable), `label`, `display_order`, `stage_goal`, `primary_actor_lens` (**a text key, e.g. "lens-3", not a foreign key**). |
| `journey_lens` (8) | An actor row: `key`, `label`, `actor_type` (customer, internal, engineering, handoff, vendor, financial, operations, ai_agent, dev, custom, metrics), `template_key` (e.g. `internal-v1`), `role_prompt`, `persona_description`, `primary_goal`, `standing_constraints`, `agent_map_id`, `cost_rate_value`/`cost_rate_unit`. Map-local; no shared role registry. |
| `journey_cell` (9) | Unique on (map, stage, lens). `content`, `status` (open/draft/confirmed), `is_locked`, `change_source`, **`actor_fields` JSON (≈9–12 text keys per actor template)**, **`time_duration_value` + `time_duration_unit`** (planned effort, used by the leakage formula), `planned_duration`, **`actual_duration`** (an *observed baseline*, not an execution actual). |
| `journey_link` (14) | Cell → map link; types `exception`, `anti_journey`, `sub_journey`. |
| `stage_automation_config` (31) | Machine-executable config per stage (trigger_type, action_type, exception_condition, linked map, status draft/confirmed/disabled). |
| `automation_snapshot` (30) | One compiled automation graph per map, upserted on publish. **Not immutable history.** |
| `workflow_execution` (19) | An **AI orchestrator run** of a map: `subject_label`, `execution_mode`, `status`, `current_stage_key`, `stage_outputs` JSON, parent/child runs for linked maps. Stage-level, conversation-bound; **not** a task-level execution record. |
| Publish endpoint | `apis/journey_map/201_journey_map_journey_map_id_publish_POST.xs`: sets `status="active"`, compiles the automation snapshot, pushes to webhooks. **No readiness gate and no version snapshot.** |

### 8.2 Planner (phase 3, planned, not built)

`planner_settings`, `planner_model`, `planner_workspace`, `planner_agent` (kind person/ai), `planner_timeline` (one per agent per day), `planner_task` (nullable `timeline_id` = backlog; `duration_minutes`; `status` planned/needs_info). Reserved table numbers **74–79**. Planned start times are **derived**, not stored. Details: `product/stories/phase-3/README.md`. **Coordination notes (phase-4 epics):** a block can cover several work tasks, so linking uses a join table `planner_task_work_task` (SCHED-1) rather than a single `planner_task.work_task_id`; `planner_task.title` becomes nullable when linked and `planner_task.tweak_reason` is added; `planner_agent.user_id` (nullable) lets a performer log in (APP-1); `planner_workspace.plan_template_id` (nullable) marks a plan instance created from a template (PLAN-1). Add these in the first push of the phase-3 tables where possible to avoid later migrations.

### 8.3 New tables (phase 4 epics; table numbers start at 80)

| # | Table | Epic | Purpose |
|---|---|---|---|
| 80 | `actor_role` | ROLE-1 | *Deferred (number reserved).* Roles defined once, with a normalized `name_key` for uniqueness |
| 81 | `agent_role` | ROLE-1 | *Deferred (number reserved).* A planner agent can fulfil several roles |
| 82 | `journey_map_version` | PUB-1 | Immutable published snapshot (stages, roles, core cell fields, durations in minutes, links) with a content hash and readiness report. Unique (map, version_no). *Open decision: or extend `automation_snapshot`; see §8.6.* |
| 83 | `plan_template` | PLAN-1 | Tiny reusable shape: name, window days, default start time |
| 84 | `plan_template_map` | PLAN-1 | Which published maps a template accepts |
| 85 | `planner_workspace_map` | PLAN-1 | The instance's own copy of the accepted maps |
| 86 | `work_item` | JOB-1 | One job, pinned to a version; status; attributes with per-value source and timestamp; optional parent |
| 87 | `work_task` | JOB-1 | Job × stage (and lens) by stable keys; **status and timestamps only**; definition read from the pinned version |
| 88 | `planner_task_work_task` | SCHED-1 | Links a scheduled block to its work tasks |
| 89 | `plan_publication` | LIVE-1 | Frozen snapshot of a timeline at Publish to live |
| 90 | `plan_change_log` | LIVE-1 | Append-only record of planner changes after publish |
| 91 | `activity_log` | LOG-1 | Append-only events: started, completed, blocked, unblocked, skipped, reopened, note; performer, server time, fixed reason code, source, duplicate-tap key; points to the frozen publication item (`plan_publication_id` + `publication_item_ref`), never to a planner task. **No pause events in the MVP.** |
| 92 | `ops_issue_ack` | OBS-1 | *Deferred (number reserved).* Records that an issue was acknowledged (fingerprint, who, when, note); a new failure after that reopens it. Issues themselves are derived by grouping events. |

Existing `event_log` (table 3) is **extended additively** (severity, outcome, feature, step, entity, correlation id, error code, message, duration) to serve as the heartbeat and error log; no parallel table is created.

### 8.4 Additions to existing tables (all additive)

**MVP:** `event_log` observability columns; `user.is_platform_admin`; `account.feature_flags`; `journey_stage.owner_lens_id`; `journey_lens.does_planned_work`; `planner_workspace.is_archived`, `plan_template_id`; `planner_agent.user_id`, `is_active`; `planner_task.tweak_reason` and nullable `title` (P3A-1); `workflow_execution.work_item_id`.
**Later:** `journey_cell.core_fields` (LEAN-1); `journey_lens.actor_role_id` (ROLE-1); `journey_stage.exit_condition`, `completion_rule`, `continuous_with_previous` (STAGE-1 deferred fields).

### 8.6 Overlap with the existing initiative `product/validation-publish-execution/` (to reconcile)

That folder (own `prd.md`, 10 phase files, stories US-VAL-01…09, US-PUB-01…09, US-EXE-01…12) is **tracked in git, planned and not built** (no matching tables, endpoints or fields exist). It was written for **AI agents running a map**; this PRD adds the **planner and human performers**. Where they overlap:

| This PRD | Existing initiative | Relationship |
|---|---|---|
| Readiness gate before publish (JM-7, PUB-1) | Publishing Phase 1–2: gate constraints, `publish_map` enforcement, structured `gate_failures[]` (US-PUB-01…06) | Same goal. Prefer adopting theirs, with the MVP minimum in JM-10/JM-11 as the gate content. |
| Immutable `journey_map_version` (JM-8) | Publishing Phase 3: pin `automation_snapshot.version` on each `workflow_execution`, publish history, stale-map detection (US-PUB-07…09) | Same goal. Prefer reusing `automation_snapshot` as the frozen version instead of a new table. |
| `activity_log` and variance (EX-3, EX-4, VA-*) | Execution Phase 1–4: structured `per_stage_log` inside `workflow_execution`, three-gate protocol, planned vs. actual per stage (US-EXE-01…12) | Different grain: theirs is one run's per-stage log (AI-run-centric); this PRD adds task-level human execution plus a plan layer. Reuse their field ideas (planned duration, gap %, outlier flags). |
| Blocked reason / exceptions (EX-5, D-20) | Validation Phase 3 and Execution Phase 3: BLOCKED, NOVEL_EXCEPTION, escalation (US-VAL-07/08, US-EXE-07/08) | Same concept; reconcile the status vocabulary. |
| Plan template/instance, planner, roles, work items, Publish to live | — | New in this PRD. |

**Resolved 2026-10-12 (D-39):**
- **Publish gate:** one gate. Generic maps use the MVP readiness rules plus a real title, with their structured `gate_failures[]` shape. Their stricter Gates 2/3 apply later, only to atomic or automation maps.
- **Versions:** one table, `journey_map_version`, linked to `automation_snapshot`; AI runs will pin to it (replaces US-PUB-07/08).
- **Stale detection:** adopt the behaviour later, using a content hash.
- **Logs and statuses:** one log (LOG-1) and one status list for human work and future AI runs (replaces US-EXE-01–03's vocabulary).
- **Deferred:** AI three-gate protocol (US-EXE-04–06), validator row (US-VAL-01–06), novel exceptions (US-VAL-07/08, US-EXE-07/08).
- **Plan vs. actual:** VAR-1 replaces US-EXE-10–12 and reuses their thresholds.
- That folder is still **not edited**.

### 8.5 Derived, never stored

Expected stage duration (sum of cells); entry condition (previous stage's output); handoff matching; planned start times; blocks; costs; every variance figure; the `duration_minutes` projection of the cell's existing duration columns (conversion rule defined once, e.g. 1 day = 480 min, configurable).

---

## 9. Variance model (how "people don't report it" works)

| Signal | Source | Result |
|---|---|---|
| Actual duration | Start event and end event on the work task (minus pauses) | Actual vs. expected (per stage) and vs. scheduled (per block) |
| Start lateness | Start event vs. derived planned start | Schedule adherence |
| Window adherence | End event vs. window attribute, if the work type has one | On-time rate |
| Exception | Blocked status plus reason code | Exception frequency by stage and reason |
| Planner tweak | Scheduled ≠ expected, plus optional reason | "The map is probably wrong here" signal |
| Attribute effect | Duration variance grouped by job attribute | Candidate duration modifiers (P2) |

Pauses are **not captured in the MVP** (D-17). Actual time is elapsed time, and unusually long tasks are flagged as outliers (VA-7).

---

## 10. Decisions log (settled — do not re-litigate)

| # | Decision | Date |
|---|---|---|
| D-01 | The product is a **generic** process loop; only the journey map changes per work type. Logistics is the first test case, not the identity. | 2026-10-11 |
| D-02 | Different work types are separate maps; the **planner groups them manually** into plans. No automatic pooling or "pool" object yet. | 2026-10-11 |
| D-03 | Expected duration comes from the journey map; the planner tweaks it **per job only**, at block level. | 2026-10-11 |
| D-04 | The planner enters job attributes manually; each value records its **source** so other sources can plug in later. | 2026-10-11 |
| D-05 | Attribute vocabulary is controlled (enums, numbers, yes/no); free text only in notes. | 2026-10-11 |
| D-06 | Attributes do not change durations automatically; AI proposes modifiers from data later. | 2026-10-11 |
| D-07 | **Performers do not report variance.** The app derives it from start/end times and status changes. (A performer-entered "observed differs" flag was considered and rejected.) | 2026-10-11 |
| D-08 | A planner tweak may carry an optional reason chosen from the job's attributes. | 2026-10-11 |
| D-09 | Publishing a map version and publishing a plan to live are two distinct actions with distinct names (**Publish version** vs. **Publish to live**). See D-24. | 2026-10-11 |
| D-10 | Duration reuses the existing `journey_cell` columns; no duplicate stored duration field. | 2026-10-11 |
| D-11 | Each stage is its own schedulable item by default. A stage flagged `continuous_with_previous` (declared by the process owner) groups with the previous same-role stage into one **block**; the planner may override. *(Blocks deferred beyond the MVP — D-43.)* | 2026-10-11 |
| D-12 | Blocks are **derived on read**, not stored. A tweak is stored as one scheduled value on the planner task. | 2026-10-11 |
| D-13 | Location, time windows and load/capacity are **optional attributes**, not core. Whether jobs of different work types share one visit or slot is a planner decision, not a system rule. | 2026-10-11 |
| D-14 | Lean cell core: 4 structured text fields + virtual duration + 2 text fields (`friction`, `notes`). Cell owner is the lens; stage owner is the stage contract; no separate owner field on the cell. | 2026-10-11 |
| D-15 | Work tasks reference the pinned version for their definition; they do not copy task text or durations. | 2026-10-11 |
| D-16 | A new `work_item` table is the business object; `workflow_execution` stays the AI run engine and gains a nullable link to it. | 2026-10-11 |
| D-17 | **No pause capture in the MVP.** Actual time is start to done; unusually long tasks are flagged as outliers for someone to explain. | 2026-10-11 |
| D-18 | **AI-proposed process improvement is out of the MVP** (future phase). The MVP still captures the structured data it will need. | 2026-10-11 |
| D-19 | **The performer app does not need to work offline in the MVP.** Offline is a noted future-phase item. | 2026-10-11 |
| D-20 | Blocked reasons come from **one fixed list shared by every work type** in the MVP; improve later if needed. | 2026-10-11 |
| D-21 | `tools_systems` stays in the cell **notes** for the MVP; not a structured field yet. | 2026-10-11 |
| D-22 | The **planner assigns people/agents when building a plan**. Plan templates do not name roles or people. | 2026-10-11 |
| D-23 | Changes made after publish to live are **visible only to the planner**; performers do not see them. | 2026-10-11 |
| D-24 | Naming: **Publish version** (journey map) and **Publish to live** (plan). Both use the word "publish" on purpose; the full label always disambiguates. | 2026-10-11 |
| D-25 | Core cell fields are required **only for work-doing actors**. Customer-type actors exist to add context to the journey map. | 2026-10-11 |
| D-26 | Capacity constraints are **deferred** beyond the MVP; later they become an optional attribute a work type can declare. | 2026-10-11 |
| D-27 | **MVP minimum for a journey map** is five fields: work type name; per stage name, order, owner role; per work-doing cell task and expected duration. Done-when is recommended but optional. | 2026-10-11 |
| D-28 | MVP readiness = every stage has name, owner role, task and duration. The input/output hand-off coherence check comes later. | 2026-10-11 |
| D-29 | Required fields live **in place** (map settings, stage header, cell panel) and look different from freeform notes (Required tag, structured inputs, per-stage mark, progress line, checklist with jump links, disabled publish with reason). See JM-12. | 2026-10-11 |
| D-30 | A role has a **"does planned work?" switch**: default Yes for Internal and AI Agent, No for all other actor types. *(In the MVP the switch lives on each journey-map row — D-42.)* | 2026-10-11 |
| D-31 | **Flow:** map → Publish version → tiny plan template (points to map versions) → plan instance (copy) → add jobs (tasks pulled from the pinned version) → Publish to live. The plan template stays in the MVP as a tiny step. | 2026-10-11 |
| D-32 | **Governance is part of the MVP, not a later phase:** database standards (GOV-1), validation and friendly errors (VAL-1), and observability with a Health page (OBS-1) are built first, and every other epic carries a Governance section and tests. | 2026-10-11 |
| D-33 | The support person is the founder (a product manager). The system must be diagnosable without reading code: plain-language issues, an owner for each, and a diagnostic bundle for engineers and the AI. | 2026-10-11 |
| D-34 | The "heartbeat" is implemented by **extending the existing `event_log`** (additive columns) and scheduled heartbeat and integrity tasks. Successes and failures both land there. *(Default; alternative is a new table.)* | 2026-10-11 |
| D-35 | Deletion follows an explicit matrix: used roles, maps with versions, and plans with history are **archived, never deleted**; versions, publications and logs are never deleted. | 2026-10-11 |
| D-36 | The UI validates for the user; the server always validates again. User input is preserved on any rejected save. | 2026-10-11 |
| D-37 | The MVP uses **existing cell fields**: task = `actor_fields.task_objective`, done-when = `actor_fields.success_criteria`, duration = `time_duration_value` + unit. The LEAN-1 migration is deferred. | 2026-10-12 |
| D-38 | Performers may tap **Done without Start**. The start is recorded as unknown, actual time is unknown, and it is flagged as a data-quality warning. | 2026-10-12 |
| D-39 | Overlap with `validation-publish-execution/` resolved: one publish gate (MVP rules + title; stricter gates later only for atomic/automation maps), one version table (`journey_map_version` linked to `automation_snapshot`), one log and one status list. See §8.6. | 2026-10-12 |
| D-40 | Phase-3 is amended before it is built (`EPIC-P3A-1`): plans, agents and timelines with recorded work are archived or deactivated, never deleted; phase-4 columns are added in the first push. | 2026-10-12 |
| D-41 | The Health page and ops endpoints are **admin-only** (`user.is_platform_admin`). | 2026-10-12 |
| D-42 | The role registry (ROLE-1) is deferred. The MVP uses a **"does planned work?" switch on each journey-map row**, and the planner assigns any active person. | 2026-10-12 |
| D-43 | MVP scheduling is **one item per task**; blocks, continuous stages and configurable completion rules are deferred. | 2026-10-12 |
| D-44 | Job attributes are **free key/value pairs** in the MVP (with source and time); a controlled list per work type comes later with the intake schema. | 2026-10-12 |
| D-45 | Required cells: the **stage owner's cell plus any other work-doing cell the user has started** need a task and duration. | 2026-10-12 |
| D-46 | Feature flags live in `account.feature_flags` (`required_fields_ui`, `publish_gate`): off while building, on at launch. Failure tests use Xano unit-test mocks, never switches in production endpoints. | 2026-10-12 |

---

## 11. Open questions

The ten questions raised in v0.2 were all answered on 2026-10-11 and are recorded as decisions D-17 to D-26 in §10.

The independent review of 2026-10-12 raised five questions; all were answered with the recommended option and are recorded as D-37 to D-46. **No open questions block building.**

### Future-phase backlog (deliberately not in the MVP)

| Item | Why deferred | Notes for later |
|---|---|---|
| AI-proposed process improvements | Founder decision: not needed for MVP | MVP still captures structured attributes, reasons and timestamps so the data exists. |
| Offline performer app | MVP requires a connection | Needs local queue and sync of activity-log events. |
| Pause capture | Keep performer taps minimal | Revisit if long-task flags prove noisy. |
| Per-work-type blocked reasons | One fixed list is enough to start | Map could declare its own list later. |
| Structured tools/systems list | Notes are enough for now | Needed only if execution or automation features want it. |
| Capacity constraints (vehicle load, staff limits) | Not required for MVP | Add as an optional attribute a work type can declare. |
| Automated sequencing/optimization | Manual sequencing first | Uses the scheduling shape (who, when, how long, what first, plus optional attributes). |
| Role registry (ROLE-1) | MVP uses a per-row switch | Migrate the switch into roles; use a normalized `name_key`. |
| Lean cell core migration (LEAN-1) | MVP uses existing fields | File currently missing; restore before building. |
| Blocks, continuous stages, configurable completion rules, exit condition | One item per task is enough to prove the loop | STAGE-1 and SCHED-1 deferred stories. |
| Bulk publish to live, stale-map detection | Not needed to prove the loop | LIVE-1, PUB-1 deferred stories. |
| Stage aggregates, tweak signal, variance panel, window adherence | Per-task variance first | VAR-1 deferred stories. |
| Issue acknowledgement, AI diagnostic tool, retention tiers | Health page and Copy bundle first | OBS-1 deferred stories. |

---

## 12. Success metrics

- **Loop closure:** a job moves map → plan → publish to live → execution → log with no manual data re-entry.
- **Data quality:** ≥ 95% of completed work tasks have both a start and an end time captured by the app.
- **Plan accuracy:** median |scheduled − actual| per block shrinks over successive versions.
- **Process improvement** *(future phase)*: share of AI-proposed changes approved; reduction in stage-level variance after each version.
- **Safety:** zero loss of existing journey-map data through migrations (parity report passes).

## 13. Phasing and next steps

| Phase | Outcome | Where | State |
|---|---|---|---|
| **3** | Planner backend (tables, APIs, frontend integration) | `product/stories/phase-3` | Planned |
| **4** | **MVP foundation:** governance, stage owner, required-field authoring, publish version, plan template/instance, jobs, scheduling, publish to live, activity log, performer app, variance, end-to-end validation (plus phase-3 amendments) | `product/stories/phase-4/` | 17 epic files plus a README, reviewed and revised 2026-10-12; ROLE-1 and LEAN-1 deferred; not built |
| **5** | *(unassigned; the `phase-5` folder exists and is empty)* | `product/stories/phase-5` | — |
| **6** | Offline performer app and other backlog items (§11) | — | Future |
| **7** | AI learning loop and proposed versions | — | Future (not in the MVP) |

**Phase-4 epics (one feature each; every epic has UT/FT/E2E test cases and a completion gate):**

| Epic | Feature |
|---|---|
| `EPIC-P3A-1` | Planner amendments: archive/deactivate instead of delete; phase-4 columns in phase-3's first push |
| `EPIC-OBS-1` | Observability: heartbeat, error catalog, Health page, diagnostic bundle |
| `EPIC-GOV-1` | Data integrity governance: standards, delete matrix, guards, audits |
| `EPIC-VAL-1` | Input validation and friendly errors |
| `EPIC-TIME-1` | Duration model: one minutes conversion; meaning of `actual_duration` |
| `EPIC-ROLE-1` | Actor role registry, role picker *(deferred post-MVP)* |
| `EPIC-STAGE-1` | Stage contract: real owner, exit condition, completion rule, continuous flag |
| `EPIC-LEAN-1` | Lean cell core *(deferred post-MVP; file currently missing from the folder)* |
| `EPIC-AUTH-1` | Required-field authoring: required vs. freeform, ready marks, progress, checklist |
| `EPIC-PUB-1` | Publish version: readiness gate, immutable versions, stale detection |
| `EPIC-PLAN-1` | Plan template and instance (copy semantics) |
| `EPIC-JOB-1` | Jobs and tasks: pinned to a version, tasks generated and hydrated |
| `EPIC-SCHED-1` | Scheduling: derived blocks, assignment by role, per-job duration tweaks |
| `EPIC-LIVE-1` | Publish to live: frozen snapshot, planner-only changes logged afterwards |
| `EPIC-LOG-1` | Activity log and status engine: fixed statuses, blocked reasons, stage advance |
| `EPIC-APP-1` | Performer app: today's items, one-tap actions |
| `EPIC-VAR-1` | Variance and outliers, computed from the log |
| `EPIC-E2E-1` | End-to-end validation and integrity audit |

Build order and dependencies: `product/stories/phase-4/README.md`.

**Immediate next action for a new session:** begin implementation in the **MVP build order** in the phase-4 README, starting with OBS-1, one epic at a time, running each epic's tests before moving on. First item inside OBS-1: the correlation-id spike (US-OBS-1-12). Before ROLE-1 or LEAN-1 are ever built, confirm with the founder (LEAN-1's file must be restored).

### Key files for orientation

| What | Where |
|---|---|
| This PRD | `product/emgramprd.md` |
| Planner backend epics | `product/stories/phase-3/` |
| MVP foundation epics (index and build order) | `product/stories/phase-4/README.md` |
| Earlier validation / publishing / execution initiative (planned, not built; overlaps this PRD, see §8.6) | `product/validation-publish-execution/` (`prd.md`, `validation/`, `publishing/`, `execution/`) |
| Table definitions | `static/tables/*.xs` |
| Cell field templates and AI fill tools | `ai/tool/update_actor_cell_fields.xs`, `scaffold_structure.xs` |
| Journey-map APIs | `apis/journey_map/` |
| Frontend (journey maps) | `webapp/protype-2` (unit tests: `npm test`, Playwright in `e2e/`) |
| Frontend (planner) | `webapp/planningFrontendv2` |
| Backend workflow tests | `workflow_tests/` |
| Live journey-map data (via MCP) | map 178 `leads-to-sales-baseline` |

## 14. Risks

| Risk | Mitigation |
|---|---|
| Performers forget or tap inconsistently | Variance derived from status actions they already take; minimal-tap UI; flag implausible timestamps instead of asking users |
| Not enough data for AI to learn | Capture structured attributes and reasons from day one; learning is a future phase, after the data exists |
| Logistics assumptions leaking into the core | Principle 10; test every design against a non-logistics work type |
| Schema drift between layers | Reference-not-copy; versions pinned; end-to-end integrity test (EPIC-E2E-1) |
| Map edits disrupting live work | Immutable versions; in-flight work stays pinned |
| Scope creep into optimization | Automated sequencing is P2; manual sequencing first |
| Two meanings of "publish" | Always use the full labels: **Publish version** (map) vs. **Publish to live** (plan) |
| Planner changes after publish to live are invisible to performers (D-23) | Log every change against the snapshot; revisit live push to performers in a later phase if it causes field confusion |
| Duplicate facts (e.g. a second duration field) | Verify existing schema before adding fields; phase-4 amendment is the cautionary example |
