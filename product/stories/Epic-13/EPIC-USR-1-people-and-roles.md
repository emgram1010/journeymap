# EPIC-USR-1 — People and roles

**Epic:** Epic-13 — Who is in the account, and what they can reach
**Status:** ✅ **Done, 2026-10-22.** Nine stories: 01–06 in the morning, 07–09
the same afternoon when the founder asked for full CRUD and an admin-only
page. All five endpoints live in workspace 1 (585–589) and exercised over
real HTTP against test account 6; 485/485 frontend tests green; `tsc` clean.
Two bugs that only a live call could have found are written up under **Test
Results** — both fixed.
**Model:** Sonnet 5.5 (ordinary build work — tables, endpoints, UI, tests)
**Depends on:** nothing. This is the first story in Epic-13.
**Blocks:** USR-2, which has nothing to grant permissions *to* until this exists.

---

## Why

An account today is a bag of users with a `role` column nobody reads. There is
no screen that lists them, no way to add one, no way to remove one, and no way
to see or change who is an admin. The founder is the only support person; the
first time a second person needs access, the only route is a direct database
edit.

This epic makes the account's people **visible and manageable from the web app**,
and — the part that matters more than it sounds — makes it **impossible for an
account to lock itself out** while doing so.

## What this is not

- **Not** module permissions. Who can reach Intelligent Layer, Planner and
  Execution is USR-2. This epic only answers *who exists* and *who is an admin*.
- **Not** platform admin. `is_platform_admin` spans every account and stays
  exactly where OBS-1 put it: writable only by direct database edit, with no
  endpoint, on purpose.
- **Not** a replacement for `planner/assert_admin`. The two admin-only planner
  areas keep working unchanged; they just finally have a UI that explains why a
  member cannot use them.
- **Not** granular rights. Per-action permissions are a later epic.

## What already exists, verified live 2026-10-21

| Thing | State | What this epic does with it |
|---|---|---|
| `user.role` enum `admin` / `member` | Exists, populated | **Reuses as-is.** No schema change |
| `user.account_id` | Exists | Reuses — the tenancy boundary |
| `GET account/my_team_members` | Exists | **Fixes:** its `output` omits `role` |
| `POST admin/user_role` | Exists, admin-gated, logs an event | **Extends:** adds the lockout rules it is missing |
| `POST user/join_account` | Exists | Checked before writing any new "add a person" path |
| `GET account/details`, `PATCH user/edit_profile` | Exist | Left alone |

**Verify before building:** `getAPI` each of these and diff against the local
`.xs` file. The live workspace drifts from this repo (`CLAUDE.md`), and three of
them predate everything in phase 4.

## 🔴 The constraint that shapes the data model

`user` has text columns with validators (`name filters=trim`,
`email filters=trim|lower`, `password filters=min:8|minAlpha:1|minDigit:1`).

`updateTableSchema` **silently drops validators** on any such table — confirmed
twice on `user`/`event_log`, and again on `journey_stage`/`journey_lens`
(STAGE-1). Re-adding them needs the Xano dashboard by hand.

**Therefore: no new column goes on `user`.** Active/inactive state lives in a
1:1 side table, exactly like `account_feature_flag` (GOV-1) and
`journey_stage_owner` (STAGE-1). This is the house default for any new optional
field on a validator-bearing table, not a one-off judgement call.

And the matching lesson from AUTH-1: **a side table needs its own `GET`
endpoint**, or the frontend never sees it. `GET account/my_team_members` queries
`user` and only `user`; a status living in `user_status` will read as
`undefined` forever, with no error, no matter how correct the write path is.
Story 01 therefore merges the side table in explicitly.

## The data model

### New table — `user_status`

One row per user, created on demand. Absence of a row means **active**.

| Field | Type | Notes |
|---|---|---|
| `id` | int | primary |
| `created_at` | timestamp | `=now`, private |
| `user_id` | int | FK `user`, **unique index** |
| `account_id` | int | FK `account`. Denormalised so a tenancy filter never needs a join |
| `is_active` | bool | `=true` |
| `deactivated_at` | timestamp? | null while active |
| `deactivated_by_user_id` | int? | FK `user`, for the audit trail |

**Indexes:** primary on `id`; `btree|unique` on `user_id`; `btree` on
`account_id`.

**Why a flag and not a delete:** users are referenced by
`journey_architecture.owner_user`, `planner_agent.user_id`,
`agent_profile.user_id`, `activity_log.performer_user_id` and
`event_log.user_id`. Destroying the row behind a live reference raises no
error in this engine — it leaves an id pointing at nothing, and the things
that read it go quietly wrong months later.

**AMENDED 2026-10-22 — there IS a delete now (story 08), and the paragraph
above is why it refuses more often than it succeeds.** The founder asked for
it explicitly after reading that the epic had none. The reasoning was not
discarded; it became the guard: the endpoint counts those four references
first and refuses with `E-USR-013` if it finds any, naming deactivation as
the thing to do instead. What is left is a real and useful delete — the
invitation typed with the wrong address, the test account, the person who
never signed in — and exactly two rows are destroyed, the person's
`user_status` row and their `user` row, inside one transaction.

