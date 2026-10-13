# ROLE-1 — Actor Role Registry

**Epic ID:** ROLE-1
**Feature:** Roles are defined once and picked from a list, never typed.
**Status:** **Deferred (post-MVP)** — decided 2026-10-12 (D-42)
**Depends on:** OBS-1, GOV-1, VAL-1, STAGE-1
**Goal:** A named role (for example "Sales Coordinator") exists once per account. Journey-map rows and planner agents both point to it. Each role says whether it does **planned work**, which decides what the journey map requires and what the planner can schedule.

---

## Why deferred, and what the MVP uses instead

The MVP proves the loop without a shared role registry. Instead, each journey-map row (lens) gets a **"Does this row do planned work?"** switch (STAGE-1, US-STAGE-1-06), and the planner assigns any person. When this epic is built later it must:
- **Migrate** each lens switch into a role (one role per distinct name per account).
- Use a **normalized `name_key`** column for case-insensitive uniqueness (Xano cannot index `lower(name)`; review finding F4).
- Make the **role the single source of truth for `actor_type`**; the lens value is set from the role and validated to match (finding F13).
- For a lens with no role yet, fall back to the lens switch (finding F14).

## Context

Today an actor is a `journey_lens` row local to one map (`actor_type`, label, persona, goal, constraints). Nothing links the same role across maps, and nothing links a map's actor to a planner agent. Plan resolves "who does this" through the role, so the role must be a shared record.

`journey_lens.actor_type` values today: customer, internal, engineering, handoff, vendor, financial, operations, ai_agent, dev, custom, metrics.

## Existing Architecture (Do Not Break)

- `static/tables/8_journey_lens.xs` — all existing columns and rows stay; only a nullable reference is added.
- AI scaffold/fill tools that create lenses keep working (they may leave `actor_role_id` null until backfilled).
- Lens persona, goal and constraints stay on the lens (they are map-specific context).

## Non-Goals

- No cost-rate move (stays on the lens). No capacity model. No people-to-role scheduling rules (SCHED-1).

---

## Stories

### US-ROLE-1-01 — Tables `actor_role` and `agent_role`

**Files:** `static/tables/80_actor_role.xs`, `81_agent_role.xs`

- `actor_role`: `id`, `created_at`, `updated_at`, `account_id → account` (required), `name` (required, trimmed, display casing), `name_key` (required, `trim|lower`), `actor_type` (same enum as the lens), `does_planned_work` bool (required), `description` text, `is_active` bool default true.
- `agent_role`: `id`, `created_at`, `planner_agent_id → planner_agent`, `actor_role_id → actor_role`.
- Indexes: unique `(account_id, name_key)`; unique `(planner_agent_id, actor_role_id)`; btree `(account_id, is_active)`.
- `journey_lens.actor_role_id → actor_role` (nullable, additive).

**Acceptance:** duplicate role name (any case) in one account rejected; same name in another account allowed; existing lens rows unaffected.

### US-ROLE-1-02 — Default for "does planned work?"

- Function `defaultDoesPlannedWork(actorType)`: `internal` and `ai_agent` → **true**; every other type → **false**. Implemented in the frontend module and as a backend function.
- The user can flip the switch on any role.

**Acceptance:** creating a role without the field uses the default for its type; explicit values are respected.

### US-ROLE-1-03 — Role CRUD API

**File:** `apis/journey_map/<next>_actor_role_*.xs`

- List (active only by default), create, update (name, description, switch, type), archive.
- Deleting a role referenced by any lens or agent is blocked; the user archives instead.
- Archived roles stay readable on old maps and cannot be newly assigned.
- All endpoints scoped to the caller's account.

**Acceptance:** cross-account read/write returns not-found/denied; archived role cannot be assigned to a lens.

### US-ROLE-1-04 — Link lenses to roles (with safe backfill)

- Setting a lens's role updates `journey_lens.actor_role_id`.
- Backfill function: for a map, **dry-run first**, propose a role per lens (match existing role by name, else propose creating one with the type default); real run is idempotent and never changes lens text.

**Acceptance:** dry-run writes nothing; real run twice changes nothing the second time; map 178 clone yields roles for "Customer" (no planned work) and "Sales Coordinator" (planned work).

### US-ROLE-1-05 — Role picker in the journey-map UI

- Adding or editing a lens shows a **role picker** (list of active roles) plus **"+ New role"**. Role name is never free-typed into the lens.
- New-role dialog: name, type, and the **"Does this role do planned work? Yes / No"** switch preset by type.
- A customer-type role shows no required tags in the map (AUTH-1).

