# EPIC-SEC-1 — API access control

**Status:** stories 01–05 done · 06 partly · 07 to-do — **28 open endpoints → 0**
**Model:** **Opus 5.5** (guards and tenancy — CLAUDE.md model table)
**Depends on:** OBS-1 (event logging), GOV-1 (`guards/assert_owns`, standard S4)
**Blocks:** ORD-1 (insert and resequence)

## Why

The journey-map API group has 94 endpoints. **28 of them require no login at
all.** Confirmed live on 2026-10-18 with a single unauthenticated request:

```
GET https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ/journey_stage   →  HTTP 200
[{"id":1293,"journey_map":176,"key":"s3","label":"Needs Assessment",
  "display_order":3,"stage_goal":"All requirements gathered: date, ...
```

Every stage of every map in the workspace, to anyone with the URL. The same
route family also **writes**: `PUT`/`PATCH`/`DELETE` on `journey_stage/{id}` and
`journey_lens/{id}` are open, so an anonymous caller can rename a column, move
it to a different map, or delete it.

This was found while scoping ORD-1 (insert and resequence a column or row),
because `display_order` and `key` — the two columns ordering governs — are
exactly what those open endpoints can rewrite.

**The second problem, which auth alone does not fix:** five of the endpoints the
app genuinely uses are *global list* endpoints with no map filter
(`GET journey_stage`, `GET journey_lens`, `GET journey_cell`,
`GET journey_lens_planned_work`, `GET journey_stage_owner`). The frontend pulls
the whole table and filters client-side. Adding a login requirement would still
hand account A every row belonging to account B. They need **owner scoping**, not
just authentication.

## Rule

Every endpoint in the journey-map group does one of three things, and which one
is written down:

1. **Requires a login and proves ownership** before it reads or writes a row.
2. **Requires a platform admin**, for maintenance tools that can mass-mutate.
3. **Is deleted**, because nothing calls it.

"Open on purpose" is a fourth option that currently applies to nothing, and any
future use of it must be named in code with a reason.

## Non-goals

- The auth group (`api:RPonubWS`) and the ops group (`api:-2MhtESP`) — this epic
  is the journey-map group only. A sweep of the other groups is a follow-up.
- The planner group, which already has `resolve_actor` + `assert_*` guards on
  every endpoint.
- Orphan structure rows (6 deleted maps left stages and lenses behind) — a real
  finding, recorded in the Epic-8 README, but DEL-1 territory.
- Rate limiting and abuse protection.

## Tenancy decision

Scope by **`account_id`**, using the existing `guards/assert_owns`, not by
`owner_user`.

| Why | Evidence |
|---|---|
| It is already the house standard | GOV-1 standard S4; `guards/assert_owns` takes two account ids |
| Teams exist | `account/my_team_members` — `owner_user` scoping would break sharing |
| No backfill needed | All 24 `journey_map` rows have a non-zero `account_id` (checked live: 0 rows with `account_id = 0`) |

Older journey-map endpoints use `precondition ($journey_map.owner_user == $auth.id)`.
Those are left alone in this epic — tightening them to account scope is a
separate, behaviour-changing decision. New work uses `assert_owns`.

## Error codes

Reuse before minting (GUARD-1-01: a code means exactly one thing).

| Code | Meaning | New? |
|---|---|---|
| `E-GOV-001` | The row belongs to a different account | Existing — reused, not duplicated |
| `E-SEC-001` | Not signed in | New — **documentation only, see below** |
| ~~`E-SEC-002`~~ | ~~Platform admin only~~ | **Not minted — `E-OBS-001` reused instead** |

**`E-SEC-002` was never minted, and that is the right call.** This epic
planned a new code for "platform admin only" before checking whether one
existed. `E-OBS-001` already means exactly that — OBS-1 built it for the Health
page guard — and GUARD-1-01 says a code means exactly one thing. Two codes for
one condition is the thing that rule exists to prevent, so story 05 reuses
`E-OBS-001` and this row is struck rather than quietly dropped.

**`E-SEC-001` never fires, and that is correct.** `auth = "user"` is enforced by
Xano itself: an unauthenticated call is refused with its platform
`401 ERROR_CODE_UNAUTHORIZED` before one line of XanoScript runs, so there is
nowhere to attach our own code. The entry stays in the catalog as the name for
that 401, not as a code any endpoint emits. Measured, not assumed — all 13
endpoints were probed with no token and every one returned exactly that body.