`event_log` is deliberately **not** counted. It holds `user_id` as a plain
int, and a historical entry naming a person who has since been removed is
what an audit trail is for. Counting it would mean nobody could ever be
deleted, because signing up writes one.

🟡 **Known stale comment:** the live `user_status` table's own
description still ends "Nobody is ever deleted", written before story 08
existed. It is documentation, not schema, and `updateTableMetadata` is not a
tool this project trusts on an existing table (`CLAUDE.md`), so it was left
alone rather than risked. The local `static/tables/133_user_status.xs` says
what is now true. One line to correct by hand in the Xano dashboard when
convenient.

**Reading it safely:** `is_active` is a bool, so `== null` is useless —
`false == null` is `true` in this engine (`CLAUDE.md`, VAR-1). Test
`$row.is_active == true` explicitly, and treat a missing row as active rather
than inferring it from a falsy value.

## Error codes

Added to `webapp/protype-2/src/ops/errorCatalog.json`. One code means exactly
one thing (GUARD-1-01).

| Code | Means | HTTP |
|---|---|---|
| `E-USR-001` | You are not an admin of this account | 403 |
| `E-USR-002` | That person is not in your account | 404 |
| `E-USR-003` | That would leave the account with no admin | 403 |
| `E-USR-004` | You cannot change your own role or deactivate yourself | 403 |
| `E-USR-005` | This account is deactivated | 403 |
| `E-USR-008` | That email is already in use | 400 |
| `E-USR-009` | That isn't a role we recognise | 400 |
| `E-USR-010` | We couldn't find your own user record | 403 |
| `E-USR-011` | A name and an email are both needed | 400 |
| `E-USR-012` | That password is too weak | 400 |
| `E-USR-013` | That person has work, so they can't be removed | 403 |
| `E-USR-014` | That doesn't look like an email address | 400 |
| `E-USR-015` | You can't remove your own account | 403 |

`E-USR-006` and `E-USR-007` are reserved for USR-2 so the two epics never
collide.

**`E-USR-015` is separate from `E-USR-004` on purpose.** Both are "not to
yourself" rules, and the first version of the delete endpoint reused
`E-USR-004` for it. `errorCodeRegistry.test.ts` (GUARD-1-01) failed on the
very next run: *one code means exactly one thing*. A role change or a
deactivation can be undone by any admin; a removal cannot be undone by
anybody, so it is a different refusal with a different remedy. The guard
caught this before it reached the founder, which is the only reason that test
exists.

---

## Stories

### US-USR-1-01 — The Team page shows who is in the account ✅

**As an** admin
**I want** one page listing everyone in my account
**So that** I can see who has access before I change anything.

```gherkin
Scenario: The list shows the people and their roles
  Given I am signed in as an admin
  When I open the Team page
  Then I see every user in my account
  And each row shows their name, email, role and whether they are active

Scenario: A member sees the team but no controls
  Given I am signed in as a member
  When I open the Team page
  Then I see the same list
  And there is no control to add, re-role or deactivate anyone

Scenario: I can tell which row is me
  Then my own row is marked, and its destructive controls are absent

Scenario: Another account's people are not listed
  Given a user exists in a different account
  Then they do not appear, and no count includes them

Scenario: A deactivated person is still listed
  Then they appear, visibly marked inactive, not hidden
```

**Method:**
- Fix `GET account/my_team_members` — add `role` to its `output`. It is omitted
  today, which is why no Team page could exist.
- New `GET user_status` — a small, no-filter list endpoint for the side table,
  account-scoped. Same shape as the `journey_stage_owner` fix from AUTH-1.
- New `webapp/protype-2/src/team/TeamPage.tsx`, route `/team`, inside
  `AppLayout`. Merge the two fetches into one view model in the client.

**Counter-measures:**
- 🔴 **Do not add the status to `my_team_members` by joining.** Keep the side
  table's read separate, so the existing endpoint's response shape changes by
  exactly one added field and nothing else can break.
- Enumerate every caller of `my_team_members` before touching it.
- `db.query` with `return = {type: "list"}` must have **no `paging`** — with it,
  the result is not a plain array and `foreach` fails (`CLAUDE.md`).
- A user with no `user_status` row is **active**. Do not treat the missing row
  as an error or as inactive.

**Done when:** the founder opens `/team`, sees themselves listed as `admin`, and
sees no one from any other account.

---

### US-USR-1-02 — An admin adds a person to the account ✅

**As an** admin
**I want** to add someone to my account
**So that** they can sign in and be given access to modules.

```gherkin
Scenario: Adding a person
  Given I am an admin
  When I add a person with a name, an email and the role "member"
  Then they appear in the team list immediately
  And they can sign in

Scenario: A member cannot add anyone
  Given I am a member
  When I call the add endpoint directly
  Then it is refused with E-USR-001
  And the refusal is logged

Scenario: An email already in use is refused
  Given a user already exists with that email
  Then I am told so with E-USR-008
  And my typing is kept on the form

Scenario: A new person starts with no module access
  Then they can sign in and reach nothing until granted (USR-2)

Scenario: The new person lands in my account, not another
  Then their account_id is mine, regardless of anything in the request
```

**Method:** new `POST admin/user_create` in the Members & Accounts group.
Admin-gated, account taken from `$auth`, **never** from the request body.

