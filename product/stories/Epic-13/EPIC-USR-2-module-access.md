# EPIC-USR-2 — Module access

**Epic:** Epic-13 — Who is in the account, and what they can reach
**Status:** 🟢 **Stories 01, 02, 05 and 06 are done and proven live, 2026-10-23.**
Table 134, functions 219–221 and endpoints 590–591 are pushed and exercised
over real HTTP. 517/517 unit tests, `tsc` clean. Two live bugs found and fixed
— see Test Results.
🔴 **Story 03 is NOT done: no middleware is pushed and nothing is attached**,
so a module grant is not yet enforced on any endpoint. Story 04 has not
started. Until story 03 lands, this epic grants and displays access without
refusing anything — the shape the epic's own second rule warns about. Details
in **Still open**.
**Model:** **Opus 5.5.** `CLAUDE.md` marks guards and tenancy as Opus work, and
this epic can lock every user out of the product. Switch with `/model` before
starting, and run an Opus review pass after it.
**Depends on:** USR-1, and specifically USR-1 story 05 being green. Do not start
until an account cannot lock itself out.

---

## Why

Three modules exist in the sidebar — Intelligent Layer, Planner, Execution — and
every signed-in user can reach all three. There is no way to give someone
Execution without also giving them the whole Intelligence Layer, and nothing on
the server would notice if they went there anyway.

This epic makes each module something a person is **granted**, and makes the
server refuse what was not granted.

## The rule

> A **grant** says which rooms you may enter. **Tenancy** says whose things you
> may touch once inside. Both still run, in that order, on every request.

Nothing in this epic replaces `guards/assert_same_account`,
`journey/visible_map_ids`, or `planner/resolve_actor`. A user with the Planner
grant still only sees their own account's plans. Losing sight of that would
turn a permission epic into a tenancy regression.

A second rule, equally load-bearing:

> Hiding a menu item is not a permission.

The nav work here exists so the product is not confusing. The middleware exists
so it is not open. **The UI half must never ship without the server half** —
that is the shape that looks finished and is not.

## 🔴 What the feasibility probe found (2026-10-21)

The full probe is written up in [the Epic-13 README](README.md). The three facts
this epic is built on:

1. **Middleware works on this Xano plan**, can be attached from XanoScript, and
   returns a real `403 ERROR_CODE_ACCESS_DENIED` with the endpoint never running.
2. **`$auth.id` resolves inside a pre-middleware.** A `db.get user` in the
   middleware returned `{id: 6, account_id: 3, role: "member"}` on a real HTTP
   call with a real bearer token. The whole design rests on this.
3. **`exception_policy` defaults to `"silent"`, and silent means the denial is
   swallowed and the request proceeds.** Worse, the field is not validated:
   `"abort"` and a deliberate nonsense string were both stored as `"silent"`
   with no error. Only `"critical"` stuck.

> **A permission middleware without `exception_policy = "critical"` permits
> everything, and nothing anywhere tells you.**

Every middleware this epic writes sets it explicitly, and story 03's gate is a
real 403 over HTTP — never "the code reads correctly".

## The awkward fact

**Planner and Execution share the `planner` API group.** Middleware attaches to
a group, so one attachment cannot tell the two apart. Story 04 exists only to
resolve this, and it is the story most likely to change shape once started.

## The data model

### New table — `user_module_access`

One row per (user, module). Absence of a row means **not granted**.

| Field | Type | Notes |
|---|---|---|
| `id` | int | primary |
| `created_at` | timestamp | `=now`, private |
| `user_id` | int | FK `user` |
| `account_id` | int | FK `account`. Denormalised, so a tenancy filter needs no join |
| `module` | text | `intelligence` \| `planning` \| `execution` |
| `granted` | bool | `=false` |
| `granted_by_user_id` | int? | FK `user` |
| `granted_at` | timestamp? | |

**Indexes:** primary on `id`; `btree|unique` on (`user_id`, `module`); `btree`
on `account_id`.

**Why `module` is text and not an enum or a foreign key:** adding a fourth
module later becomes a configuration change, not a schema migration. The
allow-list lives in one function so the validation is still strict.

**Why a `granted` bool and not row-presence:** revoking by deleting the row
would throw away who granted it and when. A revoke flips the bool and writes an
event; the history survives.

