# US-DEMAND-1-01 — Add an on-demand job to a live day

**Epic:** DEMAND-1 · **Size:** M · **Model:** **Opus 5.5** · **Status:** 📋 Not built
**Decision D-7:** ✅ approved 2026-11-21: adding to a live day **runs, then tells you**. The tool
declares its own action type (`plan_live_add`) with that level as its default; the owner can change it later.

## Description

A live day is locked so the team can trust it. That lock also means work caused by an event,
such as a new booking, has nowhere to go until someone re-plans and republishes. This story
adds one narrow, safe way in: put a job at the end of an existing live day, flagged as
unplanned. Everything about it is built to be called many times by a machine without harm.

## User story

**As** the owner or an AI agent, **I want** to drop a job from a published map onto a live
day, **so that** event-driven work shows up straight away without disturbing the plan.

## Acceptance criteria

```gherkin
Scenario: add an on-demand job
  Given plan P accepts map M, M has a published version, and member X has a live day on date D
  When plan_add_on_demand_job is called with P, M, X, D, a title and source_ref "booqable:order:96"
  Then a job is created, pinned to M's latest published version
  And its steps are added after the last block of X's live day
  And the job is flagged unplanned and stores its source
  And it appears in Execution for X at once

Scenario: planned work is untouched
  Then no planned block on that day has moved, changed length or been removed

Scenario: no live day
  Given X has no live day on D (none, or still a draft)
  Then it is refused: "X has no live day on D. Publish that day first."
  And no day is created and nothing is published

Scenario: the same order twice
  When the same source_ref, map and day are sent again
  Then the first job is returned with created false, and no second job exists

Scenario: the same order ten times at once
  Then exactly one job exists afterwards

Scenario: over capacity
  Given the day is full
  Then the job is still added, and the response and the day carry "over by N minutes"

Scenario: the map is not accepted, or has no published version
  Then it is refused, and the message says which

Scenario: the switch is off
  Given on-demand jobs are switched off for plan P
  Then it is refused: "On-demand jobs are switched off for this plan." and nothing is written

Scenario: a past date, or a date outside the plan's window
  Then it is refused with a message that names the allowed range

Scenario: the member is switched off, or is not in this plan
  Then it is refused

Scenario: no source_ref
  Given a person adds an on-demand job by hand
  Then it is created every time (no duplicate rule without a source)
```

- One function does the work (suggested `planner_ops/add_on_demand_job`); the tool and the
  endpoint are thin callers. It reuses `planner_ops/create_work_item` for the job itself.
- "Today" and D are read in the **business's time zone**, never UTC (finding F-8).
- `source_ref` format: `system:kind:id`, lower-case system and kind, max 120 characters,
  letters, digits, `-`, `_` and `:` only.
- The response returns `work_item_id`, `created` (true/false), `task_count`, `over_capacity_minutes`.

## Counter-measures

| Risk | Prevention |
|---|---|
| Two overlapping calls both pass the "does it exist" check and make two jobs | A **unique index** on the side table over (plan, map, date, source_ref). The second insert fails, the transaction rolls back, and the function returns the first job |
| A rolled-back attempt leaves half a job | The job, its steps, the side-table row and the day blocks are written in one `db.transaction`; logging and any HTTP stay outside |
| A new column on `work_item` drops its `title` validators | Do not alter `work_item`. New 1:1 side table (suggested `work_item_origin`: work item, origin `planned` / `on_demand`, source system, source ref, date). A job with no row is planned |
| The side table is invisible to the screen | It gets its own GET list endpoint and a dedicated fetch (the STAGE-1 lesson) |
| The per-plan switch needs a column on an existing table | Side table or the existing feature-flag table; default **off** |
| A machine floods a day | At most N on-demand jobs per plan per day (suggested 50), counted on the side table |
| Composite keys built with a pipe character break the parser | Use `::` as the separator |
| A date in UTC puts an evening order on tomorrow | Convert with the business's time zone before any compare; test at 11:30 pm local |
| A date input left out crashes the call | `date` is required; if any optional date is added, declare it as text |
| Adding to a live day bypasses the owner's approval levels | The tool declares its own action type (suggested `plan_live_add`), so the owner's level applies (D-7) |
| The job silently has no steps | `task_count` 0 is returned with `skipped_stages` and a warning event, as `plan_add_job` does |
| The caller is an AI on someone else's plan | Same gate, same `copilot/plan_in_business`, same Planner grant as `plan_add_job` |

## Governance

- **Errors (suggested):** `E-DEMAND-001` no live day · `E-DEMAND-002` switched off ·
  `E-DEMAND-003` date outside the window · `E-DEMAND-004` bad source_ref ·
  `E-DEMAND-005` daily limit reached · `E-DEMAND-006` member not available.
- **Events:** `on_demand_job.created`, `.duplicate_returned`, `.refused` (with code),
  `.over_capacity` (warning). Each has plan, day, source ref.
- **Delete behaviour:** the side-table row is removed with its job, inside the job's own
  delete path (query, then loop by id, in a transaction).

## Tests (write first)

| ID | Test |
|---|---|
| T-DEMAND-01-1 | Happy path: job at the end of the day, flagged, visible in Execution |
| T-DEMAND-01-2 | Planned blocks identical before and after (compare a snapshot of the day) |
| T-DEMAND-01-3 | No live day refused; row counts unchanged; no day created |
| T-DEMAND-01-4 | Second call returns the first job |
| T-DEMAND-01-5 | Ten parallel calls leave one job (real HTTP, in parallel) |
| T-DEMAND-01-6 | Over capacity still added, minutes over reported |
| T-DEMAND-01-7 | Switch off refuses; switch on works; no data changed by the switch |
| T-DEMAND-01-8 | 11:30 pm local lands on the local date |
| T-DEMAND-01-9 | Daily limit refuses the next one |
| T-DEMAND-01-10 | Other account, other business: refused |
| T-DEMAND-01-11 | A failure in the middle leaves nothing behind (forced error) |