**Counter-measures:**
- 🔴 **`account_id` is never an input.** Read it from the caller's own record.
  An account id in a request body is a cross-tenant write waiting to happen.
- The `user` table's unique index on `email` is the real guard; catch its
  failure and return `E-USR-008` rather than letting a raw database error out.
- Password: do **not** invent one and email it. See the open question below.
- An omitted optional text input arrives as `""`, never `null` (`CLAUDE.md`).
  Validate `name` and `email` with explicit `!= ""` checks.

### ✅ DECIDED, 2026-10-22 — option 1: the admin sets the password

The question was how the new person first gets in. Three options were put to
the founder: an admin-set password, the existing magic link, or a real
invitation email. The recommendation was the magic link, on the grounds that
it stores no plaintext password anywhere.

**The founder chose the admin-set password**, in their words: *"That's fine.
Then I'll know the password. It's all test. Go live will enhance and secure
the create user process."*

That is a sound call for where this product is, and it is recorded here with
its consequences rather than quietly implemented:

| Consequence | Status |
|---|---|
| The admin knows the person's password until they change it | **Accepted.** Every current user is a test user |
| No "must change at next sign-in" flag | **Deferred to go-live**, at the founder's own framing. Would need a column, so a `user_status` field rather than a `user` one |
| The password crosses the wire in the request body | **Accepted** — identical to every existing auth endpoint in this product |
| The password is stored hashed, never in plaintext | **Handled.** `user.password` is a `password`-typed column, the same write path `auth/signup` has always used |
| The password never reaches `event_log` | **Handled.** Metadata is the new user's id and role only |
| The response never carries the hash or the reset token | **Handled.** The response is shaped field by field |

**Built as `POST admin/user_create` (endpoint 587), live 2026-10-22.** The
form shows the password in plain text as the admin types it, deliberately:
they have to be able to read it back to the person, and masking a value whose
whole purpose is to be passed on would be theatre.

---

### US-USR-1-03 — An admin changes someone's role ✅

**As an** admin
**I want** to make someone an admin, or step them back to member
**So that** more than one person can manage the account.

```gherkin
Scenario: Promoting a member
  Given a member in my account
  When I change their role to admin
  Then the list shows them as admin
  And the change is logged with the previous role

Scenario: A member cannot change roles
  Then it is refused with E-USR-001

Scenario: Changing someone in another account
  Then it is refused with E-USR-002, which does not confirm they exist

Scenario: An unknown role value is refused
  When the role is neither "admin" nor "member"
  Then it is refused before anything is written
```

**Method:** extend the existing `POST admin/user_role`. Do not write a second
endpoint — it already does the admin check, the same-account check and the
event log correctly.

**Counter-measures:**
- 🔴 **The existing endpoint does not validate `new_role`.** Its input is a free
  `text` written straight into an enum column. Add an explicit allow-list check
  before the write.
- Keep `error_type = "notfound"` for the wrong-account case, matching the
  tenancy guards — a refusal should not confirm that a user id exists.
- Story 05's lockout rules land in this same endpoint; build them together or
  build this one knowing it is incomplete until 05 is done.

**Done when:** the founder can promote a second user to admin and see it in the
list, and `new_role: "superuser"` is refused.

---

### US-USR-1-04 — An admin deactivates and reactivates a person ✅

**As an** admin
**I want** to switch someone's access off without erasing them
**So that** people who leave stop getting in, and their history survives.

```gherkin
Scenario: Deactivating
  Given an active member in my account
  When I deactivate them
  Then the list marks them inactive
  And the action is logged with who did it and when

Scenario: A deactivated person cannot sign in
  When they try to sign in with correct credentials
  Then they are refused with E-USR-005
  And the refusal is logged

Scenario: A deactivated person's live session stops working
  Given they were already signed in
  When they make their next request
  Then it is refused

Scenario: Reactivating
  When I reactivate them
  Then they can sign in again, with the roles and grants they had before

Scenario: Their work is untouched
  Then every task, job and log entry attributed to them still exists
```

**Method:** new `POST admin/user_status` writing `user_status`. Login and
session checks consult it.

**Counter-measures:**
- 🔴 **The session scenario is the one that gets skipped.** Blocking login alone
  leaves anyone already signed in with a working token until it expires. The
  check has to run on requests too — this is the natural first job for USR-2's
  middleware, and USR-1 should implement the login half and leave a **named,
  failing test** for the session half rather than quietly scoping it out.
- Deactivation must **not** cascade-delete anything.
- Grants are preserved across deactivate/reactivate; do not clear them.
- `db.patch` touches only the **first** matching row (`CLAUDE.md`). Patch by
  `id`, or query-then-loop. Never patch by `user_id` and assume one row.

---

### US-USR-1-05 — The account cannot lock itself out ✅

**As the** founder
**I want** the product to refuse changes that would leave nobody in charge
**So that** an ordinary mistake does not cost me a support ticket to myself.

