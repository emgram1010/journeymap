# PLAN-2 — Agent Profile

**Epic ID:** PLAN-2
**Feature:** A durable, per-person "agent profile" that exists independent of any one plan.
**Status:** Done (to-do / in-progress / done)
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

**2026-10-17 — Sonnet 5 build pass. All stories built and verified over real authenticated HTTP, plus a real click-through in the browser.**

| Thing | Live id | File |
|---|---|---|
| `agent_profile` | table 129 | `static/tables/129_agent_profile.xs` |
| `planner/assert_agent_profile` | fn 163 | `functions/planner/assert_agent_profile.xs` |
| `planner/assert_agent_profiles_eligible` | fn 164 | `functions/planner/assert_agent_profiles_eligible.xs` |
| `POST planner/agent-profile` | 573 | `apis/planner/573_agent_profile_POST.xs` |
| `GET planner/agent-profile` | 574 | `apis/planner/574_agent_profile_GET.xs` |
| `PATCH planner/agent-profile/{id}` | 575 | `apis/planner/575_agent_profile_profile_id_PATCH.xs` |
| `isValidColorHex`/`isValidCapacityHours`/`isValidProfileName` | — | `webapp/protype-2/src/agentProfile.ts` |
| Agents modal | — | `webapp/protype-2/src/planner/components/AgentProfilesModal.tsx`, wired into `Header.tsx`/`PlannerApp.tsx` |

D-1 taken as recommended (AI profiles carry their own `account_id`). **D-2 correction (Opus review, 2026-10-17):** this line originally said D-2 was "taken as recommended" with no role check. That was wrong; the recommendation was admin-only for managing *other* people. It's now built as recommended: anyone can manage their own profile, and only an admin can manage someone else's or an AI profile (E-PLAN-013). See `gap-fix.md` #2.

### Unit tests
`npm test`: 347/347 (7 new — UT-PLAN-2-01/02 plus the profile-name helper).

### Functional (real HTTP, account 2 / javierc9@gmail.com)
| Case | Result |
|---|---|
| AI profile, no name | ✅ `E-PLAN-007` |
| AI profile, valid name + color | ✅ created, `kind: "ai"`, `user_id: 0` |
| Person profile for an existing user | ✅ created, `kind: "person"`, `account_id: 0` (tenancy via `user.account_id` instead) |
| Same user profiled twice | ✅ `E-PLAN-006` |
| Invalid color (`"blue"`) | ✅ `E-PLAN-009` |
| Zero capacity | ✅ `E-PLAN-008` |
| `GET` list | ✅ both profiles returned, person's `display_name` correctly resolved from `user.name` ("Jav"), AI's own name used directly |
| `PATCH is_eligible: false` → `GET` | ✅ dropped from default list; `?include_ineligible=true` brings it back |
| `assert_agent_profiles_eligible` — empty list / mixed accounts / ineligible | ✅ `ok:true` (empty); `not_found` (cross-account, profile 1 of 2 checked before failing fast); `not_eligible` (toggled off) |

### UI
Real click-through in a running `npm run dev` session: opened the new "Agents" button in the Planner header, saw the two profiles created during the HTTP tests (with the person's real name resolved), typed a new AI agent name ("Weekend Dispatcher") and added it — appeared instantly in the list via a full reload of the account's profiles.

### Deviations
- No admin-only restriction on these endpoints (matches PLAN-1's own precedent: "a template is ordinary planning work," same logic applies to tagging an agent).
- `GET account/my_team_members` (an existing endpoint, a different API group — "Members & Accounts", canonical `Fcgmwc6Y`) is reused as the candidate list for tagging, rather than building a new one — added `getAccountsBaseUrl()` to `performApi.ts` following the exact pattern `getJourneyMapBaseUrl` already established.

## Notes

- The "copy forward vs. template-as-truth" debate that motivated this epic resolved in favor of template-as-truth (see PLAN-3) — this epic itself doesn't take a position on that; it only had to provide a durable identity for either design to reference.
- Confirmed live, consistent with `planner_agent`'s own documented reasoning: a DB unique index on `user_id` would have rejected every second AI profile (they all default to `0`), so uniqueness is enforced the same way `plan_template`'s name uniqueness is — a count check in the endpoint, not a schema constraint.
- `GET agent-profile`'s tenancy merge (person via `user.account_id`, AI via its own `account_id` column, combined with an `in` + `||` `where` clause) worked first try — no live surprises, unlike several earlier epics' XanoScript gotchas.
