# Epic-13 — Who is in the account, and what they can reach

Created 2026-10-22, from a founder session that started with one question —
*"is user management and roles supported, specifically showing on my web app?"* —
and ended with a live feasibility probe against Xano.

The feature, in the founder's words:

> I have full admin and I have access to the intelligence layer, planning and
> execution, so that's what I want you to set it up with. If you're an admin you
> have the ability to add, remove, all that stuff for users, and provide them
> with permissions to access those three modules. We'll get a little bit more
> granular in the future.

## Where this stands, 2026-10-22

USR-1 is built and live. The founder then asked for the second half in the
same session:

> I want to be able to enable CRUD for the user, update the user info, delete
> the user, add users, read users, along with their roles. […] And we also,
> for the users, along with enabling users, enabling their roles, we also want
> to be able to associate permissions to the users. The permissions is
> specifically on … if they have access to the intelligence layer and or the
> planning layer and or the execution layer.

The CRUD half landed in USR-1 as stories 02, 07, 08 and 09. **The permissions
half is USR-2, and it is next.** It is marked Opus work and it depends on
USR-1's lockout rules being green, which they now are.

Later the same day, testing the live Team page, the founder asked for the rule
to point the other way as well:

> What about enforcing that any user using the intelligence layer, being an
> agent, that's assigned plan tasks or that execute tasks in the execution
> layer, must have a user account and must be assigned planning and execution
> permissions.

…and clarified immediately: *"when I mean an agent, I mean a person, not an AI
agent."* That is a question about the **subject** of an assignment rather than
the caller, so it is **USR-3**, written up 2026-10-22 and blocked on USR-2.
The founder also settled the default in the same exchange: **all three modules
off for a new user**, with the admin ticking them on.

## Epics

| Epic | What it enables | Model | Status |
|---|---|---|---|
| [USR-1 — People and roles](EPIC-USR-1-people-and-roles.md) | An admin can see, add, correct, re-role, deactivate and remove the people in their account, from an admin-only Team page, without the account ever locking itself out | Sonnet 5.5 | ✅ **Built 2026-10-22** — 9 stories, 485/485 tests green. Two endpoints await a push |
| [USR-2 — Module access](EPIC-USR-2-module-access.md) | Each person is granted Intelligent Layer, Planner and/or Execution; the server refuses what they were not granted, and the app only shows what they can reach | **Opus 5.5** | 🟡 **Stories 01, 02, 05, 06 done and proven live 2026-10-23** (table 134, functions 219–221, endpoints 590–591; 517/517 tests). 🔴 **Story 03 is not done — no middleware is attached, so nothing is enforced yet.** Story 04 not started |
| [USR-3 — Only real, permitted people do the work](EPIC-USR-3-only-real-people-do-the-work.md) | A person a plan hands work to must be a real user account holding the right grant. AI agents are explicitly out of scope | **Opus 5.5** | 📋 Written 2026-10-22, blocked on USR-2 — there are no grants to check yet |

**Model note for the founder:** USR-1 is ordinary build work — Sonnet 5.5 is
fine. USR-2 is a guards-and-tenancy epic, which `CLAUDE.md` marks as Opus work,
and it is the one that can lock everybody out of the product. Switch with
`/model` before starting USR-2, and run an Opus review pass after it.

## What already exists, verified live 2026-10-21

More than the founder expected. Almost none of it is visible.

| Thing | State |
|---|---|
| `user.role`, an enum of `admin` / `member` | **Exists**, on the `user` table, populated |
| `user.is_platform_admin` | **Exists**, separate and stricter — spans all accounts |
| `user.account_id` | **Exists** — every user already belongs to one account |
| `GET account/my_team_members` | **Exists** — but its `output` omits `role`, so a Team page cannot show it |
| `POST admin/user_role` | **Exists** — admin-only, same-account, writes an `event_log` entry |
| `functions/planner/assert_admin` | **Exists** — the only role gate in the product |
| `functions/ops/require_platform_admin` | **Exists** — gates the Health page and cross-account tools |
| Anything about roles in the web app | **Nothing**, except one route redirect on `is_platform_admin` |

So `role` is fetched on every page load by `auth/me`, carried into the client,
and then **never read**. A member and an admin see an identical application
today, except for two planner settings (account rates and the model catalogue).

## The three modules

They already exist as the three items in the sidebar, and map cleanly onto
routes and API groups:

| Module | Key | Routes | Backend |
|---|---|---|---|
| Intelligent Layer | `intelligence` | `/architectures`, `/architectures/:id`, `/maps/:id`, `/dashboard` | `journey_map` API group (~95 endpoints) |
| Planner | `planning` | `/planner` | `planner` API group (plan / agent / timeline / task endpoints) |
| Execution | `execution` | `/perform` | `planner` API group (job / schedule / perform endpoints) |

**Planner and Execution share one API group.** That is the single awkward fact
this epic has to work around, and it is why USR-2 has a story of its own for it.

## The enforcement decision, and the probe behind it

The obvious implementation is to add a guard call to the top of every protected
endpoint, the way `assert_owns` is used today. That is roughly **150 hand
edits**, and the failure mode is silent: a forgotten guard is an open door that
looks exactly like a closed one.

The alternative is Xano **middleware** — logic attached once to an API group and
run automatically before every endpoint in it. Nobody has to remember anything,
and a new endpoint is protected the day it is created.