---

## Stories

### US-SEC-1-01 — Every endpoint has a recorded decision ✅ Done

**As a** founder who is the only support person
**I want** one table saying what each open endpoint is for and what happens to it
**So that** nothing is secured by guesswork and nothing is left in "unknown".

```gherkin
Scenario: The classification is complete
  Given the journey-map API group has 94 endpoints
  When the open ones are listed against every path literal the frontends use
  Then each of the 28 open endpoints has exactly one decision: delete, guard, or admin-only
  And no endpoint is marked "unknown"
```

**Method:** the live endpoint list (`listAPIs`, group 4) cross-referenced against
every API path literal in `webapp/protype-2/src`, `webapp/protype-2/e2e` and
`webapp/planningFrontendv2/src`, resolving template literals
(`` `/journey_lens/${id}` ``) rather than matching bare words.

**Checked and ruled out as callers:** no server-side XanoScript calls these over
HTTP (`tools/`, `ai/`, `functions/`, `tasks/`, `agents/` make only external
Anthropic calls); the automation API token (endpoint 197) mints tokens that no
endpoint validates, so no automation depends on them; the frontend attaches its
bearer token on every request (`xano.ts:720`, `:752`), so turning auth on breaks
nothing for a signed-in user.

#### Bucket A — delete (12). Nothing calls them.

| id | Verb | Path | Note |
|---|---|---|---|
| 24 | PUT | `journey_stage/{id}` | Auto-generated CRUD. Can rewrite `key`, `display_order`, `journey_map` |
| 25 | GET | `journey_stage/{id}` | |
| 27 | DELETE | `journey_stage/{id}` | |
| 28 | POST | `journey_stage` | App uses `journey_stage/add/{map_id}` |
| 29 | PATCH | `journey_stage/{id}` | Can rewrite `key`, `display_order`, `journey_map` |
| 30 | PUT | `journey_lens/{id}` | |
| 31 | POST | `journey_lens` | App uses `journey_lens/add/{map_id}` |
| 34 | GET | `journey_lens/{id}` | |
| 35 | DELETE | `journey_lens/{id}` | |
| 37 | DELETE | `journey_cell/{id}` | |
| 59 | GET | `journey_map/{id}/turn-logs` | App uses `tool-logs` (endpoint 128) |
| 60 | GET | `test` | Scaffolding |

#### Bucket B — login + ownership (13). The app uses these.

| id | Verb | Path | Fix |
|---|---|---|---|
| 26 | GET | `journey_stage` | auth + **scope to caller's account** |
| 32 | GET | `journey_lens` | auth + **scope** |
| 41 | GET | `journey_cell` | auth + **scope** |
| 518 | GET | `journey_lens_planned_work` | auth + **scope** |
| 519 | GET | `journey_stage_owner` | auth + **scope** |
| 19 | POST | `journey_map` | auth; set `owner_user`/`account_id` from `$auth`, never from the body |
| 33 | PATCH | `journey_lens/{id}` | auth + `assert_owns` (used for cost rate, `xano.ts:1162`) |
| 36 | GET | `journey_cell/{id}` | auth + `assert_owns` |
| 63 | PATCH | `journey_lens/actor_fields/{id}` | auth + `assert_owns` |
| 54 | GET | `journey_map/{id}/conversation/{cid}` | auth + `assert_owns` |
| 56 | PATCH | `journey_map/{id}/conversation/{cid}` | auth + `assert_owns` |
| 57 | DELETE | `journey_map/{id}/conversation/{cid}` | auth + `assert_owns` |
| 58 | DELETE | `journey_map/{id}/conversation/{cid}/message/{mid}` | auth + `assert_owns` |

#### Bucket C — platform admin only (3). Maintenance tools.

| id | Verb | Path | Why admin |
|---|---|---|---|
| 61 | POST | `journey_lens/backfill_descriptions` | One-off migration, writes across maps |
| 427 | POST | `journey_cell/dedupe_scan` | Reads across maps |
| 428 | POST | `journey_cell/dedupe_apply` | **Deletes** cells across maps |

---

### US-SEC-1-02 — Nothing is deleted before its traffic is checked ✅ Done (with a caveat that matters)

**As a** founder
**I want** live request history checked for every endpoint before it is deleted
**So that** a caller outside this repo is found before the endpoint disappears.