**Reading it safely:** `granted` is a bool, so `== null` is worse than useless —
`false == null` is `true` in this engine (`CLAUDE.md`, VAR-1). Test
`granted == true` explicitly. A missing row is **not granted**, and that must be
an explicit branch, not an inference from a falsy value.

## Error codes

| Code | Means | HTTP |
|---|---|---|
| `E-USR-006` | You do not have access to this module | 403 |
| `E-USR-007` | Unknown module key | 400 |
| `E-USR-020` | You cannot change your own module access | 403 |

`E-USR-001` … `E-USR-005` and `E-USR-008` belong to USR-1 and are reused
unchanged — in particular `E-USR-001` for "you are not an admin" when a member
tries to grant something, and `E-USR-005` for a switched-off user, which this
epic's middleware now enforces on every request rather than only at sign-in.

**`E-USR-020` was not in this epic's first draft.** The self-change rule was
going to reuse `E-USR-004`, until that code's catalogued message was read
back: *"You can't change your own role or switch yourself off."* That is a
different sentence about a different action, and `errorCodeRegistry.test.ts`
compares live messages against the catalog precisely to catch one code growing
a second meaning — it caught exactly this during USR-1 and `E-USR-015` had to
be minted. So `020`, out of sequence (`016`–`019` belong to USR-3), because a
code is an identifier and not a position in a queue. One code means one thing
(GUARD-1-01).

---

## Stories

### US-USR-2-01 — Grants exist, and nobody loses access on the day this ships

**As the** founder
**I want** the permission table created and pre-filled for everyone already here
**So that** turning enforcement on changes nothing for existing users.

```gherkin
Scenario: The table holds one row per user per module
  Given a user and three modules
  Then at most three rows can exist for them
  And a second row for the same user and module is rejected by the database

Scenario: Everyone who exists today keeps everything
  When the backfill runs
  Then every existing active user has all three modules granted

Scenario: A brand-new user starts with nothing
  When a user is created after this epic
  Then they have no granted modules until an admin grants one

Scenario: An unknown module key is refused
  When a grant names a module that is not one of the three
  Then it is refused with E-USR-007 and nothing is written
```

**Method:** new table; `functions/usr/module_keys` holding the allow-list; a
backfill function run **against a clone first**.

**Counter-measures:**
- 🔴 **Test the backfill on a clone of the live data before running it**
  (`CLAUDE.md`). A backfill that misses users is an outage for those users the
  moment story 03 lands.
- 🔴 **`db.patch` and `db.del` with `field_name`/`field_value` touch only the
  FIRST matching row.** The backfill writes many rows: `db.query` them and loop,
  writing each by `id`, inside a `db.transaction`.
- The unique index on (`user_id`, `module`) is the real guard against double
  grants. Build it with the table, not later.
- Count rows before and after the backfill and compare against the user count
  times three. The OBS-1 heartbeat ran for eight hours writing nothing and was
  caught only by comparing counts — not by trusting a reported success.

**Done when:** every existing active user has three granted rows, proven by a
count query, not by the backfill's own report.

---

### US-USR-2-02 — An admin grants and revokes modules

**As an** admin
**I want** three switches per person on the Team page
**So that** I can decide what each person can reach.

```gherkin
Scenario: Granting
  Given a member with no access
  When I switch on Execution for them
  Then their row shows Execution granted
  And the grant is logged with who granted it

Scenario: Revoking
  When I switch Execution off
  Then it shows as not granted
  And their work is untouched

Scenario: A member cannot grant anything
  Given I am a member
  When I call the grant endpoint directly
  Then it is refused with E-USR-001, and the refusal is logged

Scenario: Granting across accounts
  When I try to grant a module to someone in another account
  Then it is refused with E-USR-002, which does not confirm they exist

Scenario: Several changes at once
  When I change two modules for one person in one action
  Then both apply, or neither does
```

**Method:** `POST admin/user_module_access`, taking **one** `{user_id,
module, granted}`. Admin-gated through `usr/assert_team_admin`. Team page gains
a "Can reach" column with three checkboxes per row.

**⚠️ CHANGED FROM THE DRAFT: one module per call, not a list.** The draft
specified a list applied in one transaction, and the scenario "several changes
at once" below is what is left of it. The reason for the change is worth
keeping:

> The Team page has three checkboxes per person and each click is one change,
> so a list was never going to arrive with more than one item in it. Supporting
> one anyway meant a `foreach` inside a `db.transaction` — and while
> `db.transaction` is confirmed to mix tables and verbs, and a `conditional` is
> confirmed to nest inside one, a **`foreach` inside one is not proven in this
> workspace**. Choosing an unproven construct to solve a problem the UI cannot
> produce is how an endpoint acquires a failure mode nobody asked for.

With one row to write, atomicity across modules is not a state that can exist,
so the "all, or none" counter-measure below is satisfied by there being nothing
to split. The scenario is kept, marked as answered this way rather than
deleted.

**Counter-measures:**
- 🔴 **Multiple grants in one call means a transaction.** A half-applied
  permission change is the worst outcome of the three (all, none, some).
- 🔴 **"Field omitted" and "field sent as false" are different**, and `$input`
  cannot tell them apart — an omitted optional bool arrives as `false`
  (`CLAUDE.md`, STAGE-1). Use `util.get_raw_input` and `|has:"module"` on each
  array element, captured during a first pass into the loop item itself.
- Only branch on the loop item inside a `foreach`. A `conditional` whose
  condition reads a variable `var.update`d earlier in the same iteration
  **silently discards everything the branch writes** (`CLAUDE.md`, PLN-6).
- Revoking must not delete, archive or reassign any of that person's work.
- Do not let an admin revoke their own Intelligent Layer access while they are
  the only admin — see story 06.

---

### US-USR-2-03 — The server refuses a module you were not granted

**As the** founder
**I want** the refusal to happen on the server, automatically, for every endpoint
**So that** a permission is real and a new endpoint is protected the day it exists.

```gherkin
Scenario: A granted user is unaffected
  Given a user granted the Intelligent Layer
  When they call any journey-map endpoint
  Then it behaves exactly as before

Scenario: An ungranted user is refused
  Given a user not granted the Intelligent Layer
  When they call a journey-map endpoint directly with a valid token
  Then they get 403 with E-USR-006
  And the endpoint never runs

Scenario: The refusal is a real HTTP 403
  Then it is proven by an HTTP call, not by reading the middleware's code

Scenario: A new endpoint is protected without being touched
  Given an endpoint added to the group after this story
  Then an ungranted user is refused from it too

Scenario: Deactivated users are refused everywhere
  Given a user deactivated in USR-1
  Then every request is refused, not only sign-in

Scenario: Public and auth endpoints still work
  Then sign-in, sign-up, magic link and password reset are unaffected
```

**Method:** `middleware usr_require_module_<key>`, one per module, each:
resolves `$auth.id` → user → `account_id`; reads `user_module_access`;
refuses with `E-USR-006` if not granted; **sets
`exception_policy = "critical"`**.

Attach to the `journey_map` group first, prove it, then proceed.

**Counter-measures:**
- 🔴 **`exception_policy = "critical"`, verified after the push.** The default
  swallows the denial. Read the stored XanoScript back after writing and
  confirm the value survived, because an invalid value is silently replaced
  with `"silent"`.
- 🔴 **Attach to one group, prove it, then the rest.** Never attach to all
  three in one change.
- 🔴 **Do not attach anything to the Authentication group.** A middleware that
  needs `$auth` on the endpoints that create `$auth` is a lockout.
- 🔴 **Commit before attaching.** This is the first destructive moment in
  Epic-13; the rollback is detaching, and it needs to be one revert away.
- The middleware runs on **every** request in the group, so it is one extra
  `db.get` per call. Measure it on the journey-map group before accepting it.
