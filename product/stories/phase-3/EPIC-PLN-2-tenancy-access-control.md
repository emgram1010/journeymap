# PLN-2 — Tenancy & Access Control

**Epic ID:** PLN-2
**Status:** Done (see Test Results) — seven guards live and verified against two real accounts
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

**2026-10-14 — Opus 5 build pass.** Seven guard functions and the planner
API group are live in workspace 1. Every case below was run against real
rows in two real accounts, not mocked.

> **Model note:** the build order marks phase-3 as Sonnet, but names PLN-2
> tenancy as one of the two phase-3 areas wanting an Opus review. This ran
> on Opus throughout (founder away, asked for work to continue), so the
> build and the review are the same pass.

### What shipped

| Function | Live id | File |
|---|---|---|
| `planner/resolve_actor` | 98 | `functions/planner/resolve_actor.xs` |
| `planner/assert_workspace` | 99 | `functions/planner/assert_workspace.xs` |
| `planner/assert_agent` | 100 | `functions/planner/assert_agent.xs` |
| `planner/assert_timeline` | 101 | `functions/planner/assert_timeline.xs` |
| `planner/assert_task` | 102 | `functions/planner/assert_task.xs` |
| `planner/assert_admin` | 103 | `functions/planner/assert_admin.xs` |
| `planner/assert_same_workspace` | 104 | `functions/planner/assert_same_workspace.xs` |
| `api_group "planner"` | 24 (`PE5iDldw`) | `apis/planner/api_group.xs` |

### Fixtures used

Account **3** (admin user 7 is account 4; member user **6** is account 3)
holds workspace 1 "Q1 Delivery Plan" and workspace 3 "Second Plan
(cross-workspace test)", agents 1 and 3, timeline 1, task 1. Account
**6** is the foreign account. User **5** has `account_id 0` — the broken
signup case.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-2-01 | ✅ `resolve_actor(6)` → `{user_id:6, account_id:3, role:"member"}`; `resolve_actor(7)` → `{user_id:7, account_id:4, role:"admin"}`. Same shape both roles |
| FT-PLN-2-02 | ✅ `resolve_actor(5)` (no account) → `ERROR_CODE_NOT_FOUND` |
| FT-PLN-2-03 | ✅ `assert_workspace(3, 1)` returns the row |
| FT-PLN-2-04 | ✅ `assert_workspace(6, 1)` (cross-account) and `assert_workspace(3, 99999)` (nonexistent) return **byte-identical** `{"message":"Not Found","error_type":"ERROR_CODE_NOT_FOUND"}` — the leak this story exists to prevent |
| FT-PLN-2-05 | ✅ `assert_agent(6,1)`, `assert_timeline(6,1)`, `assert_task(6,1)` all `Not Found` |
| FT-PLN-2-06 | ✅ `assert_admin("member")` → `ERROR_CODE_ACCESS_DENIED`; `assert_admin("admin")` → `{ok:true}` |
| FT-PLN-2-07 | ✅ `assert_same_workspace(1, 3)` → `ERROR_CODE_INPUT_ERROR`, "Entities must belong to the same workspace" |
| FT-PLN-2-08 | ✅ `assert_same_workspace(1, 1)` → `{ok:true, workspace_id:1}` |
| **Positive-path check** (not in the plan) | ✅ `assert_task(3, 1)` and `assert_agent(3, 1)` return the row **and** its workspace |

**Why that last row was added.** Every test in the plan above asserts a
*rejection*. A guard hard-wired to `throw` would have passed all eight and
blocked the entire planner. The positive path is now asserted for each
entity guard, so "it rejects" and "it still lets the right people
through" are both covered.

All eight cases were **re-run from scratch** after the functions were
re-pushed (see Deviations) — the earlier passes were against superseded
code and would not have been evidence for what is live now.

`npm test`: 213/213. `npm run lint`: exits 0. (Both unaffected — this
epic adds no frontend code.)

### Deviations

| Change | Why |
|---|---|
| Guards take `user_id` / `role` as inputs rather than reading `$auth` | A Xano **function** has no `$auth` of its own; only an endpoint does. Endpoints pass `$auth.id` into `resolve_actor` and the resulting `role` into `assert_admin`. This also makes all seven testable with `runWorkspaceFunction`, which is how every case above was proven |
| `assert_same_workspace` takes two `workspace_id`s, not "two or more entities" | US-PLN-2-04 says "two or more entities". Callers already hold each entity's `workspace_id` from the entity guard they just ran, so passing ids costs no extra query, and ids are what the comparison actually needs. A 3+ entity check is two calls |
| All seven re-pushed after first verification | The repo convention (rich header comment **plus** a `description =` field) does not round-trip — Xano merges the two. See `product/learning-fixes.md`. Fixed by dropping the redundant field; all cases re-run afterwards |

### Open, needs the founder

- **`inputerror` prefixes its message**: FT-PLN-2-07 returns
  `"Param:  - Entities must belong to the same workspace"`, not the clean
  sentence. VAL-1 requires friendly messages. This affects **every**
  existing `inputerror` guard (`guards/assert_state`, `assert_fresh`,
  `assert_not_archived`, `ops/build_diagnostic_bundle`), so it is a
  pre-existing, codebase-wide cosmetic issue, not new to PLN-2. **Not
  fixed here, deliberately:** PUB-1 proved `runWorkspaceFunction` distorts
  error shape (it appeared to strip `accessdenied` messages, which real
  HTTP did not), so this prefix may be an artefact of the test harness
  rather than the real response. It gets checked over real HTTP at PLN-3,
  when the first planner endpoint exists to check it with.

### Not done

- **`workflow_tests/planner_2_tenancy.xs` was not written**, for the same
  reason as PLN-1: no runner for workflow-test files is exposed to a
  session, so the file would be an unrunnable restatement of work already
  proven live. The table above is the evidence.
- **US-PLN-2-05's 401 case is not yet testable.** The group exists and is
  configured, but it has no endpoints until PLN-3. The epic already
  specifies this as a standing test in each later epic; PLN-3 runs it
  first.