```gherkin
Scenario: The last admin cannot be demoted
  Given I am the only admin in my account
  When I try to change my role to member
  Then it is refused with E-USR-003
  And I am still an admin

Scenario: The last admin cannot be deactivated
  Given I am the only admin
  When I try to deactivate myself
  Then it is refused with E-USR-003

Scenario: You cannot change your own role, even with another admin present
  Given there are two admins
  When I try to change my own role
  Then it is refused with E-USR-004

Scenario: You cannot deactivate yourself
  Then it is refused with E-USR-004

Scenario: A second admin can demote the first
  Given there are two admins
  When the other admin demotes me
  Then it succeeds, because one admin remains

Scenario: An inactive admin does not count
  Given the only other admin is deactivated
  When I try to demote myself
  Then it is refused — a deactivated admin cannot administer anything
```

**Method:** one shared function, `functions/usr/assert_not_last_admin`, called
by both the role endpoint and the status endpoint.

**Counter-measures:**
- 🔴 **One function, two callers.** The LOG-1 lesson: a rule copied into two
  places will eventually disagree with itself and sound equally confident both
  times. The admin count is computed in exactly one place.
- Count with `db.query ... return = {type: "count"}`, which returns a plain int
  and is the right way to count without loading rows (`CLAUDE.md`).
- The count must exclude **inactive** admins — the last scenario exists because
  this is the version of the bug that ships.
- Check **before** the write, in the same transaction as the write, so two
  simultaneous demotions cannot both pass.
- The UI disables these controls too, but the UI is a courtesy — the test that
  matters calls the endpoint directly.

**Done when:** the founder, as the only admin of their account, cannot demote or
deactivate themselves through the UI or by calling the endpoint by hand.

---

### US-USR-1-06 — Every change leaves a trace ✅

**As the** founder and only support person
**I want** every change to a person recorded
**So that** "who gave them that?" has an answer that is not my memory.

```gherkin
Scenario: Successes are logged
  When a person is added, re-roled, deactivated or reactivated
  Then an event records who acted, who was affected, and the before and after

Scenario: Refusals are logged too
  When any of those is refused
  Then a "rejected" event records it, with the error code

Scenario: No secrets in the log
  Then no password, hash or reset token appears in any event metadata

Scenario: The Health page shows a spike of refusals
  Then repeated E-USR-001 refusals are visible there
```

**Method:** extend `event_log` through the existing
`Getting Started Template/create_event_log`. Do not create a second log.

**Counter-measures:**
- 🔴 **`db.patch` on a `json` column MERGES, it does not replace** (`CLAUDE.md`,
  the 2,600-row cleanup incident). If any metadata is ever corrected in place,
  it is a two-step patch: `null` first, then the value.
- Log ids, not records. `auth/me` already had to be fixed for exactly this — it
  was writing whole user records, names and emails included, on every page load.
- A refusal that logs nothing is the failure mode OBS-1 exists to prevent.

---

### US-USR-1-07 — An admin corrects someone's name or email ✅

**As an** admin
**I want** to fix a colleague's name or move them to a new address
**So that** a typo at sign-up is not permanent and a person who changes
email does not lose their account.

```gherkin
Scenario: Correcting a name
  Given I am an admin and Sam is in my account
  When I change Sam's name
  Then the team list shows the new name
  And Sam's role, status and work are untouched

Scenario: Correcting an email
  When I change Sam's email to a free address
  Then Sam signs in with the new address from then on

Scenario: Leaving a field out keeps it
  When I send only a name
  Then the email is unchanged

Scenario: An address someone else holds is refused
  Then it is refused with E-USR-008 and my typing is kept

Scenario: A malformed address is refused
  Then it is refused with E-USR-014

Scenario: Resaving the same address unchanged is allowed
  Then it succeeds — the clash check must not match the person themselves

Scenario: An admin may correct their OWN name and email
  Then it succeeds — unlike role and status, this cannot strand an account

Scenario: A member cannot correct anyone
  Then it is refused with E-USR-001, and the refusal is logged
```

**Method:** new `POST admin/user_update` in the Members & Accounts group.

`PATCH user/edit_profile` already existed and edits the CALLER'S own record
with no user id. It is the right endpoint for "change my own details" and was
**left completely alone**; this is the admin's half, which was missing.

**Counter-measures:**
- An omitted optional text input arrives as `""`, never null (`CLAUDE.md`), so
  `""` is the only available signal for "not supplied". That is why this
  endpoint cannot blank a name or an email, and should not: both are required
  columns and a person with neither cannot sign in.
- The clash check reads the id out with `|get:"id":0` rather than touching
  `.id` on a row that may be null. A **literal** key honours its default; a
  variable key silently throws it away (`CLAUDE.md`).
- **Self-editing is allowed**, and `E-USR-004` deliberately does not apply.
  Fixing your own surname cannot lock anybody out.
- The response is shaped. `db.edit` returns every column, which is how
  `admin/user_role` was handing back the password hash until 2026-10-22.
- The log records WHICH fields changed, not what they changed to. Nobody
  supporting this account needs a second copy of everyone's email address.

**Done when:** an admin can fix a misspelled name and move someone to a new
address from the Team page, and cannot take an address that is already in use.

---

### US-USR-1-08 — An admin removes a person ✅

**As an** admin
**I want** to delete someone who should not be here at all
**So that** a wrong address or an abandoned test account does not sit in my
team list forever.