- Deactivation (USR-1 story 04's open half) belongs in the same middleware, as
  a single shared pre-check — not copied into three.

**Done when:** a test user without the Intelligent Layer grant gets a real
`403 E-USR-006` from a real `curl` against a real journey-map endpoint, and a
granted user gets a normal response from the same call.

---

### US-USR-2-04 — Planner and Execution are told apart

**As the** founder
**I want** Planner access and Execution access to be genuinely separate
**So that** a performer can be given Execution without being given the Planner.

```gherkin
Scenario: Execution without Planner
  Given a user granted Execution but not Planner
  Then every perform endpoint works
  And every plan, agent and timeline endpoint is refused with E-USR-006

Scenario: Planner without Execution
  Given the reverse
  Then the reverse holds

Scenario: Each endpoint is accounted for
  Then every endpoint in the planner group is classified as one or the other
  And none is left unclassified
```

**Method:** three candidate approaches, in order of preference. **Prove one
before writing the story's code.**

1. **Per-endpoint attachment.** `middleware` is accepted as a property on an
   individual `query`, with what is almost certainly the group's shape.
   Unproven. Prove it with a scratch endpoint first; if it works, this is the
   cleanest answer and the group keeps only the shared deactivation check.
2. **Split the group.** Move the execution endpoints into their own API group.
   Correct and permanent, but it changes their base URL, so every frontend call
   site must move with them — and `webapp/protype-2/src/xano.ts` already has
   history here: `/ops/*` calls were pointed at the wrong group for weeks and
   404'd silently (APP-1).
3. **One middleware, branching on the request.** Only viable if the middleware
   can see which endpoint it is running for. The probe confirmed it sees the
   endpoint's **inputs**, not its name or path. Treat as unavailable unless
   proven otherwise.

**Counter-measures:**
- 🔴 **Enumerate every endpoint in the planner group and classify it, in a
  table in this file, before writing any code.** An unclassified endpoint
  defaults to the stricter grant, never to open.
- If approach 2 is chosen, `getApiGroup` the new canonical and wire
  `xano.ts` with an explicit base URL constant, exactly like
  `getXanoOpsBaseUrl()`. Do not assume one base URL covers it.
- 🔴 **Static paths can be shadowed by a sibling dynamic path** in the same
  group and verb (`CLAUDE.md`, PLN-9: endpoint 210 has never once executed).
  Moving endpoints between groups changes which siblings they have — re-check
  any static segment after a move.

---

### US-USR-2-05 — The app shows only what you can reach

**As a** user
**I want** the app not to offer me doors that are locked
**So that** I am not clicking into refusals.

```gherkin
Scenario: The sidebar reflects grants
  Given a user granted only Execution
  Then the sidebar shows Execution alone

Scenario: Typing the URL does not get you in
  When they navigate directly to /planner
  Then they are redirected, and the endpoints refuse them anyway

Scenario: Landing somewhere real
  When they sign in
  Then they land on a module they actually have

Scenario: Someone with nothing gets an explanation
  Given a user with no grants
  Then they see a page telling them to ask their admin, not a crash or a loop

Scenario: A refusal from the server is shown as a sentence
  Then E-USR-006 renders as plain language, not a code
```

**Method:** grants come from **`GET user_module_access`**, the side table's
own endpoint, read through one shared cache (`team/moduleGrantsCache.ts`) and
one hook (`useMyModules`). `AppLayout`'s `NAV_ITEMS` gains a `module` key and
filters on it; `ModuleRoute` in `main.tsx` mirrors the existing `AdminRoute`
and `AccountAdminRoute`; `/no-access` is the terminal page.

**⚠️ CHANGED FROM THE DRAFT: not on `auth/me`.** The draft put grants on
`auth/me` alongside `role`, and this file's own counter-measure warned that
doing so changes the highest-volume response in the app — one that has already
been fixed once for carrying more than it needed. The side-table endpoint
already existed for the Team page, it is account-scoped by the server, and the
caller's own rows are simply the ones carrying their id. One extra fetch on the
pages that gate themselves is the cheaper mistake, and `auth/me` is left alone.

🔴 **The UI fails OPEN, deliberately, and this is the decision in this story
most likely to look like a bug to a reviewer.** If the grants fetch errors,
`useMyModules` reports all three modules as held. The reasoning:

- The hook decides **what the menu shows**. It authorises nothing. Every
  endpoint behind every one of those doors runs `usr/assert_module_access`
  itself and refuses with `E-USR-006` whatever the browser believes.
- Failing closed turns one failed request into an app with no navigation at
  all, and tells a user with real access to go and ask their admin — a worse,
  more confusing and less recoverable outcome than a menu item that refuses
  when clicked.

Closed on the server, open in the chrome. `failed` is returned so `/no-access`
can say "we could not check" instead of asserting something it does not know.

**Counter-measures:**
- 🔴 **The no-grants case must not loop.** Every redirect target is itself
  gated; without an explicit terminal page this is an infinite redirect. Write
  that test first.
- Adding grants to `auth/me` changes the highest-volume response in the app.
  Keep it to ids and keys — that endpoint has already been fixed once for
  logging whole user records on every page load.
- This story is **not** shippable on its own. It is only meaningful behind
  story 03.

---

### US-USR-2-06 — A refusal is never silent

**As the** founder and only support person
**I want** every denial recorded and visible
**So that** "why can't they get in?" is answerable from the Health page.

```gherkin
Scenario: Denials are logged
  When the middleware refuses a request
  Then a "rejected" event records the user, the module and E-USR-006

Scenario: Grant changes are logged
  Then each grant and revoke records who did it, to whom, and the before and after

Scenario: The Health page surfaces a spike
  Then a burst of E-USR-006 refusals is visible there

Scenario: An admin cannot strand themselves
  Given I am the only admin
  When I revoke my own last module
  Then it is refused

Scenario: Logging never blocks the request
  Then a failure to write the event does not turn a permitted call into a refusal
```

**Method:** extend `event_log` through the existing `create_event_log` and the
`ops/log_event` path that `require_platform_admin` already uses for refusals.
No second log.

**Counter-measures:**
- 🔴 **One `db.get` plus one event write on every request** is the real cost of
  logging inside middleware. Log **refusals** always; do not log every
  successful permission check, or `event_log` becomes the product's largest
  table within a week.
- Log keys and ids, never whole records.
- 🔴 **`db.patch` on a `json` column MERGES rather than replaces** (`CLAUDE.md`
  — the cleanup that reported success over ~2,600 rows and changed nothing).
  Any in-place metadata correction is two patches: `null`, then the value.

---

## MVP scope

**In:** all six stories. This epic does not have a meaningful subset — grants
without enforcement is theatre, and enforcement without the UI is a product
nobody can administer.

**The one ordering rule:** story 03 is built and proven on a single API group
before it is attached to any other.

**Deferred:** per-action rights inside a module (view vs edit vs publish);
per-map or per-plan sharing; module access for the AI agents and MCP tools;
time-limited grants; a self-service request-access flow.

**Deliberately not in this epic, because it is USR-3:** requiring the person a
plan hands work to be a real, granted user. Every story here asks *"may this
caller enter this module?"*; that question is about the **subject** of an
assignment, it needs the grants this epic creates, and it has its own write
paths and its own thirteen legacy rows. See
[USR-3](EPIC-USR-3-only-real-people-do-the-work.md).

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | Unchanged and still enforced. A grant is checked **before** tenancy, never instead of it. `assert_same_account`, `visible_map_ids` and `resolve_actor` all keep running |
| Validation | Module keys checked against one allow-list function (`E-USR-007`); grant changes validated as a set and applied in a transaction |
| Error codes | `E-USR-006`, `E-USR-007` added to `src/ops/errorCatalog.json`. `E-USR-001`/`002` reused unchanged |
| Events | Every refusal logs `rejected`; every grant and revoke logs before and after. Successful permission checks are deliberately **not** logged, for volume |
| Table constraints | One new table, `user_module_access`, unique on (`user_id`, `module`). No change to `user` |
| Delete behaviour | Revoking flips a bool. Nothing is deleted, and no work owned by that user is touched |
| Rollback | Detaching the middleware from a group restores previous behaviour immediately and completely. Commit before the first attachment; that commit is the rollback point |
| No silent failure | 🔴 The whole epic turns on this: `exception_policy = "critical"` on every middleware, re-read from the live definition after each push, with a real HTTP 403 as the proof |
| Testing | Every live exercise runs on a **test account**, never the founder's own and never map 178. Denials proven over real HTTP with a real bearer token, never via `runWorkspaceFunction` |

## Test Results

**`npm test`: 517/517 pass. `npx tsc --noEmit`: clean.** 32 of those are new —
`UT-USR-2-01` … `UT-USR-2-32` in `src/team/teamModel.test.ts`, which is now 82
cases over USR-1 and USR-2 together.

**Exercised live on test account 6** (user 9, admin) over real HTTP with a real
bearer token, 2026-10-23. The account was returned to its original state
afterwards: one user, three grant rows, no probe fixtures left.

| Story | Tests | Result |
|---|---|---|
| 01 | Unique index rejects a duplicate; backfill count equals users × 3; new user has none; unknown key refused | ✅ **Live.** Table 134 with the unique index on (`user_id`, `module`); backfill wrote 3/3 for account 6 and the rows were counted in the table, not taken from its report; a second run wrote 0 and found 3 (idempotent); unknown key refused. Unit: `UT-USR-2-14`, `-15`, `-25`, `-26` |
| 02 | Grant; revoke; member refused; cross-account refused as notfound; several changes at once | ✅ **Live, 8/8** — see the table below. Unit `UT-USR-2-20`–`-32`. "Several changes at once" is answered by there being one row per call |
| 03 | **Real 403 E-USR-006 over HTTP**; granted user unaffected; new endpoint protected untouched; deactivated user refused on every call; auth endpoints unaffected; `exception_policy` re-read as `critical` | 🔴 **Not done.** The RULE is live and proven — `usr/assert_module_access` refused user 9 for `planning` with no grant row, then allowed the identical call once the row existed. But no middleware is pushed and nothing is attached, so no endpoint actually runs it yet |
| 04 | Execution-only user passes perform and fails planner; the reverse; every planner-group endpoint classified | 🔴 Not started. The two middleware files exist and are attached to nothing; the approach is still unchosen because it depends on a live probe |
| 05 | Sidebar filtered; direct URL redirected; sign-in lands somewhere real; **no-grants page does not loop**; refusal renders as a sentence | 🟡 Built and typechecked: `module` on `NAV_ITEMS`, `ModuleRoute`, `/no-access` ungated and nothing redirecting away from it. `UT-USR-2-16`–`-19` cover the predicate. The loop case is structural, not yet clicked through |
| 06 | Refusal logged with code; grant logged with before/after; Health page shows a spike; last admin cannot strand themselves; log failure does not block | 🟡 By construction — every refusal goes through the existing `ops/log_event`, metadata is `{module, granted}` only, and `E-USR-020` makes stranding unreachable (`UT-USR-2-27`, `-28`). Unverified live |

### Live checks over real HTTP, test account 6

| # | Check | Result |
|---|---|---|
| L1 | `usr/module_keys` with a real key / a junk key | ✅ `valid: true` / `valid: false` |
| L2 | `usr/assert_module_access`, user 9, `planning`, **no grant row** | ✅ `ERROR_CODE_ACCESS_DENIED` — absence means not granted, proven rather than assumed |
| L3 | Backfill on account 6 | ✅ `users: 1, scanned: 3, written: 3, already_there: 0` |
| L4 | **Row count in the table afterwards** | ✅ Exactly 3 rows, all `granted: true`. The gate is the count, not the function's own report (the OBS-1 heartbeat lesson) |
| L5 | The identical L2 call, after the backfill | ✅ `{user_id: 9, account_id: 6, module: "planning", granted: true}`. The before/after pair is the real proof |
| L6 | Backfill run a second time | ✅ `written: 0, already_there: 3` — idempotent |
| L7 | `GET user_module_access` as the admin | ✅ 200, three rows, account-scoped |
| L8 | Grant `planning` to a second person (user 16) | ✅ 200 |
| L9 | Admin changes **their own** access | ✅ 403 `E-USR-020` |
| L10 | Unknown module key | ✅ 400 `E-USR-007` |
| L11 | **`module` omitted from the body entirely** | ✅ 400 `E-USR-007` — not a raw "Missing param". The USR-1 lesson about `required` inputs was applied and holds |
| L12 | Grant to somebody in another account (user 2) | ✅ 404 `E-USR-002`, which does not confirm they exist |
| L13 | Revoke | ✅ 200, and the row still exists with `granted: false` |
| L14 | **The row after a grant → revoke cycle** | ✅ `granted_by_user_id: 9`, `granted_at` set, `revoked_by_user_id: 9`, `revoked_at` set — all four survive. This failed the first time; see below |
| L15 | A **member** calling the grant endpoint | ✅ 403 `E-USR-001`, logged |
| L16 | A member reading `GET user_module_access` | ✅ 200 — deliberately not admin-only; everyone needs their own grants to draw their own menu |

### 🔴 Two live bugs, neither visible from the code

**1. `error_type = "input"` is not a value, and nothing says so until runtime.**
The first smoke test of `usr/assert_module_access` returned `Param: error_type
- Input "input" is not one of the allowable values`. The push was clean. The
precondition never refused what it was written to refuse — it threw something
unrelated instead, so `E-USR-007` could never have reached a caller. It was in
two files, written the same hour. The correct value is `inputerror`.

The general lesson, now in `ai-learnings.md`: `error_type` is validated at
runtime, exactly like a middleware's `exception_policy`. **Smoke-test the
refusal, not only the success** — the untested branch is always the one that
matters in a guard.

**2. Revoking erased who granted it.** This table keeps a `granted` bool
instead of deleting the row, and its own header says why: *"revoking by
deleting the row would throw away who granted it and when."* The endpoint then
threw it away anyway — it seeded all four audit columns to `0`/null before
branching, so every revoke patched `granted_by_user_id` back to 0. The
response was correct, the UI was correct, and the row quietly lost half its
history. Caught only by reading the row back out of the table after the call.

The fix seeds each pair from the row that already exists. **And the fix would
have done nothing**, because the lookup feeding those defaults was
`output = ["id", "granted"]` — a column left out of `output` comes back
absent, so the `|get` defaults would have fired and re-introduced the erasure.
Both halves are in `ai-learnings.md`.

### What the local checks caught before the push

| Check | Finding |
|---|---|
| `schemaAudit.test.ts` (FT-GOV-1-01) | 🔴 **Caught a real omission before the push.** The table's first draft indexed `granted_by_user_id` but not `revoked_by_user_id`, breaking GOV-1 standard S3. That test reads `static/tables/` directly, so the standard is enforced on the file rather than remembered |
| `errorCodeRegistry` / catalog review | Reusing `E-USR-004` for the self-change rule would have given one code two meanings. `E-USR-020` minted instead |
| `tsc` on `TeamMember.modules` | Making `modules` a required field proved no fixture builds a `TeamMember` by hand, so the merge is the only way one is created — which is what makes "absence means not granted" hold everywhere |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| 🔴 **`exception_policy` silently defaults to permitting everything** | The feature would appear built, pass a code review, and enforce nothing. Confirmed live, twice, including a nonsense value accepted without error | Set explicitly; re-read the live definition after every push; the story gate is a real HTTP 403 |
| 🔴 **A bad middleware locks everyone out of a whole module at once** | The blast radius is a group, not an endpoint — the mirror image of the sweep's risk | One group at a time; commit before attaching; detach is the rollback; never attach to the Authentication group |
| 🔴 **The backfill misses users** | Anyone missed loses all access the moment story 03 lands | Run on a clone first; verify by counting rows, not by trusting the function's report (the OBS-1 heartbeat lesson) |
| 🔴 **Planner and Execution cannot be told apart** | Story 04's three approaches are all unproven to some degree, and the fallback changes frontend base URLs | Prove per-endpoint attachment on a scratch endpoint before committing to an approach |
| 🟡 **Grants quietly weaken tenancy** | A reviewer could read a module grant as "this user may see this account's data" and relax a guard | Stated as the epic's first rule; no existing guard is removed or edited by any story here |
| 🟡 **One extra query on every request** | The middleware runs on all ~150 endpoints | Measure on the journey-map group before attaching the rest; cache only if measurement demands it |
| 🟡 **`event_log` growth** | Logging every check would make it the largest table in the product | Refusals only |
| 🟡 **Moving endpoints between groups re-shadows static paths** | PLN-9's endpoint 210 has never executed because a sibling dynamic route matched first | Re-check static segments after any move |
| 🟢 **Migration** | Additive table, backfilled | Absence of a row means not granted; the backfill makes today's users whole |

## Decided

| Question | Decision | Date |
|---|---|---|
| Per-endpoint guard sweep, chokepoints, or middleware? | **Middleware.** ~150 hand edits with a silent failure mode, versus one attachment per group that also covers endpoints not yet written | 2026-10-22 |
| Is middleware usable on this Xano plan? | **Yes** — proven live, including `$auth` resolution and a real 403. Worth proving: `redis.*` is rejected outright on this plan | 2026-10-21 |
| Module as an enum column or a text key? | **Text key**, validated against one allow-list function, so a fourth module is config rather than a migration | 2026-10-22 |
| Revoke by deleting the row? | **No** — flip `granted`, keep who and when | 2026-10-22 |
| Default for a new user? | **No modules — confirmed by the founder**, asked directly: *"three are off by default. And then the admin will enable or turn on the check marks for the associated module. Intelligence, plan, or execution."* Existing users are backfilled (story 01) so nobody loses access on the day enforcement lands; the default applies to everyone created after it | 2026-10-22 |
| Who holds the grant — the person, or their agent row? | **The person.** A grant lives on `user_module_access` and a `planner_agent` inherits it through `planner_agent.user_id`. Granting on the agent would let the same person differ between two plans and would be unreadable at sign-in | 2026-10-22 |
| Ship the UI gating first, on its own? | **No.** It looks finished and enforces nothing | 2026-10-22 |
| One module per call, or a list in a transaction? | **One per call.** Each checkbox is one click, so a list could never arrive with more than one item — and supporting one meant a `foreach` inside a `db.transaction`, which is not proven in this workspace. See story 02's amended Method | 2026-10-22 |
| Where do the signed-in user's own grants come from? | **`GET user_module_access`**, not `auth/me`. That endpoint already existed for the Team page, it is account-scoped server-side, and `auth/me` is the highest-volume response in the app and has been trimmed once already | 2026-10-22 |
| Should the UI fail open or closed if the grants fetch errors? | **Open**, because it decides what the MENU shows and authorises nothing — the server refuses regardless. Failing closed turns one failed request into an app with no navigation and tells a user with real access to ask their admin | 2026-10-22 |
| Can an admin change their own module access? | **No, in either direction.** A rule with a direction is a rule somebody finds the other side of, and refusing the grant direction too costs nothing. Refused with `E-USR-020`, its own code | 2026-10-22 |

## Still open

- 🔴 **Story 03 is the whole point of this epic and it is not done.** A
  grant is recorded, displayed and respected by the menu — and refused by
  nothing. `usr/assert_module_access` is live and proven to refuse correctly,
  but no middleware is pushed and nothing is attached, so every endpoint still
  answers everybody. **This is the shape the epic's own second rule warns
  about**, and it must not be left sitting here. What is left, in order:

  | # | What | Why it is in this position |
  |---|---|---|
  | 1 | Push `usr_require_module_intelligence` — attached to nothing | Confirm the declaration shape first |
  | 2 | `getMiddleware` it back and check `exception_policy` really stored `"critical"` | Any value it does not recognise is silently stored as `"silent"`, which permits everything |
  | 3 | Backfill every account that has real users, counting rows each time | Attaching before this locks those users out |
  | 4 | **Commit** | The rollback for step 5 is a revert, and it needs to be one |
  | 5 | 🔴 Attach to the `journey_map` group — **the first irreversible step in Epic-13, and a separate decision** | Blast radius is a whole module |
  | 6 | Prove a real 403 over HTTP, and a granted user unaffected | Never infer it from the code reading correctly |

- 🔴 **`admin/user_delete` (USR-1, endpoint 589) does not delete grant rows.**
  Found while cleaning up a probe user: that endpoint destroys the `user` and
  `user_status` rows in one transaction, and knows nothing about
  `user_module_access` — so removing somebody now leaves up to three orphan
  grant rows behind. Harmless today, wrong in principle, and it contradicts
  `user_status`'s own documented claim that a delete destroys exactly two
  rows. The fix is not a one-liner: `db.del` by `field_name` touches only the
  FIRST match, so three rows means a loop, and a `foreach` inside a
  `db.transaction` is not proven in this workspace. **It is a change to
  shipped, tested USR-1 code, so it needs the founder's go rather than a quiet
  edit.**

- 🟡 **The middleware declaration shape is the one line nobody has proven.**
  The probe established that middleware works here, that `$auth` resolves
  inside it, that it returns a real 403, and the group-level attach syntax —
  but Xano's documentation tool has no middleware section at all, so the
  `middleware "name" { exception_policy = ... }` header in those three files
  follows the `function` shape by analogy. Confirm with `getMiddleware` on the
  first push and correct the files to match live **before** attaching anything.

- **Story 04's approach** — per-endpoint attachment (preferred, unproven),
  splitting the group (correct, more frontend churn), or branching inside one
  middleware (probably impossible). Settled by a scratch test at the start of
  the story, not by discussion. The two middleware files exist and are
  deliberately attached to nothing until it is.
- **Whether the deactivation check lives in these middlewares or its own.** One
  shared pre-check is cheaper; a separate one is clearer. Decide once the
  per-request cost has been measured.