```gherkin
Scenario: An endpoint with recent traffic is not deleted
  Given an endpoint in bucket A
  When its live request history is checked
  And it shows requests that did not come from the test suite
  Then it moves from bucket A to bucket B and is guarded instead
```

**Result:** the whole retained history for API group 4 is **540 requests over
exactly 24 hours** (2026-10-17 21:00 → 2026-10-18 21:04). **Zero** of them hit
any of the 12 bucket A endpoints or the 3 bucket C endpoints.

**The caveat, stated plainly: 24 hours cannot prove an endpoint is unused.**
Only 29 of the 94 endpoints saw any traffic in that window, so 65 endpoints look
"unused" by this measure alone — including ones the app certainly needs. Xano's
request history on this instance does not retain enough to answer the question.

So the delete decision rests on the **code evidence** (story 01: no path literal
in either frontend, no server-side HTTP caller, no automation token path), with
the 24-hour traffic check as corroboration only, and git as the way back. That
is a judgement call, and it is the founder's to confirm — recorded here rather
than buried.

### US-SEC-1-03 — The dead endpoints are gone ✅ Done (2026-10-18)

```gherkin
Scenario: A deleted endpoint stops answering
  Given endpoint 29 (PATCH journey_stage/{id}) has been deleted
  When anyone calls it with or without a token
  Then the API returns 404
  And no journey_stage row can be reached through it

Scenario: The app still works
  Given the dead endpoints are deleted
  When the matrix, the actor wizard and the chat are exercised
  Then every existing Playwright spec still passes
```

**Way back:** every endpoint's XanoScript already exists in
`apis/journey_map/*.xs` and in git history, so each delete is restorable by
re-pushing one file. **Verified before deleting:** all 12 files present,
non-empty (16–63 lines) and tracked in git.

**Founder approved the delete on 2026-10-18** (CLAUDE.md ask-first list).

**Result:** 12 endpoints deleted. The group went from **94 endpoints to 82**,
and from **28 open to 16 open**. A fresh `listAPIs` confirms none of the 12
remain.

**Proved from outside, over real HTTP, with no token** — the four deleted `GET`
routes were probed directly, because `auth: true` in a listing is not proof
(US-SEC-1-06's principle, applied early):

| Probe | Before | After |
|---|---|---|
| `GET /test` | 200 | **404** |
| `GET /journey_stage/1293` | 200 | **404** |
| `GET /journey_lens/1` | 200 | **404** |
| `GET /journey_map/176/turn-logs` | 200 | **404** |
| `GET /journey_stage` (control, kept) | 200 | 200 — still open, story 04 |

The write routes (`PUT`/`PATCH`/`DELETE`) were **not** probed on purpose: if a
delete had silently failed, the probe would itself have destroyed a column or a
row. Their absence from `listAPIs` is the evidence instead.

### US-SEC-1-04 — Login and ownership on the endpoints the app uses ✅ Done (2026-10-18)

```gherkin
Scenario: No token
  Given endpoint 33 (PATCH journey_lens/{id}) is guarded
  When it is called with no Authorization header
  Then it returns 401 and nothing is written

Scenario: Another account's row
  Given user A is signed in
  And lens 42 belongs to account B
  When user A calls PATCH journey_lens/42
  Then it returns accessdenied with E-GOV-001
  And a rejected event is logged
  And the lens is unchanged

Scenario: The owner
  Given user A is signed in and lens 7 belongs to account A
  When user A calls PATCH journey_lens/7
  Then it succeeds and a success event is logged

Scenario: A global list only returns the caller's own rows
  Given account A owns 3 maps and account B owns 21
  When user A calls GET journey_stage
  Then only stages belonging to account A's maps come back
  And orphan rows whose map no longer exists come back for nobody
```

The five global list endpoints get a shared scoping helper so "which rows may
this caller see" is written once, not five times (CLAUDE.md house rule: a shared
rule lives in its own function).

#### What was built

Four new functions, each owning one rule, and all four smoke-tested with
`runWorkspaceFunction` against live data before any endpoint was touched:

| Function | Rule it owns | Used by |
|---|---|---|
| `journey/visible_map_ids` | Which maps may this caller see — this account's, minus the soft-deleted | the 3 map-keyed lists, and the two below |
| `journey/visible_stage_ids` | Which stage rows — the extra hop a side table needs | `GET journey_stage_owner` |
| `journey/visible_lens_ids` | Which lens rows — same hop | `GET journey_lens_planned_work` |
| `journey/assert_map_owner` | Does this caller own the map this row belongs to | the 8 row-touching endpoints |

