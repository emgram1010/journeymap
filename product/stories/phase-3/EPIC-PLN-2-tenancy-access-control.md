# PLN-2 — Tenancy & Access Control

**Epic ID:** PLN-2
**Status:** Planning
**Depends on:** PLN-1
**Goal:** One set of guard functions that every planner endpoint calls, so account isolation and role rules are enforced identically everywhere and are never re-implemented per endpoint.

---

## Context

Planner tables hang off `account`. A user belongs to one account (`user.account_id`) with role `admin | member`. Existing endpoints (e.g. `apis/journey_map/134_account_me_PATCH.xs`) resolve the user, then check account and role inline. The planner has ~25 endpoints; inline checks would drift. Guards go in shared functions.

## Existing Architecture (Do Not Break)

- `user.account_id`, `user.role`; auth via `auth = "user"` and `$auth.id`.
- `api_group "journey-map"` is untouched; planner uses a new `planner` group.

## Non-Goals

- No per-workspace membership or sharing; the account is the boundary.
- No new roles.

## Access matrix

| Operation | member | admin |
|---|---|---|
| Read anything in own account | ✅ | ✅ |
| Create / update / delete workspaces, agents, timelines, tasks | ✅ | ✅ |
| Update account rates (`planner_settings`) and model catalog | ❌ | ✅ |
| Anything in another account | ❌ (`notfound`) | ❌ (`notfound`) |

---

## Stories

### US-PLN-2-01 — `planner_resolve_actor` function

**File:** `functions/planner/resolve_actor.xs`

- Input: none (reads `$auth.id`). Output: `{user_id, account_id, role}`.
- Errors: `notfound` if the user has no `account_id`.

**Acceptance:** Returns the same shape for admin and member; user with null account → `notfound`.

### US-PLN-2-02 — Entity guards

**Files:** `functions/planner/assert_workspace.xs`, `assert_agent.xs`, `assert_timeline.xs`, `assert_task.xs`

- Each takes `{account_id, <entity>_id}`, returns the row, and returns `notfound` when the row is missing **or belongs to another account** (never `accessdenied`, so existence of other accounts' data is not revealed).
- Agent/timeline/task guards resolve account through `workspace_id → planner_workspace.account_id`.

**Acceptance:**
- Cross-account id → `notfound`, identical to a nonexistent id.
- Guards perform one lookup chain, no N+1.

### US-PLN-2-03 — Admin guard

**File:** `functions/planner/assert_admin.xs`

- Input: `role`. `accessdenied` unless `admin`, message `"Only account admins can change planner rates and models"`.

**Acceptance:** Member → `accessdenied`; admin → passes.

### US-PLN-2-04 — Cross-reference guard

**File:** `functions/planner/assert_same_workspace.xs`

- Input: two or more entities (e.g. a task + a target timeline, an agent + a timeline). Rejects when their `workspace_id`s differ with `inputerror` `"Entities must belong to the same workspace"`.

**Acceptance:** Moving a task into a timeline of another workspace (same account) is rejected.

### US-PLN-2-05 — Planner API group and auth baseline

**File:** `apis/planner/api_group.xs`

- `api_group "planner"`; every endpoint declared `auth = "user"`. Canonical id assigned by Xano on first push.

**Acceptance:** An unauthenticated call to any planner endpoint (added in later epics) returns 401; documented as a standing test in each later epic.

---

## Functional Test Plan

`workflow_tests/planner_2_tenancy.xs`. Needs two accounts (A: admin + member, B: admin).

| ID | Case | Expected |
|---|---|---|
| FT-PLN-2-01 | `resolve_actor` as A-admin, A-member | Correct account and role |
| FT-PLN-2-02 | User with no account | `notfound` |
| FT-PLN-2-03 | `assert_workspace` with A's workspace as A-member | Returns row |
| FT-PLN-2-04 | Same call with B's workspace id as A | `notfound` (same message as a random id) |
| FT-PLN-2-05 | `assert_agent`/`timeline`/`task` with B's ids as A | `notfound` |
| FT-PLN-2-06 | `assert_admin` as member | `accessdenied` |
| FT-PLN-2-07 | `assert_same_workspace` with entities from two workspaces of one account | `inputerror` |
| FT-PLN-2-08 | `assert_same_workspace` with entities from one workspace | Passes |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`.

## Test Results

_Not yet run._