The workspace had never used middleware, and Xano's documentation tool has no
middleware section, so on 2026-10-21 a throwaway middleware, API group and
endpoint were created in workspace 1 to settle it. **All scratch objects were
deleted afterwards; the workspace is back to zero middleware.**

### What the probe proved

| Question | Answer |
|---|---|
| Does middleware work on this Xano plan? | **Yes.** Created and ran. (Worth asking — `redis.*` is rejected outright on this plan) |
| Can it be attached without the dashboard? | **Yes**, at API-group level, in XanoScript |
| Can it refuse a request? | **Yes** — returned `403 ERROR_CODE_ACCESS_DENIED` with the right message shape, and the endpoint never ran |
| Can it tell who is calling? | **Yes** — `$auth.id` resolves, and a `db.get user` inside the middleware returned `{id: 6, account_id: 3, role: "member"}` |
| Can it see the request's inputs? | **Yes** — `$input.vars` held the endpoint's resolved inputs |

`$auth` working inside middleware is the fact the whole design rests on. It was
tested with a real HTTP call carrying a real bearer token, not with
`runWorkspaceFunction`.

### 🔴 The trap, and it is a bad one

A middleware's `exception_policy` defaults to **`"silent"`**, and with it a
thrown `accessdenied` is **swallowed and the request proceeds**. The probe
demonstrated exactly that: a `precondition (false)` with an access-denied error
returned `HTTP 200` and the endpoint's normal body.

Worse, the value is **not validated**. Submitting `"abort"` and submitting
`"nonsense_value_to_learn_the_enum"` both came back stored as `"silent"`, with
no error. Only `"critical"` stuck, and only then did the request get its 403.

**A permission middleware written without `exception_policy = "critical"` is a
permission middleware that permits everything, and nothing anywhere says so.**
Every middleware in USR-2 must set it explicitly, and a test must prove a denial
really returns 403 — never infer it from the code reading correctly.

### Syntax, since it is written down nowhere

Attach at the group level:

```xs
api_group planner {
  canonical = "PE5iDldw"
  middleware = {pre: [{name: "usr_require_module_planning"}]}
}
```

Found by elimination against the parser's own errors: `middleware` wants
`{"pre?": {}, "post?": {}}`, and each of `pre` / `post` wants `static:object[]`
of `{name: "..."}`. A plain text array, an int array, a bare identifier and a
`middleware { ... }` block are all rejected.

The middleware itself gets two inputs injected automatically, whether or not you
write them: `json vars` (the endpoint's inputs) and `enum type` (`pre` / `post`).

`middleware` is also accepted as a property on an individual `query`, with what
is almost certainly the same shape — **not proven**, and USR-2 story 04 proves
it before depending on it.

## Build order

1. **USR-1** first. It establishes who exists and who is an admin. Module grants
   are meaningless without it.
2. **USR-2** second, and not before USR-1's lockout rules are green — the
   enforcement epic is the one that can lock the founder out of their own
   product.
3. **USR-3** third, and not before USR-2 — every rule in it reads a grant, and
   there are no grants until USR-2 ships.

Within USR-2, the middleware is built and proven on **one** API group before it
is attached to the others.

Within USR-3, the Health-page list of unlinked person-agents is built **before**
the refusals are turned on: 13 of the 20 person-agents in the product have no
login behind them today, and they should be visible before they start causing
refusals rather than after.

**Model note:** all three epics after USR-1 are Opus work. USR-2 can lock
everyone out of a module; USR-3 sits on the Planner's write path.

## Why not just hide the menu items

Because hiding a menu item is not a permission. The routes are reachable by
typing a URL, and every endpoint behind them answers an ordinary `fetch` from
anyone holding a valid token. The nav work in USR-2 exists so the product is not
confusing; the middleware exists so it is not open. Neither substitutes for the
other, and the UI half must never be shipped alone — that is the shape that
*looks* finished and is not.

## Relationship to the other open epics

- **GOV-1 / SEC-1** already established account scoping (`assert_same_account`,
  `visible_map_ids`). This epic sits **on top** of that, not instead of it: a
  module grant says *which rooms you may enter*, tenancy says *whose things you
  may touch once inside*. Both still run.
- **OBS-1** owns `is_platform_admin` and the Health page. Untouched here, and
  deliberately kept separate — a platform admin is not an account admin.
- **PLN-2** owns `planner/assert_admin`. USR-1 does not replace it; the two
  admin-only planner areas keep working exactly as they do.

## Still open

- 🔴 **The founder's own user (`Jav`, id 2) has `is_platform_admin = false`**,
  so the Health page is currently unreachable by the only person meant to see
  it. One-field fix, deliberately has no endpoint (OBS-1 made it un-writable by
  design), so it is a direct database edit. Confirm with the founder first.
- **Granularity.** The founder has said per-action rights ("a little bit more
  granular") are wanted later. USR-2's table is shaped to take them without a
  migration, but no story builds them.
- **Invitation email.** ✅ **Decided 2026-10-22: no email for now.** The admin
  sets an initial password and passes it on, in the founder's words *"It's all
  test. Go live will enhance and secure the create user process."* A real
  invitation email stays deferred. See USR-1, story 02.
- ✅ **All five USR-1 endpoints are live** (585–589) and exercised end to end
  on test account 6. The live run found two bugs that reading could not have:
  a `required` input making the endpoint's own validation unreachable, and
  `db.del` throwing a bare 404 on a missing row, which meant the delete never
  worked at all. Both fixed, both written into `product/ai-learnings.md`.