`journey/assert_map_owner` **delegates to `guards/assert_owns`** rather than
re-implementing it, so the refusal, `E-GOV-001`, and the logged `rejected` event
stay where GOV-1 put them. This epic is that guard's first caller: it was built
by GOV-1 and had no callers until now.

**The lists always carry a `-1` sentinel.** No row can reference map -1, so a
caller who owns nothing matches nothing — without a `conditional`, whose writes
are not reliably visible outside the branch (CLAUDE.md). It also means an
**orphan row, one whose map was deleted, belongs to no account and comes back
for nobody**, which is what the last scenario above asks for. An empty array in
a `where ... in` clause is untested on this instance, so it is never produced.

**Caller identity reuses `planner/resolve_actor`** (user → account + role)
instead of a fourth copy of the same `db.get user` + precondition block. The
`planner/` prefix is now misleading; renaming it would touch 19 planner
endpoints, so it is recorded in Still open rather than done here.

#### Two more things found by securing these endpoints

1. **A lens could be moved into another account's map.** Endpoint 33 is a
   generic CRUD patch whose data block is built from whatever keys the body
   sent — including `journey_map`. Authenticating the caller and checking only
   the lens's *current* map would still have let them push their own lens into a
   stranger's matrix, through an endpoint that had just proved they owned the
   row. It now checks **both** maps: where the lens is, and where it is going.
2. **Four soft-deleted maps were still serving their contents.** `GET
   /journey_map` has excluded soft-deleted maps since DEL-1 (endpoint 18,
   US-DEL-1-07), but the structure lists knew nothing about the marker: the
   founder's app was still being handed the stages, lenses and cells of maps
   179, 194, 196 and 204, hidden from the map list and arriving in every other
   list. `journey/visible_map_ids` now reads the same
   `journey/deleted_map_ids` lookup, so a map cannot be hidden in one place and
   live in another. **Measured: the founder's scope went from 16 maps / 116
   stages / 110 lenses to 12 / 84 / 83, and map 178 still returns all 56 of its
   cells.**

   **I got this wrong first, in this file.** The earlier note here said
   `deleted_map_ids` had no callers and that the map list still showed deleted
   maps. That came from grepping the local `.xs` files, where endpoint 18 is
   stale; the live endpoint has called it since 2026-10-18. CLAUDE.md's standing
   rule — fetch the live source and diff — was applied to the endpoints being
   changed and not to the function being reasoned about.
3. **`!(... in ...)` in a where clause fails at RUNTIME, not at push.** The
   first version of the exclusion used it. It pushed clean, then broke all three
   map-keyed list endpoints with no usable error. Reverted within the minute,
   service confirmed restored, and the working form (`not in`) proved on a
   scratch function before going anywhere near the live function. Added to
   CLAUDE.md's constraint list so it is not re-discovered.
4. **`POST /journey_map` returned 500 on every call the app could make** —
   pre-existing, unrelated to auth, and found only because story 04 exercised
   the success path. It wrote `updated_at` and `last_interaction_at` from
   `$input`, and an omitted optional `date` input *does not exist at all*:
   referencing it is a runtime `"Unable to locate input: updated_at"`, not a
   null (CLAUDE.md). The frontend's `CreateDraftJourneyMapInput` sends neither
   field. Nobody noticed because `journey_map/create_draft` normally answers
   first and the fallback swallows the error. Both are now `"now"`, matching
   endpoint 42. **Fixed, and called out rather than folded in silently.**

### US-SEC-1-05 — Maintenance tools are admin only ✅ Done (2026-10-19)

```gherkin
Scenario: A signed-in non-admin is refused
  Given user A is signed in and is not a platform admin
  When user A calls POST journey_cell/dedupe_apply
  Then it returns accessdenied with E-OBS-001
  And a rejected event is logged
  And no cell is deleted
```

#### What was built

**The guard was EXTENDED, not copied.** `ops/require_platform_admin` already
existed (OBS-1, six callers in the ops group) and already checked exactly the
right thing. Writing a second `is_platform_admin` check for SEC-1 would have
been the duplication CLAUDE.md warns about, so that one function grew three
optional things instead — every default preserving its previous behaviour:

| Added | Why |
|---|---|
| `what` | The refusal message said "You don't have access to this **page**". Telling the founder they lack access to a *page* when they called an API is a confusing error. The three tools pass "maintenance tool"; the Health page's six callers get "page", unchanged. |
| `feature` / `step` / `account_id` / `correlation_id` | **The admin refusal was silent.** The one guard protecting cross-account deletes left no trace when it fired. It now logs a `rejected` event through `ops/log_event` before throwing — the same shape `guards/assert_owns` uses — so a denial shows on the Health page like a failure does (OBS-1). |
| A missing user folded into the not-admin path | Two preconditions became one boolean, so "no such user" and "not an admin" log identically instead of one of them logging nothing. |

**What each endpoint was actually exposed to**, which is worse than "admin
only" suggests:

| id | Endpoint | What an anonymous caller could do |
|---|---|---|
| 61 | `journey_lens/backfill_descriptions` | Rewrite lens descriptions in **every map in the workspace** — its query is `WHERE description IS NULL` with no map or owner filter. Idempotent, which made it less dangerous, not safe. |
| 427 | `journey_cell/dedupe_scan` | Read **every cell in every account** — with no `journey_map_id` it loads the whole table and returns map/stage/lens ids with content flags. A free index of every customer's matrix. |
| 428 | `journey_cell/dedupe_apply` | **Mass-delete cells across every account.** `dry_run` defaults true and `confirm` must be true — a fat-finger guard, not a security boundary. Anyone could pass both. |

**Why admin and not ownership:** all three act across accounts by design, so
there is no single account that owns the action. Account-scoped work belongs in
an account-scoped endpoint.

**Deliberately not tested:** `dedupe_apply` was never called with
`dry_run=false&confirm=true`. Auth is decided before the body runs, so the 401
and the 403 are complete proof on their own, and the only thing the riskier call
could have added was a real mass delete if the push had silently failed. Same
judgement as story 03's decision not to probe the write routes.

### US-SEC-1-06 — The two-user proof ⏸ Partly done — 13 of 82 swept, and no longer blocked

**As a** founder
**I want** every endpoint proved from the outside, over real HTTP, by two users
**So that** the fix is verified at the layer an attacker uses, not the layer that changed.

```gherkin
Scenario: The whole group is swept
  Given two test users in two different accounts
  When every endpoint in the journey-map group is called with no token,
       then with user B's token against user A's data,
       then with user A's own token
  Then the results are 401, then denied, then success
  And every endpoint in the group appears in the result table
```

This is Epic-7's diagnosis applied: *verify at the layer the user touches*. A
`getAPI` showing `auth: true` is not proof — the unauthenticated `curl` is.
Tokens come from `generate_magic_link` → `reset/magic-link-login` (CLAUDE.md;
`security.create_auth_token` tokens are rejected by the live API).

**CORRECTION TO AN EARLIER NOTE IN THIS FILE: the test accounts already
existed.** The story-03 write-up said there was no test user and that the only
real account was the founder's, and recorded "create test accounts" as a
decision the founder had to make. That was wrong. It was concluded from one
missing email (`aipming51@gmail.com`, which the Playwright specs reference and
which genuinely does not exist) instead of from reading the table. The `user`
table holds **nine rows, and five of them are test users in five different
accounts**, each left behind by an earlier epic's own tenancy testing:

| user | account | left by |
|---|---|---|
| 2 — the founder | 2 | — |
| 6 — "QA Test" | 3 | AUTH-1 |
| 7 — "Tenancy Check" | 4 | GOV-1 |
| 8 — "Chain Check" | 5 | GOV-1 |
| 9 — "Orphan Check" | 6 | DEL-1 |
| 10 — "PLN-9 Test" | 7 | PLN-9 |

(Users 3–5 are internal map-builder logins with `account_id` 0 and own nothing.)

So the two-user proof needed no new accounts and never needed to touch the
founder's login. **Story 04 was verified with two of them** — user 9 (account
6, which owns map 202 and the four `journey_lens_planned_work` rows) and user 7
(account 4) — magic-linked to real bearer tokens and swept over real HTTP.
Those results are in Test Results below and cover the 13 endpoints story 04
touched.