**Acceptance:** picking an existing role links it; creating a role from the picker works in one step; duplicate name shows an inline error.

### US-ROLE-1-06 — Link planner agents to roles

- API to add/remove `agent_role` rows for an agent (an agent can fulfil several roles).
- Planner shows each agent's roles (read-only chips in this epic).

**Acceptance:** an agent can hold many roles; the same pair cannot be added twice.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-ROLE-1-01 | Unit | `defaultDoesPlannedWork('internal')` / `'ai_agent'` | true |
| UT-ROLE-1-02 | Unit | Same for customer, handoff, metrics, vendor, operations, engineering, dev, financial, custom | false |
| UT-ROLE-1-03 | Unit | Role-name normalizer ("  Sales Coordinator ", "sales coordinator") | Same canonical key |
| FT-ROLE-1-01 | Functional (`workflow_tests/14_actor_roles.xs`) | Duplicate name same account, differing case | Rejected |
| FT-ROLE-1-02 | Functional | Same name in a second account | Allowed |
| FT-ROLE-1-03 | Functional | Create role without `does_planned_work` | Default applied by type |
| FT-ROLE-1-04 | Functional | Delete a role used by a lens | Blocked; archive succeeds |
| FT-ROLE-1-05 | Functional | Assign an archived role to a lens | Rejected |
| FT-ROLE-1-06 | Functional | Cross-account list/update/archive | Denied |
| FT-ROLE-1-07 | Functional | Backfill dry-run on map 178 clone | Proposes 2+ roles; DB unchanged |
| FT-ROLE-1-08 | Functional | Backfill run twice | Second run changes nothing |
| FT-ROLE-1-09 | Functional | Existing AI scaffold creates lens with null role | Still works |
| FT-ROLE-1-10 | Functional | Same pair added twice to `agent_role` | Rejected |
| E2E-ROLE-1-01 | UI | Add a lens by picking an existing role | Linked; no typing |
| E2E-ROLE-1-02 | UI | "+ New role" with type internal | Switch preset Yes; role appears in list |
| E2E-ROLE-1-03 | UI | New role named like an existing one | Inline error |

**Completion gate:** all pass; `workflow_tests/1–9` and existing e2e (`internal-actor`, `ai-agent-actor-fields`) green.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Table | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `actor_role` (80) | PK `id`; `account_id → account` (indexed) | `(account_id, name_key)` | name, actor_type, does_planned_work, account_id | **Restrict** if referenced by any lens or agent; **archive** instead |
| `agent_role` (81) | PK `id`; `planner_agent_id → planner_agent`; `actor_role_id → actor_role` (both indexed) | `(planner_agent_id, actor_role_id)` | both references | **Cascade** when the agent is deleted; role is archived, not deleted |
| `journey_lens.actor_role_id` | `→ actor_role` (indexed, nullable) | — | — | Restrict deleting a role in use |

Rules the schema cannot enforce (done by API guards): role and lens belong to the same account; an archived role cannot be newly assigned.

**Validation and friendly messages**

| Field / action | Rule | Friendly message | Code |
|---|---|---|---|
| Role name | 1–80 characters, trimmed, no HTML or control characters | "Give the role a short name, like 'Sales Coordinator'." | `E-ROLE-001` |
| Duplicate name | Unique per account, case-insensitive | "A role named '{name}' already exists. Pick it from the list or choose a different name." | `E-ROLE-002` |
| Delete a role in use | Blocked | "'{name}' is used by {n} maps or people. Archive it instead so existing work keeps its history." | `E-ROLE-003` |
| Assign an archived role | Blocked | "This role is archived. Pick an active role." | `E-ROLE-004` |
| Role from another account | Blocked | "That role isn't available here." | `E-ROLE-005` |

**Events logged** (`feature = ROLE-1`): `create_role`, `update_role`, `archive_role`, `link_lens`, `link_agent`, `backfill_dry_run`, `backfill_run`, each as `success`, `rejected` (with code) or `failure`.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-ROLE-1-G01 | Unit | Junk corpus through the role-name rule | Rejected correctly; valid names pass |
| FT-ROLE-1-G01 | Functional | Schema audit on tables 80 and 81 | Pass |
| FT-ROLE-1-G02 | Functional | Every rejection above | Friendly message, Reference, `rejected` event, nothing written |
| FT-ROLE-1-G03 | Functional | Backfill failure injected midway | No partial links |
| FT-ROLE-1-G04 | Functional | Integrity audit with a lens pointing to another account's role | Detected |

## Test Results

_Not yet run._
