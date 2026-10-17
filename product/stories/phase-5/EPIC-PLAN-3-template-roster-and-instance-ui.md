# PLAN-3 — Template Agent Roster, Instance Copy, and the Minimal Planner UI

**Epic ID:** PLAN-3
**Feature:** A plan template remembers which agents belong to it; creating an instance copies them in automatically.
**Status:** Planning
**Depends on:** PLAN-1 ✅ (template/instance, backend only), PLAN-2 (agent profile)
**Model:** Sonnet (extends an already-proven copy pattern; no new mechanism)
**Goal:** The founder builds a template once — maps **and** agents — and every future instance starts staffed, without re-adding the same people each time. Manual trigger only; no auto-recurrence (that's later).

---

## Context

PLAN-1 proved the copy semantics for maps: a template's `plan_template_map` rows get copied into a fresh `planner_workspace_map` on every instance. This epic applies the exact same shape to agents, using PLAN-2's durable `agent_profile` as the thing being referenced (never a live `planner_agent` row, which only exists inside one plan already).

This epic also finishes PLAN-1's own unbuilt UI story (`US-PLAN-1-05`) — building a roster picker without the base template screen existing yet would be wasted motion, so this epic owns both.

**Explicitly decided in discussion, recorded here:**
- The **template** is the record of truth for "who's normally on this," not "whoever was on the last instance" — a one-off change to a single instance (someone's out sick) never leaks into the next one, because the next one copies from the template, not from the prior instance. This also means a template can seed **any number of independent instances** in parallel with no "which one is the real prior instance" ambiguity — nothing to solve there.
- Instance creation stays **manual, one click, human-confirmed** for MVP. No background job, no cron, no auto-created next period. That's a distinct future epic.

## Existing Architecture (Do Not Break)

- PLAN-1's tables, endpoints, and copy-on-create behavior for maps are unchanged.
- `planner_agent` keeps being the thing that actually gets assigned to timelines/tasks inside a plan — this epic only changes how those rows get **seeded**, never how they're used afterward.
- A plan created without a template (phase-3's plain `POST planner/workspace`) keeps working with zero agents pre-filled, same as today.

## Non-Goals

- **No auto-recurrence.** Creating the next period's instance is always a deliberate action.
- **No roster removal from a template yet** — same delete-approval gate PLAN-1 already deferred for maps. Adding an agent to a template is append-only and safe to call twice (skips one already attached).
- **No availability/auto-assignment** — PLAN-2 doesn't have the data for it yet, and this epic doesn't add any.
- No changes to how agents are assigned *within* an instance once it exists (that's existing PLN-5 territory).

---

## Stories

### US-PLAN-3-01 — `plan_template_agent` table

**Files:** `static/tables/91_plan_template_agent.xs` (reserved; Xano assigns its own live id)

- `plan_template_id`, `agent_profile_id`; unique pair.
- No `position`, no hours override here — a per-instance tweak happens on the instance's own `planner_agent` row after copy, same as any other instance edit.

**Acceptance:** the same agent profile can't be attached to one template twice; attaching an ineligible (`is_eligible = false`) profile is rejected with a clear message.

### US-PLAN-3-02 — Template roster API

- `POST planner/template/{id}/agent` — `add_agent_profile_ids: int[]`, append-only, idempotent (mirrors PLAN-1's `add_map_ids` shape exactly).
- `GET planner/template/{id}` (extends PLAN-1's existing read) — includes the attached roster alongside the attached maps.

**Acceptance:** attaching an already-attached profile is a no-op, not an error; cross-account template or profile access denied.

### US-PLAN-3-03 — Instance creation copies the roster

**Files:** extends `apis/planner/551_template_template_id_instance_POST.xs`

- For every `plan_template_agent` row on the template, create a fresh `planner_agent` in the new `planner_workspace`: `name` from the profile's user (or the AI profile's own name), `kind`, `color`, `daily_capacity_hours` from the profile's defaults, `user_id` carried through for a person.
- **If a referenced profile is no longer eligible** (`is_eligible = false`) at instance-creation time: skip it, don't fail the whole instance, and say so plainly in the response (`skipped_agents: [...]`) — never a silent gap in the roster. Same "never fail silently" rule OBS-1 already holds this project to.

**Acceptance:** a template with 3 eligible agents produces an instance with 3 `planner_agent` rows, correctly defaulted; an instance already created is never altered by a later template change (same guarantee PLAN-1 proved for maps — FT-PLAN-1-05); a deactivated profile is skipped and reported, not silently dropped or hard-failed.

### US-PLAN-3-04 — Minimal planner UI (completes PLAN-1's `US-PLAN-1-05`, adds the roster)

- **Templates list and form:** name, window days, start time, maps, **and now an agent picker** sourced from PLAN-2's eligible-profiles list.
- **"New plan from template" action:** shows the resulting window (already specified in PLAN-1) **and now the agents that will be copied in**, before the instance is actually created.

**Acceptance:** an instance can be created end to end from the UI with its maps and agents both pre-filled; a skipped (deactivated) agent is visibly flagged on the result screen, not hidden.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-PLAN-3-01 | Functional | Attach the same agent profile to a template twice | Second call is a no-op |
| FT-PLAN-3-02 | Functional | Attach an ineligible profile | Rejected with a clear message |
| FT-PLAN-3-03 | Functional | Create instance from a template with 3 agents | 3 `planner_agent` rows, correctly defaulted |
| FT-PLAN-3-04 | Functional | Edit template roster after instance creation (add/remove) | Existing instance's agents unchanged |
| FT-PLAN-3-05 | Functional | One of 3 roster profiles is deactivated, then create instance | 2 agents copied, 1 reported as skipped, no failure |
| FT-PLAN-3-06 | Functional | Same template used to create two instances in parallel | Both succeed independently; no chain/ordering dependency between them |
| FT-PLAN-3-07 | Functional | Cross-account roster access | Denied |
| E2E-PLAN-3-01 | UI | Build a template with maps + agents, create an instance | Instance shows the computed window, maps, and agents; a skipped agent (if any) is visible |

**Completion gate:** all pass; PLAN-1 and phase-3 planner tests stay green.

## Governance (data integrity, validation, observability)

**Data integrity**

| Table | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `plan_template_agent` (91) | `plan_template_id`, `agent_profile_id` (indexed) | pair | both | Cascade with the template; removal from a template waits on the delete-approval gate, same as `plan_template_map` |

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Agent profile already on this template | *(silent no-op, not an error — append-only, matches `add_map_ids`)* | — |
| Attaching an ineligible profile | "This person isn't tagged as an agent right now." | `E-PLAN-010` |
| Cross-account template/profile | "Template not found." | *(reuses PLAN-1's 404 pattern)* |

**Events logged** (`feature = PLAN-3`): `add_template_agent`, `create_instance` (extended to include `agent_count` and `skipped_agent_count`), each `success`/`rejected`/`failure`.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-PLAN-3-G01 | Functional | Schema audit on table 91 | Pass |
| FT-PLAN-3-G02 | Functional | Instance-creation failure injected mid-copy (agents partially copied) | No partial instance — same all-or-nothing transaction guarantee as PLAN-1's map copy |

## Decisions needed (recommended defaults in bold)

| # | Question | Recommendation |
|---|---|---|
| D-1 | A roster profile is deactivated by the time an instance is created — skip and report, or block instance creation entirely? | **Skip and report** (`skipped_agents` in the response, surfaced in the UI). Blocking the whole instance over one unavailable person is worse than starting slightly understaffed with a clear flag. |
| D-2 | Can one template seed more than one instance running at the same time? | **Yes, unrestricted** — already resolved by "template is the record of truth": each instance copies fresh from the template, so there's no shared state between parallel instances to conflict over. |

## Test Results

*(empty — to be filled when built)*