**What is left for this story:** the other 69 endpoints in the group. Story 04's
sweep proves the 13 it changed; it says nothing about the rest, several of which
use the older `precondition ($journey_map.owner_user == $auth.id)` shape that
this epic deliberately left alone.

### US-SEC-1-07 — It cannot come back ⏸ To-do

```gherkin
Scenario: A new open endpoint fails the build
  Given a developer adds an endpoint to the journey-map group with no auth
  When the build guard runs
  Then the build fails
  And the message names the endpoint and says it can read or write another account's data

Scenario: A deliberate exception passes
  Given an endpoint is listed in the guard's exception list with a written reason
  When the build guard runs
  Then the build passes
```

Same shape as GUARD-1's guards: fails the build, says what breaks, exceptions
named in code with a reason.

---

## MVP scope

**In:** stories 01–07, journey-map group only.

**Deferred:**
- Sweeping the auth and ops groups (28 open endpoints were found in one group of
  three; the others are unmeasured).
- Tightening the older `owner_user`-scoped endpoints to account scope.
- Rate limiting.
- Orphan structure-row cleanup.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | `guards/assert_owns` on every row-touching endpoint; account scope on every list |
| Validation | Ownership is checked server-side on every call; the UI is not trusted |
| Error codes | `E-SEC-001`, `E-SEC-002` added to the catalog; `E-GOV-001` reused for ownership |
| Events | Every refusal logs `rejected` through `ops/log_event`, so denials show on the Health page like failures do |
| Delete behaviour | 12 endpoints deleted, each restorable from its `.xs` file in git; founder approves before any delete |
| Rollback | Auth flips are per-endpoint and reversible (`updateAPISecurity`); deletes are restorable by re-push |
| No silent failure | A refused call is logged, not dropped |

## Test Results