**This story exists because the founder asked for it**, having read that the
epic deliberately had none. The reasoning behind that refusal is sound and was
not discarded — it became the guard. See the amended note under
**The data model**.

```gherkin
Scenario: Removing someone who has done nothing
  Given a person who owns no architecture, is no planner agent, has no agent
    profile and has performed no step
  When I remove them
  Then their user row and their user_status row are both gone
  And the team list no longer shows them

Scenario: Removing someone who has work is refused
  Given a person who owns an architecture
  Then it is refused with E-USR-013
  And the refusal names deactivation as the thing to do instead
  And nothing at all is deleted

Scenario: I cannot remove myself
  Then it is refused with E-USR-015 — its own code, not E-USR-004

Scenario: The last active admin cannot be removed
  Given I am the only active admin
  When another admin tries to remove me
  Then it is refused with E-USR-003, checked before the self-rule

Scenario: An already switched-off admin can be removed
  Then it succeeds — a deactivated admin was never counted

Scenario: A member cannot remove anyone
  Then it is refused with E-USR-001, and the refusal is logged

Scenario: Half a delete is not reachable
  Then both rows go, or neither does

Scenario: The audit trail survives
  Then event_log still holds every earlier entry naming that user id
  And a "deleted_user" entry is added, with ids and the role but no name or email
```

**Method:** new `POST admin/user_delete` in the Members & Accounts group.
Four `return = {type: "count"}` queries, then a `db.transaction` holding two
`db.del` calls.

**Counter-measures:**
- 🔴 **Four reference counts before anything is destroyed**, against
  `journey_architecture.owner_user`, `planner_agent.user_id`,
  `agent_profile.user_id` and `activity_log.performer_user_id`. A dangling id
  raises no error here; it goes wrong quietly, months later.
- 🔴 **POST on a static path, not `DELETE admin/user/{user_id}`.** A static
  segment beside an existing dynamic sibling in the same group and verb is
  permanently shadowed — the trap that left endpoint 210 dead from the day it
  was created (PLN-9, `CLAUDE.md`).
- Both deletes are by a **unique** key: `user.id` is the primary and
  `user_status.user_id` carries a unique index. `db.del` by `field_name`
  touches only the FIRST match (`CLAUDE.md`), which would be a half-delete on
  any non-unique key.
- Both inside one `db.transaction`, which is confirmed to mix tables and verbs
  in this workspace. No `function.run` inside it: the counts and the log sit
  outside.
- The log is written **after** the transaction, so an entry exists only for a
  delete that actually happened.
- **Ids and the role in the metadata, not the name and the email.** The
  tempting argument — the row is gone, so this is the last record of them — is
  the same shape as the argument behind the four logging bugs fixed on
  2026-10-15. The trail survives through the earlier entries for the same id.
- `E-USR-013` is **not** mirrored on the client. The browser cannot see the
  four things that decide it, so the button is offered and the refusal is
  shown honestly. A greyed-out button the client guessed wrong about would be
  worse.

**Done when:** a test account with no work can be removed from the Team page in
two clicks, and an admin who tries to remove someone with work is told to
switch them off instead.

---

### US-USR-1-09 — Only an admin can reach the page ✅

**As the** founder
**I want** user management to be an admin-only part of the web app
**So that** a member does not see a door they cannot open.

The founder's instruction, 2026-10-22: *"the only difference is that the role
is admins can have access to the user management module in their web
interface."*

This **reverses a decision made earlier the same day**, recorded here rather
than quietly overwritten. The page first shipped visible to everyone, on the
reasoning that it renders no controls for a member, so hiding the menu item
would only make an admin's own team invisible until they learned the URL. The
reasoning was sound; the founder's instruction overrides it.

```gherkin
Scenario: A member does not see the menu item
  Given I am a member
  Then "Manage users" is absent from the sidebar and the mobile menu

Scenario: A member typing the URL is turned away
  When I navigate to /team
  Then I land on the architectures list

Scenario: An admin sees it as before
  Then the item is present and the page works

Scenario: Hiding it is not what protects it
  Given a member who calls all five endpoints directly
  Then each refuses with E-USR-001 and logs the refusal
```

**Method:** an `adminOnly` flag on the nav item, a new `AccountAdminRoute`
guard in `main.tsx`, and `canManageTeam` — the same function the page and the
model already use — as the single test of who counts as an admin.

**Counter-measures:**
- 🔴 **Hiding a menu item is not a permission**, the rule USR-2 is built on.
  The nav flag and the redirect are conveniences; the five endpoints each run
  `usr/assert_team_admin` themselves.
- `AccountAdminRoute` is a **separate guard from `AdminRoute`**, which tests
  `is_platform_admin`. Conflating them would either lock an account's admins
  out of their own team or hand one account's admin the platform tools.
- The page keeps its read-only rendering for a non-admin. A page that renders
  nothing dangerous when its guard is bypassed is one less thing to get wrong.
- `role` has arrived on every page load from `auth/me` since long before this
  epic and was never read. One function reads it, so the nav, the route and
  the page cannot drift into disagreeing about who is an admin.

**Done when:** a member sees three sidebar items and an admin sees four, and a
member who types `/team` ends up somewhere useful instead of nowhere.

---

## MVP scope

