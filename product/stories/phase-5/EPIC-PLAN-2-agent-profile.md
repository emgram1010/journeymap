# PLAN-2 — Agent Profile

**Epic ID:** PLAN-2
**Feature:** A durable, per-person "agent profile" that exists independent of any one plan.
**Status:** Planning
**Depends on:** phase-3 PLN-1 (`planner_agent`), phase-4 P3A-1
**Model:** Sonnet (ordinary CRUD + a side table; nothing touches the status engine or a publish gate)
**Goal:** One place that answers "is this person eligible to be an agent, and what are their defaults" — referenced by every plan they're ever on, instead of re-entered inside each one.

---

## Context

Today `planner_agent` only exists *inside* a single plan (`planner_workspace`): unique by `(workspace_id, name)`, created fresh by hand every time a plan is built. There is no identity for a person-as-agent that survives across plans — the only cross-plan link is the optional `user_id`, which exists to let a real login perform work in `/perform`, not to carry any defaults forward.

This epic adds that missing identity: **one `agent_profile` row per eligible person**, holding just enough to seed a fresh `planner_agent` row wherever they're added — nothing about scheduling, nothing about a specific plan.

This is the foundation PLAN-3 builds on (a plan template's agent roster points at `agent_profile`, not at any one plan's `planner_agent` rows).

## Existing Architecture (Do Not Break)

- `planner_agent` (phase-3 PLN-1, amended P3A-1) keeps working exactly as it does today. This epic does not change it, touch its rows, or make `agent_profile` required for anything existing.
- `user.account_id` already scopes every user to one account — `agent_profile` inherits tenancy through that relationship rather than duplicating an `account_id` column.
- An AI agent today has no login (`planner_agent.user_id = 0`) and is named directly on the `planner_agent` row. This epic preserves that: a profile can represent an AI agent too, with no `user_id`.

## Non-Goals

- **No availability or scheduling fields.** This epic is identity and defaults only — availability/shift data is explicitly deferred to a later epic, once it's actually needed.
- **No auto-assignment.** Nothing here picks an agent automatically.
- **No skill/tag matching.** Deferred alongside availability.
- Does not touch `/perform` or execution-side logic at all.

---

## Stories

### US-PLAN-2-01 — `agent_profile` table

**Files:** `static/tables/90_agent_profile.xs` (reserved; Xano will assign its own live id, as it always has)

- `id`, `created_at`, `updated_at`
- `user_id?` (nullable-by-default-0, table ref `user`) — set for a person, `0` for an AI agent with no login
- `kind` enum `["person", "ai"]`, required
- `name?` — required only when `kind = "ai"` or `user_id = 0` (an AI agent names itself here, same as `planner_agent` does today); for a person, defaults to `user.name` at read time and is never required on the profile itself
- `color?` filters=trim — hex, display default
- `default_daily_capacity_hours?` decimal, default `8`
- `is_eligible?` bool, default `true` — the "tagged as an agent" flag; turning it off hides them from future rosters without deleting history
- Unique: `(user_id)` where `user_id != 0` — one profile per real login

**Acceptance:** a person can have at most one profile; an AI profile needs a name; invalid `kind` or non-positive capacity rejected.

### US-PLAN-2-02 — Profile CRUD API

- `POST planner/agent-profile` — create (tag a user as agent-eligible, or create an AI profile)
- `PATCH planner/agent-profile/{id}` — update defaults, toggle `is_eligible`
- `GET planner/agent-profile` — list eligible profiles for the caller's account (joins through `user.account_id` for person profiles; AI profiles carry no account today — scope AI profiles to whichever account created them via an `account_id` column on the profile itself, since they have no `user` row to inherit tenancy from)

**Acceptance:** cross-account access denied; a person already profiled can't be profiled twice; an ineligible (`is_eligible = false`) profile doesn't appear in the default list.

### US-PLAN-2-03 — Minimal UI: "Agents" settings list

**Files:** planner settings area (exact location TBD against current `webapp/protype-2` structure)

- A simple list of the account's users with an "Agent" toggle (creates/updates their profile), plus a small "Add AI agent" action for profiles with no login.

**Acceptance:** toggling a user on makes them selectable in PLAN-3's template roster picker; toggling off removes them from future rosters without touching plans they're already on.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-PLAN-2-01 | Unit | Validate capacity hours (`0`, negative, `8`, `24.5`) | Reject ≤ 0, accept positive |
| UT-PLAN-2-02 | Unit | Validate color hex (`"#4f46e5"`, `"blue"`, `""`) | Accept hex only, empty is fine (optional) |
| FT-PLAN-2-01 | Functional | Profile a user twice | Second rejected |
| FT-PLAN-2-02 | Functional | Create an AI profile with no name | Rejected |
| FT-PLAN-2-03 | Functional | Toggle `is_eligible` off, then list | Dropped from default list |
| FT-PLAN-2-04 | Functional | Cross-account profile access | Denied |
| E2E-PLAN-2-01 | UI | Toggle a teammate to "Agent" | They appear in PLAN-3's roster picker |

**Completion gate:** all pass; phase-3/phase-4 planner tests stay green.

## Governance (data integrity, validation, observability)

**Data integrity**

| Table | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `agent_profile` (90) | PK; `user_id → user` (nullable via 0) | `(user_id)` where `user_id != 0` | `kind`; `name` when `user_id = 0` | No delete — `is_eligible = false` instead |

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| User already has a profile | "This person is already set up as an agent." | `E-PLAN-006` |
| AI profile with no name | "Give this AI agent a name." | `E-PLAN-007` |
| Capacity hours ≤ 0 | "Daily capacity must be a positive number of hours." | `E-PLAN-008` |
| Invalid color | "Enter a color like #4f46e5." | `E-PLAN-009` |

**Events logged** (`feature = PLAN-2`): `create_profile`, `update_profile`, `toggle_eligibility`, each `success`/`rejected`/`failure`.

## Decisions needed (recommended defaults in bold)

| # | Question | Recommendation |
|---|---|---|
| D-1 | Does an AI profile belong to an account directly, since it has no `user` row to inherit tenancy from? | **Yes — add `account_id` to `agent_profile`, required only when `user_id = 0`.** Keeps tenancy checks uniform without forcing AI agents to pretend to be logins. |
| D-2 | Can a person's profile be edited by anyone, or only an admin? | **Admin only for creating/toggling others; a person could later edit their own display defaults, but that's not needed for MVP.** |

## Test Results

*(empty — to be filled when built)*