| Story | Tests | Result |
|---|---|---|
| 01 | Live endpoint list vs. every frontend path literal; server-side and automation callers ruled out | ✅ 28 of 94 open, all 28 classified, 0 unknown |
| 02 | Request history for all 15 delete/admin candidates | ✅ 0 hits in 540 requests / 24h — but 24h is too short to be proof; see the story |
| 03 | 404 after delete (real HTTP, no token) | ✅ 4/4 deleted GET routes return 404; all 12 gone from `listAPIs` (94→82 endpoints, 28→16 open) |
| 03 | Existing unit suite (`npm test`, `webapp/protype-2`) | ✅ 399/399 pass, 0 fail, 0 skipped |
| 03 | Typecheck (`npm run lint`) | ✅ clean |
| 03 | Existing Playwright specs | 🟡 **Null result** — 26 failed / 9 skipped / 0 passed, all on the sign-in page because no `E2E_AUTH_TOKEN` is set. Matches the documented pre-existing count exactly. Not a pass; not evidence of breakage either. See note. |
| 04 | All 13 endpoints probed with **no token**, real HTTP | ✅ **13/13 return 401** `ERROR_CODE_UNAUTHORIZED`. Write routes probed with ids that cannot exist, so a failed push could not have written anything |
| 04 | Group-wide open count after story 04 | ✅ **16 open → 3 open**, and the 3 left are exactly bucket C (story 05's targets) |
| 04 | The four shared functions, `runWorkspaceFunction` on live data | ✅ owner → ok · wrong account → `accessdenied` · missing map → `notfound` · account 0 and an unknown account → `[-1]` only |
| 04 | The refusal is logged, not dropped (OBS-1) | ✅ `event_log` row 5317: `outcome: rejected`, `severity: warn`, `error_code: E-GOV-001`, entity `journey_map` 178 |
| 04 | **Two users, two accounts, five global lists**, real tokens over real HTTP | ✅ see the scoping table below — B receives **0 rows of A's data in all five**, A receives all of its own |
| 04 | **Two users, two accounts, eight row endpoints** | ✅ B → **403 `E-GOV-001`** on all eight · A → 200 (or 404 for a conversation that does not exist, which proves the guard runs first) |
| 04 | A rejected write changes nothing | ✅ after two `HIJACKED` attempts by B, lens 1212 still reads `label: "Clerk"`, `persona_description: ""` |
| 04 | Ownership cannot be forged on create | ✅ `POST /journey_map` as user 9 with `owner_user: 2, account_id: 2` in the body → map 209 created as **owner 9, account 6**. The body was ignored |
| 04 | Existing unit suite (`npm test`, `webapp/protype-2`) | ✅ 399/399 pass, 0 fail, 0 skipped |
| 04 | Typecheck (`npm run lint`) | ✅ clean |
| 04 | Soft-deleted maps excluded from every structure list | ✅ founder's scope 16→12 maps, 116→84 stages, 110→83 lenses, 34→18 owner rows; maps 179/194/196/204 gone; map 178 still returns 56/56 cells |
| 04 | Service restored after the `!(... in ...)` runtime failure | ✅ reverted immediately, A's stage list back to 21 rows, then re-swept clean on the fixed version |
| 05 | All three tools probed with **no token** | ✅ 3/3 return 401 |
| 05 | All three tools as a **signed-in non-admin** | ✅ 3/3 return **403** `"You don't have access to this maintenance tool. (E-OBS-001)"` |
| 05 | The admin refusal is logged (it used to be silent) | ✅ `event_log` 5337: `outcome: rejected`, `error_code: E-OBS-001`, `feature: SEC-1` |
| 05 | The six existing ops/* callers are unaffected by the extension | ✅ `/ops/health`, `/issues`, `/timeline`, `/bundle` all still 403 with the original `"...this page. (E-OBS-001)"` wording — not 500 |
| 05 | **Group-wide open count** | ✅ **28 → 0.** Every one of the 82 endpoints in the journey-map group now requires a login |
| 06 | Two-user sweep over the whole group | ⏸ not run |
| 07 | Build guard fails on a planted open endpoint | ⏸ not run |

**Playwright note (story 03) — a null result, with the reason proved.**
The full suite ran to completion: **26 failed, 9 skipped, 0 passed.** The cause
is printed by the suite's own global setup on its first line of output:

```
[e2e] No E2E_AUTH_TOKEN set — every spec will land on the sign-in page.
```

`e2e/global-setup.ts` is written to behave exactly this way — "WITHOUT A TOKEN,
NOTHING PRETENDS TO PASS... the suite stays honestly red rather than silently
green." Every failure is a locator timeout on a page that is the login screen.

**It matches the documented pre-existing state exactly.** That same file records:
"26 of the 35 Playwright specs had been failing for some time, every one of them
on the sign-in page." This run produced **26** failures. Same number, same cause,
same screen.

So this run says nothing about the deletes either way — it is a null result, not
a pass. Supporting evidence that the deletes are not implicated:

- **No e2e spec calls any of the 12 deleted routes** — grepped the whole `e2e/`
  directory for each one.
- No failure artifact mentions a 404 or a deleted path.
- Every failure is a login-screen timeout, not an API error.

**What would make it a real verdict:** an `E2E_AUTH_TOKEN`, which needs a magic
link minted for a test user. The only email in the specs
(`aipming51@gmail.com`) does not exist in the `user` table, so there is no test
user to mint for — the one real account is the founder's own. **Not done, and
deliberately not done:** writing a login token onto the founder's live account
was not asked for. Story 06 needs two users in two different accounts anyway,
so creating those test accounts is a prerequisite the founder should decide on
(see Still open).

**What the scoping actually withholds now (story 04).** Measured twice: once
through the composed stack with the founder's account, once over real HTTP with
two test users' bearer tokens. "Before" is what *every caller, signed in or
not*, used to receive.

| List endpoint | Before (everyone) | Account 2 (founder) | Account 6 (user 9) | Account 4 (user 7) |
|---|---|---|---|---|
| `GET journey_stage` | 201 | 116 | 21 | **0** |
| `GET journey_lens` | 198 | 110 | 7 | **0** |
| `GET journey_stage_owner` | 43 | 34 | 5 | **0** |
| `GET journey_lens_planned_work` | 4 | **0** | 4 | **0** |
| `GET journey_cell` (map 202) | 9 | **0** | 9 | **0** |
| `GET journey_cell` (map 178, the founder's real map) | 56 | 56 | **0** | **0** |

The founder's own numbers tightened again once soft-deleted maps were excluded:
**16 maps → 12, 116 stages → 84, 110 lenses → 83, 34 stage-owner rows → 18.**
Map 178 (`leads-to-sales-baseline`) still returns all 56 of its cells, which is
the check that matters — the real working map is untouched.

The two zeroes in the founder's column are the proof, not a bug: all four
`journey_lens_planned_work` rows and map 202 belong to **account 6**, a test
account from DEL-1. The founder's own app had been served those rows since
AUTH-1 built the endpoint. Account 4 owns nothing in this group, and now sees
nothing — where before it would have been handed all 201 stages.

**Evidence for 01:** `GET /journey_stage` with no token returned HTTP 200 and
real data (2026-10-18). `journey_stage` live schema matches
`static/tables/7_journey_stage.xs` field for field. API group id 4, canonical
`ER4MRRWZ`, 94 endpoints.

## Still open

### Needs a decision from the founder

- **Four leftovers from testing, all awaiting permission to delete** (CLAUDE.md:
  ask before any delete). None of them is reachable by the app:
  - `scratch/sec1_shape_probe` (function 179) — story 04's stack verifier.
  - `scratch/sec1_notin_probe` (function 180) — proved `not in` works and
    `!(... in ...)` does not.
  - `scratch/ord1_branch_probe` (function 174) — from the ORD-1 discovery.
  - **Journey map 209**, "SEC-1-04 forged-owner test", created in test account 6
    by the create-path proof. Invisible to the founder (`GET journey_map` is
    scoped to `owner_user`), but it is junk.
  - Lens 1212's `updated_at` moved to 2026-10-19 — the owner-success case
    patched its label to the value it already had. Content unchanged.
- **`is_platform_admin` is `false` on all nine user rows — nobody is a platform
  admin.** Story 05 was built anyway, and deliberately: the three tools were
  open to the internet, and "locked to nobody" is strictly safer than "open to
  everybody" while the question is answered. **But it does mean the founder
  cannot run them either**, and two of the three (`dedupe_scan`, and
  `backfill_descriptions`) are tools they may genuinely want. It also means the
  whole Health page has been unreachable for its only intended reader since
  OBS-1 shipped — which is already why `delete_audit` (endpoint 579) exists as
  an account-scoped substitute.
  **The decision: does user 2 get `is_platform_admin = true`?**
  - **Yes** → one row patched (via a scratch `db.patch` function, since the MCP
    row editor is unusable — CLAUDE.md), and the Health page plus all three
    tools become reachable by the founder alone.
  - **No** → the three tools stay unreachable by design, and that is written
    down here as the intent rather than left looking like an oversight.
  Nothing is blocked on this: the endpoints are safe either way.

### Found while doing story 04, not fixed

- **`listJourneyCells()` has been throwing, not returning `[]`, since RES-4.**
  `GET /journey_cell` declares `journey_map` optional but validates `min:1` with
  a default of 0, so a call with no filter is rejected by Xano with 400 before
  the stack runs — measured, not assumed. The frontend's CRUD-fallback
  `listJourneyCells()` (xano.ts) sends no filter, so the fallback bundle path
  has never worked. Pre-existing and unrelated to auth; SEC-1 is not the place
  to change what that endpoint returns.
- **A map with `account_id` 0 would be visible in `GET /journey_map` but its
  contents would not be fetchable.** Endpoint 18's filter is a union (this
  account's maps PLUS anything this user owns); `journey/visible_map_ids` is
  account-only. Live count of such maps: **zero** — all 24 have a non-zero
  `account_id`, so this changes nothing today. Matching the union means
  threading a user id through five endpoints to no effect, so it is recorded
  instead. The query that detects it if it ever matters:
  `journey_map WHERE account_id = 0`.
- **`planner/resolve_actor` is now misnamed.** It is generic (user → account +
  role) and 13 journey-map endpoints call it. Renaming to a neutral namespace
  means touching 19 planner endpoints, so it was reused rather than renamed or
  duplicated.
- **Orphan structure rows.** Stages and lenses reference 30 distinct map ids but
  only 24 maps exist. They are now invisible to every caller, which is the
  correct security answer, but they are still there. DEL-1 territory.

### Still genuinely open

- Whether the other two API groups (auth, ops) get the same sweep, and when. 28
  open endpoints were found in one group of three; the others are unmeasured.
- Whether the older `owner_user`-scoped endpoints should move to account scope
  (a behaviour change — it affects team sharing).
- The remaining **69 endpoints** in this group are unswept by story 06.
- Playwright still cannot pass without an `E2E_AUTH_TOKEN`. A token can now be
  minted for a real test user in seconds, so this is no longer blocked — but
  26 specs were failing on the sign-in page before this epic and still are, and
  fixing that is not SEC-1 work.