**In, and all built: 01, 02, 03, 04, 05, 06, 07, 08, 09.**

Stories 01 and 03–06 were built in the morning of 2026-10-22. Story 02 was
blocked on one founder decision, which arrived the same afternoon along with a
request for full CRUD and an admin-only page — stories 02, 07, 08 and 09.

The founder's words for the wider ask: *"I want to be able to enable CRUD for
the user, update the user info, delete the user, add users, read users, along
with their roles."* Mapped to stories: read is 01, roles are 03, add is 02,
update is 07, delete is 08, and the admin-only page is 09. Deactivation (04)
and the lockout guard (05) were already there and are what make delete safe to
offer at all.

**“CRUD on roles” means assigning them, not inventing them.** `role` is an
enum of exactly `admin` and `member`; a third role is a schema change, not a
new string, and the founder's own framing was *"we'll get a little bit more
granular in the future"* — which arrives as module grants in USR-2, not as
more role names. Recorded in **Decided** below.

**Deferred:** transferring ownership between accounts; a user belonging to more
than one account; self-service signup into an existing account; invitation
emails; a "must change password at next sign-in" flag (go-live hardening, at
the founder's own framing).

**Next:** USR-2 — associating each person with the Intelligent Layer, Planner
and Execution. That is the other half of what the founder asked for on
2026-10-22, it is marked Opus work, and it depends on story 05 being green,
which it now is.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | Every endpoint resolves the caller's `account_id` from `$auth` and refuses anything outside it with `notfound`, never `accessdenied` — the same shape as `guards/assert_same_account` |
| Validation | `new_role` checked against an allow-list before any write; name and email checked with explicit `!= ""` (an omitted optional text arrives as `""`); email shape and password strength checked in the endpoint so the admin gets a sentence rather than a raw database error; friendly messages, and the user's typing is kept on a rejected save |
| Error codes | `E-USR-001`–`005` and `008`–`015` in `src/ops/errorCatalog.json`; `006`/`007` reserved for USR-2. `errorCodeRegistry.test.ts` compares every code's live message against the catalog and caught `E-USR-015` being born as a second meaning for `E-USR-004` |
| Events | Success and refusal both logged through the existing `create_event_log`. No second log, no silent refusal |
| Table constraints | One new table, `user_status`. **No change to `user`** — `updateTableSchema` would silently drop its validators |
| Delete behaviour | **Deactivation is the default and the only reversible option.** A hard delete exists (story 08) and refuses anyone referenced by an architecture, a planner agent, an agent profile or a performed step (`E-USR-013`). When it does proceed it destroys exactly two rows — `user` and `user_status` — in one transaction, and `event_log` is untouched |
| Rollback | The new table is additive and ignored by every existing endpoint. Reverting means deleting `user_status` and the Team route. The one non-additive change is adding `role` to `my_team_members`'s output — one line, reversible |
| No silent failure | Every refusal returns a catalogued code and writes a `rejected` event |
| Testing | Live exercises run on a **test account**, never the founder's own account and never map 178 |

## Test Results

**`npm test`: 485/485 pass. `npm run lint` (`tsc --noEmit`): clean.**
50 of those are `src/team/teamModel.test.ts` (UT-USR-1-01 … UT-USR-1-50),
52 assertions in all.

All nine stories are now live and exercised end to end, except the one path
noted at the bottom of this section.

| Story | Tests | Result |
|---|---|---|
| 01 | Team list shows role and status; member sees no controls; cross-account absent; inactive still listed; side table actually reaches the UI | ✅ UT-USR-1-01–08 |
| 02 | Admin adds a person; member refused; duplicate email refused; weak password refused; malformed email refused; unknown role refused; blank name or email refused; a clash in another account is left to the server | ✅ UT-USR-1-26–35 |
| 03 | Promote; member refused; cross-account refused as notfound; unknown role refused | ✅ UT-USR-1-11–19 |
| 04 | Deactivate; reactivate restores; no cascade; inactive still listed | ✅ UT-USR-1-20–25 |
| 05 | Last admin cannot self-demote, self-deactivate or be removed; self-change refused with two admins; second admin can demote; inactive admin does not count | ✅ UT-USR-1-17, 17b, 22, 45, 47, 48 |
| 06 | Success and refusal both logged, with the code; no secrets in metadata | ✅ by construction — every endpoint logs through the existing `create_event_log` / `ops/log_event`, and the delete's metadata carries ids and the role only |
| 07 | Correct a name, an email, or both; omitted field keeps its value; another person's address refused; resaving your own allowed; malformed refused; self-edit allowed; member refused | ✅ UT-USR-1-36–41, **and 8/8 live** |
| 08 | Remove a member; member refused; self refused as `E-USR-015`; last active admin refused as lockout; already switched-off admin removable; outsider not found; "has work" deliberately not predicted client-side | ✅ UT-USR-1-42–50, **and 10/10 live** — including the `E-USR-013` refusal with a real architecture owner |
| 09 | Member sees no menu item and is redirected from `/team`; admin unaffected; all five endpoints still refuse a member server-side | ✅ nav filtered by `canManageTeam`, `AccountAdminRoute` added; the server half is `usr/assert_team_admin`, smoke-tested live below |

### Live checks, workspace 1

Run against the real HTTP API as an admin of **test account 6** (user 9),
never the founder's own account. The token came the documented way: run
`Getting Started Template/generate_magic_link`, then POST the plaintext token
to `reset/magic-link-login`.

| Check | Result |
|---|---|
| `usr/assert_team_admin` with an admin (user 2) | ✅ returns `{id: 2, account_id: 2, role: "admin"}` |
| `usr/assert_team_admin` with a member (user 6) | ✅ `ERROR_CODE_ACCESS_DENIED` — a real 403, not the HTTP 200 the old gate gave |
| `user_status` table (133) live, with its unique index on `user_id` | ✅ |
| Endpoints 585 (`user_status`), 586 (`admin/user_status`), 587 (`admin/user_create`) live | ✅ |
| **`POST admin/user_create`** — add a member | ✅ HTTP 200, user 12 in account 6, role `member` |
| └ the response carries no password hash and no `password_reset` | ✅ five fields only: id, name, email, account_id, role |
| └ **the new person can sign in with the password the admin set** | ✅ `auth/login` returned a token for user 12. This is the proof that the `password`-typed column hashed it correctly |
| └ `account_id` came from the admin's record, not the request | ✅ account 6, and no account id was sent |
| └ role is honoured, and case-folded | ✅ `"ADMIN"` created user 13 as `admin` |
| └ a malformed email | ✅ 400 `E-USR-014` |
| └ a weak password | ✅ 400 `E-USR-012` |
| └ an unknown role | ✅ 400 `E-USR-009` |
| └ an email already in use **in another account** | ✅ 400 `E-USR-008`, without confirming whose |
| └ a blank name, and a name omitted entirely | ✅ 400 `E-USR-011` for both — after the fix below |
| └ a password omitted entirely | ✅ 400 `E-USR-012` |
| └ **a member calling it** (user 12, created moments earlier) | ✅ **403** `E-USR-001` — a real refusal, logged |
| └ a member can still read their own team | ✅ 200, both people listed. Reading is not admin-gated on the server; only the page is |

### 🔴 A bug this probing found, in the endpoint as first written

**Declaring an input `required` makes the endpoint's own validation
unreachable.** `name`, `email` and `password` were required, each with a
precondition underneath carrying a friendly sentence and a catalogued code.
None of them could ever fire: Xano validates a required input **itself,
before the stack runs and before auth is checked**, so a blank name returned
`Missing param: name` with no code, nothing the Health page could explain,
and `""` treated as missing rather than blank.

This epic had already claimed `E-USR-011` and `E-USR-012` worked. They did
not, and reading the endpoint would never have shown it — only calling it
with a blank field did.

Fixed by declaring all four inputs optional, which is how an omitted value
arrives as `""` and the preconditions get their turn. Live endpoint 587
updated, local file synced, and the lesson written into
`product/ai-learnings.md` because it generalises to every endpoint in this
product that validates its own inputs.

### Live checks — story 07, `POST admin/user_update` (endpoint 588)

Pushed 2026-10-22 on the founder's go-ahead, then exercised over real HTTP as
an admin of test account 6.

| Check | Result |
|---|---|
| Correct a name only | ✅ 200, name changed, **email untouched** |
| Correct an email only | ✅ 200, email changed, **name untouched** |
| Resave the same address unchanged | ✅ 200 — the clash check does not match the person themselves |
| Take an address another person holds | ✅ 400 `E-USR-008` |
| A malformed address | ✅ 400 `E-USR-014` |
| Send nothing to change | ✅ 400 `E-USR-011` |
| Target the founder's own record from test account 6 | ✅ **404** `E-USR-002` — cross-account tenancy holds |
| An admin correcting their OWN name | ✅ 200 — allowed, as story 07 specifies |

### Live checks — story 08, `POST admin/user_delete` (endpoint 589)

| Check | Result |
|---|---|
| Remove myself | ✅ 403 `E-USR-015` |
| Remove someone in another account | ✅ 404 `E-USR-002` |
| Remove a user id that does not exist | ✅ 404 `E-USR-002` — same code, so a refusal never confirms an id |
| Remove a person **with no status row** | ✅ 200, after the fix below |
| Remove a person **with a status row** (switched off first) | ✅ 200 — both branches exercised |
| The side table afterwards | ✅ **no orphan row** |
| Remove a person who **owns an architecture** | ✅ 403 `E-USR-013`, and **nothing was deleted** — they were still listed, intact |
| └ switching them off instead, which the refusal advises | ✅ 200 — the advice the message gives actually works |
| └ removing the same person once the architecture was gone | ✅ 200 |
| Test account restored afterwards | ✅ one user, no status rows, no leftover fixtures |

### 🔴 A second bug this probing found — the delete never worked at all

**`db.del` on a row that does not exist is not a no-op.** It raises
`ERROR_CODE_NOT_FOUND` with an **empty message** — no code, no sentence,
nothing the Health page can explain.

A `user_status` row exists only for somebody whose status has been touched;
**absence means active**, which is the entire design of that side table. So
for the ordinary case the first `db.del` found nothing, threw a bare 404, and
the transaction correctly rolled the whole delete back. The endpoint returned
`404 {"code":"ERROR_CODE_NOT_FOUND","message":""}` and deleted nobody, ever,
while all six refusal paths around it worked perfectly.

The transaction did its job. The delete simply never happened — and reading
the code would not have shown it: the two `db.del` calls look symmetrical and
nothing documents that a delete needs a match.

Fixed with a `count` before the transaction and a `conditional` around the
status-row delete. Live endpoint 589 updated, local `20_*.xs` synced, lesson
written into `product/ai-learnings.md`.

**Two things confirmed working while fixing it:** a `conditional` nests
inside a `db.transaction`, and its condition may read a `var` computed before
the transaction block.

### 🟡 The one path with unit coverage only

**The last-admin lockout on a delete** (`E-USR-003`). Reaching it live needs
an admin who is switched off but still holding a valid token deleting the
only remaining active admin — which is only possible because of the known
open-session gap that USR-2's middleware closes. Covered by UT-USR-1-47 and
by the shared `usr/assert_not_last_admin`, which the role and status
endpoints exercise live.

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| 🔴 **The account locks itself out** | The founder is the only admin and the only support person. There is no one to call | Story 05, enforced server-side, tested by calling the endpoint directly rather than clicking the UI |
| 🔴 **Deactivation only blocks login** | Anyone already signed in keeps working until their token expires, and the feature looks finished | Named failing test in story 04, closed by USR-2's middleware |
| 🔴 **A new column on `user` drops its validators** | Silent data-quality loss on email and password, repairable only through the dashboard by hand | Side table. Confirmed three times across GOV-1, STAGE-1 and here |
| 🟡 **The side table never reaches the UI** | AUTH-1 lost a day to exactly this: the write path was perfect and the value read `undefined` forever | Story 01 gives the side table its own `GET` and merges it explicitly |
| 🟡 **`my_team_members` has other callers** | Changing its output could break something unseen | Enumerate callers before the edit; the change is additive |
| 🟡 **`admin/user_role` accepts any text as a role** | An unvalidated string goes straight into an enum column today | Story 03 adds the allow-list check |
| 🔴 **A delete orphans history silently** | A destroyed user row behind a live reference raises no error. The id just points at nothing, and variance, the Health page and every performed job go quietly wrong months later | Story 08 counts four reference tables before destroying anything and refuses with `E-USR-013`. `event_log` is excluded on purpose. Both deletes are by a unique key, inside one transaction |
| 🟡 **The admin knows the new person's password** | An admin-set initial password is readable by whoever typed it until the person changes it, and there is no flag forcing them to | Accepted by the founder for a product whose users are all test users; recorded under story 02 with go-live hardening named |
| 🟢 **Migration** | None. Absence of a `user_status` row means active | No backfill needed |

## Decided

| Question | Decision | Date |
|---|---|---|
| Keep the existing `admin` / `member` enum, or design a richer role model? | **Keep it.** Two roles cover what was asked; granularity arrives as module grants (USR-2), not as more role names | 2026-10-22 |
| Delete users or deactivate them? | **Deactivate** — and then, the same day, **both.** The founder asked for a real delete; it exists, and it refuses anyone with work in the system rather than orphaning it (story 08). Deactivation remains the default and the only reversible option | 2026-10-22 |
| How does a new person first sign in? | **The admin sets an initial password.** The founder's call, over the magic-link recommendation: *"That's fine. Then I'll know the password. It's all test. Go live will enhance and secure the create user process."* | 2026-10-22 |
| Can a member see the Team page? | **No.** Reversed within the day on the founder's instruction. The nav item is hidden and the route redirects — and because hiding a menu item is not a permission, all five endpoints still refuse a member themselves | 2026-10-22 |
| Does "CRUD on roles" mean creating new roles? | **No — assigning the two that exist.** A third role is a schema change on an enum column, and the founder's "more granular in the future" is USR-2's module grants, not more role names | 2026-10-22 |
| Should the Add form mask the password? | **No.** Its whole purpose is to be read back to the person it belongs to; masking it would be theatre | 2026-10-22 |
| New column on `user` for active state? | **No — side table.** `updateTableSchema` drops validators on tables with text filters | 2026-10-22 |
| Merge account admin and platform admin? | **No.** A platform admin acts across every account; keeping them separate is what makes the stricter check meaningful | 2026-10-22 |

## Still open

- 🟡 **Deactivation still only blocks a new sign-in.** Anyone holding a
  token issued before they were switched off keeps working until it expires.
  Closing that needs a check on every request — USR-2's middleware.
- 🟡 **A "must change password at next sign-in" flag**, which the founder
  framed as go-live hardening. Would be a column on `user_status`, never on
  `user`.
- 🟡 **The live `user_status` table description** still says "Nobody is ever
  deleted". One line, by hand, in the Xano dashboard.
- 🟢 Endpoints 11 and 17 keep their own inline admin gate, written before
  `usr/assert_team_admin` existed. Identical wording, so nothing disagrees
  today — but it is two more copies of a rule that now lives in one place, and
  folding them in is a small, safe tidy-up with a live retest.
- 🟢 Whether the Team page stays in the sidebar or moves under account
  settings. A placement call; the sidebar is the default and is what shipped.
