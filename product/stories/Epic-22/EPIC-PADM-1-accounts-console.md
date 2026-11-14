# EPIC-PADM-1 — Accounts console: see and manage every customer's Emgram

**Epic folder:** Epic-22 — Accounts
**Status:** 📋 Not started. Written 2026-11-14.
**Model:** **Opus 5.5** for stories 01–03 and 07 (the scope rule and the delete). Sonnet 5.5 for 02,
04–06, 08. Opus review pass after.
**Depends on:** SEC-2 (all stories). Do not start while `user/join_account` is open.
**Risk:** high. This adds a cross-account power to endpoints that are live and in daily use.

---

## 1. Goal

**Pain:** the founder is the only support person and cannot see who has an account, add a customer,
fix a customer's user, or remove a dead test account without opening the database.

**Fix:** an **Accounts** screen only a platform admin can open. It lists every account, opens one to
show its people, and reuses the existing add / edit / role / switch-off / delete / module controls.

**Win:** onboarding a customer and answering "why can't Maria sign in?" take a minute, and every
action leaves a log entry.

---

## 2. Design

```
Accounts                                                        [ + New account ]
┌──────────────────────────┬────────┬────────┬───────┬──────────────┬─────────┐
│ Account                  │ People │ Admins │ Maps  │ Last active  │ State   │
├──────────────────────────┼────────┼────────┼───────┼──────────────┼─────────┤
│ Blooming Party Rentals   │ 4      │ 1      │ 8     │ today        │ Active  │
│ Acme Logistics           │ 2      │ 1      │ 0     │ 12 days ago  │ Active  │
│ ⚠ People with no account │ 3      │ —      │ —     │ —            │ —       │
└──────────────────────────┴────────┴────────┴───────┴──────────────┴─────────┘
  click a row →  that account's people, with the same controls as "Manage users"
```

### The scope rule — the heart of this epic

Every user-management endpoint today works out "which account" from **the caller's own record**.
That is why it is safe: nothing a caller sends can widen what they touch.

This epic adds exactly one way to widen it, in exactly one function:

| Caller | Sends `as_account_id` | Result |
|---|---|---|
| Account admin | nothing (arrives as `0`) | Their own account — **byte-for-byte today's behaviour** |
| Platform admin | nothing | Their own account, as an ordinary admin |
| Platform admin | an account number | **That** account |
| Anyone else | an account number | Refused with `E-OBS-001`, and logged |

New function `usr/resolve_admin_scope` returns `{account_id, acting_as}`. It **wraps**
`usr/assert_team_admin` for the first two rows and `ops/require_platform_admin` for the last two —
it does not copy either.

**Why extend the live endpoints instead of writing new "platform" copies:** the rules that keep an
account from locking itself out (last admin, no self-demotion, no deleting someone with work) live
inside those endpoints. A second copy would be a second opinion about those rules, and the two would
drift. One rule, one place.

### What is new

| Kind | Name | Notes |
|---|---|---|
| Function | `usr/resolve_admin_scope` | The scope rule above |
| Function | `padm/account_summary` | Counts per account: people, active admins, maps, last activity |
| Function | `padm/assert_account_empty` | Used by delete (story 07) |
| Endpoint | `GET platform/accounts` | Platform admin only |
| Endpoint | `POST platform/account_create` | Account + first admin, one transaction |
| Endpoint | `POST platform/account_update` | Rename, description, location |
| Endpoint | `POST platform/account_delete` | Empty accounts only |
| Endpoint | `POST platform/user_assign_account` | For people with no account (F-8) |
| Screen | `/accounts` and `/accounts/:id` | Behind the existing `AdminRoute` |

POST with static paths on purpose — the same reason `admin/user_delete` is not
`DELETE admin/user/{id}`: a dynamic path can shadow a static one in the same group (CLAUDE.md).

### What changes on existing endpoints

One optional input, `int as_account_id?`, and the account now comes from `resolve_admin_scope`:

`GET account/my_team_members` (10) · `GET user_status` (16) · `GET user_module_access` (21) ·
`POST admin/user_role` (11) · `admin/user_status` (17) · `admin/user_create` (18) ·
`admin/user_update` (19) · `admin/user_delete` (20) · `admin/user_module_access` (22)

---

## 3. Stories

### US-PADM-1-01 — One rule decides whose account you are acting in
**Status:** 📋 Not started.

**As the** founder **I want** a single, tested rule for acting inside a customer's account **so
that** the power cannot leak to anyone else.

```gherkin
Scenario: Account admin, nothing sent
  Given I am an admin of account X
  When resolve_admin_scope runs with as_account_id 0
  Then it returns account X, acting_as "account_admin"

Scenario: Member, nothing sent
  Given I am a member of account X
  Then I am refused with E-USR-001, exactly as today

Scenario: Platform admin names an account
  Given I am a platform admin in account A
  When it runs with as_account_id Y
  Then it returns account Y, acting_as "platform_admin"

Scenario: Account admin names another account
  Given I am an admin of account X and not a platform admin
  When it runs with as_account_id Y
  Then I am refused with E-OBS-001 and the attempt is logged with both account numbers

Scenario: Account admin names their own account
  When it runs with as_account_id X
  Then I am refused the same way — only a platform admin may send this input at all

Scenario: The account does not exist
  Given I am a platform admin
  When it runs with as_account_id 999999
  Then I am refused with E-PADM-001
```

**Counter-measures.**
- **Refuse, never ignore.** A non-platform caller who sends `as_account_id` gets a refusal, not a
  quiet fallback to their own account. Quiet fallbacks hide attacks and bugs alike.
- `0` means "not sent" — an omitted int is `0`, never `null`, and no real account is `0`. Write that
  in a comment; do not test `!= null`.
- When `function.run` calls this, **pass every input explicitly**. An input left out silently
  inherits the caller's `$input` of the same name (CLAUDE.md) — here that would hand one endpoint's
  `as_account_id` to another call.
- Unit-test all six rows with `runWorkspaceFunction` before any endpoint uses it.

---

### US-PADM-1-02 — See every account at a glance
**Status:** 📋 Not started.

**As the** founder **I want** a list of all accounts with a few facts each **so that** I know who is
using Emgram and who has gone quiet.

```gherkin
Scenario: The list
  Given I am a platform admin
  When I open Accounts
  Then each account shows its name, people, active admins, maps and last activity

Scenario: People with no account are not hidden
  Given some users have account 0
  Then a row "People with no account" shows how many

Scenario: An account with no active admin is flagged
  Then that row carries a warning

Scenario: Not a platform admin
  When anyone else calls GET platform/accounts
  Then they are refused with E-OBS-001 and it is logged
```

**Counter-measures.**
- Counts with `return = {type: "count"}` or one grouped pass in a `foreach` — never
  `array.group_by` chains (broke live on real data) and never `|get:$key:0` with a variable key
  without pre-seeding (returns `null`, CLAUDE.md).
- No paging object on the query — it stops being a plain array.
- Shaped response: account id, name and numbers. **No emails, no AI context** in the list.
- "Last activity" comes from `event_log`; cap the look-back so the list stays fast as logs grow.

---

### US-PADM-1-03 — The existing people controls work on any account, for the founder only
**Status:** 📋 Not started.

**Description.** The nine endpoints listed in §2 accept `as_account_id`.

**As the** founder **I want** to add, correct, re-role, switch off and remove a customer's users
**so that** I can support them without a database tool.

```gherkin
Scenario: Nothing changes for account admins
  Given a recording of every Team-page request and response taken before this story
  When the same requests are replayed after it
  Then every response is identical

Scenario: The founder lists another account's people
  Given I am a platform admin
  When I call account/my_team_members with as_account_id Y
  Then I get account Y's people, statuses and module grants

Scenario: The founder adds a person to another account
  When I call admin/user_create with as_account_id Y
  Then the new person belongs to account Y, not to mine

Scenario: A status or grant row lands in the right account
  When I switch off a person in account Y
  Then the user_status row's account is Y
  And account Y's own admin sees them as inactive on their Team page

Scenario: The lockout rules still hold
  When I try to remove or demote account Y's last active admin
  Then I am refused with E-USR-003

Scenario: A person in a third account
  When I send as_account_id Y with a user who belongs to account Z
  Then I am refused with E-USR-002

Scenario: A customer tries the new input
  Given I am an admin of account X
  When I call any of the nine with as_account_id Y
  Then I am refused with E-OBS-001 and nothing is read or written
```

**Counter-measures.**
- 🔴 **`user_status.account_id` and `user_module_access.account_id` are written "from the ACTING
  user's own record"** today (table comments say so). With a platform admin acting, that would file
  the row under the **founder's** account and the customer's Team page would never see it. Both
  writes must use the **resolved** account. This is the easiest bug in the epic to ship.
- **Record before, replay after.** The golden replay in the first scenario is the proof that
  customers are unaffected. Take it before the first push, not after.
- One endpoint at a time: push, smoke-test over real HTTP as an account admin and as the founder,
  then the next. Read endpoints (10, 16, 21) first — they cannot damage data.
- Save each endpoint's live source with `getAPI` before pushing. That file is the rollback.
- `E-USR-004` / `E-USR-015` ("not yourself") compare user ids, so they keep working unchanged — but
  add a test that the founder still cannot delete **themselves** through `as_account_id`.
- `deactivated_by_user_id` / `granted_by_user_id` will now sometimes be a person from another
  account. The Team page must show "Emgram support" (or similar), not a blank or a crash, when it
  cannot find that id among the account's own people.

---

### US-PADM-1-04 — Create an account with its first admin
**Status:** 📋 Not started.

**As the** founder **I want** to set up a customer's account myself **so that** I can onboard
someone on a call without sending them to a sign-up form (D-1).

```gherkin
Scenario: Creating
  When I enter an account name, the admin's name, email and a starting password
  Then an account and its admin are created together
  And the admin can sign in and sees all three modules (D-5)

Scenario: Email already used
  Then I am refused with E-USR-008 and my typing is kept

Scenario: Missing name
  Then I am refused with E-PADM-002 and my typing is kept

Scenario: Weak password / bad email
  Then I get the same E-USR-012 / E-USR-014 messages the Team page gives

Scenario: Half-made accounts never exist
  Given the user insert fails
  Then no account row is left behind
```

**Counter-measures.**
- One `db.transaction`: account, user, three grant rows. `function.run` for write-only helpers is
  safe inside it; **logging goes outside**.
- Validation is `admin/user_create`'s — extract the shared checks into a function rather than
  re-typing them, so the two cannot disagree.
- The password is never logged, never returned, never put in an event's metadata.
- The email is unique across **all** accounts (the index is on `user.email` alone). Say so in the
  message: "That email already has an Emgram sign-in."
- Renaming or editing the account uses `POST platform/account_update`; the customer's own
  `/account` page must show the new name on next load — check in the browser.

---

### US-PADM-1-05 — Open one account and manage its people
**Status:** 📋 Not started.

**As the** founder **I want** an account's page to look and behave like "Manage users" **so that** I
do not have to learn a second screen.

```gherkin
Scenario: Opening an account
  When I click an account in the list
  Then I see its people, roles, active state and module ticks
  And a banner says "You are managing <account name> as Emgram support"

Scenario: Every control works
  Then add, edit, change role, switch off / on, delete and module ticks behave as on the Team page

Scenario: A refused save keeps my typing
  When the server refuses a change
  Then the form stays filled in and shows the server's message

Scenario: Going back
  When I return to the list
  Then the counts reflect what I changed
```

**Build notes.** `TeamPage` gains **one optional prop**, `accountId`. Absent = today, for every
existing user. Each call in `xano.ts` gains one optional argument that is only sent when set. The
pure rules in `teamModel.ts` are reused as they are.

**Counter-measures.**
- **A request without the prop must be identical on the wire to today's.** Do not send
  `as_account_id: 0` or `undefined` as a query key — omit it. Unit-test the request builder.
- The banner is not decoration: without it the founder cannot tell their own team from a
  customer's, and the two screens are otherwise identical.
- `teamModel.ts`'s "can I do this?" checks compare against the **viewer**. The founder is not a
  member of the account they are managing — test that controls are enabled, and that the
  last-admin warning still appears.
- Component key by `accountId`, so switching accounts cannot leave a half-typed form pointed at the
  previous customer (the PUX-1 R-1 bug).

---

### US-PADM-1-06 — Only the founder can find or open the screen
**Status:** 📋 Not started.

```gherkin
Scenario: The menu item
  Given I am a platform admin
  Then the sidebar shows "Accounts"

Scenario: Everyone else
  Given I am not a platform admin
  Then there is no "Accounts" item
  And typing /accounts sends me to my normal start page

Scenario: The server does not trust the screen
  When a non-platform user calls any platform/* endpoint directly
  Then it is refused with E-OBS-001 and logged
```

**Counter-measures.**
- Reuse `AdminRoute` — the Health page's guard. Do not write a third route guard.
- Hiding a menu item is a convenience, not a permission (the rule in `main.tsx`). The test that
  matters is the direct HTTP call.
- The item appears in **both** sidebars in `AppLayout.tsx` (desktop and mobile drawer). Add it once
  to the shared nav list, not twice in the markup.

---

### US-PADM-1-07 — Remove an empty account
**Status:** 📋 Not started.

**As the** founder **I want** to remove test and abandoned accounts **so that** the list stays clean
(D-4).

```gherkin
Scenario: An empty account
  Given an account with no architectures, maps, plans, templates or recorded work
  When I delete it and confirm by typing its name
  Then the account, its people, their status and grant rows, and its feature flags are removed together

Scenario: An account with anything in it
  Then I am refused with E-PADM-003, which names what it still holds and offers "switch it off"

Scenario: My own account
  Then I am refused with E-PADM-004

Scenario: It failed halfway
  Then nothing was removed
```

**Counter-measures.**
- **Check, then delete, in that order, with the count taken in the same read the check used**
  (CLAUDE.md race rule). Everything inside one `db.transaction`.
- `db.del` removes **one** row per call. Query each child table, loop by `id`.
- `event_log` and `journey_map_version` are **never** deleted — history is what an audit trail is
  for, and `historyTables.ts` fails the build on a `db.del` against a version.
- List every table with an `account_id` (16 files reference it) and decide each one explicitly in
  the story's build notes: *counted as "has content"*, *deleted with the account*, or *kept as
  history*. A table left off the list is an orphan waiting to happen.
- Typing the account's name to confirm is the UI guard; the server takes the id **and** the name and
  refuses if they do not match.

---

### US-PADM-1-08 — Give a person with no account a home
**Status:** 📋 Not started.

**Description.** Users created before 2026-10-14 have account `0` (F-8). Nothing account-scoped
works for them.

```gherkin
Scenario: Seeing them
  When I open "People with no account"
  Then I see each person's name, email and sign-up date

Scenario: Placing one
  When I assign a person to an account as a member
  Then they appear on that account's Team page with no modules ticked

Scenario: Their old work
  Then maps and architectures they own with account 0 are listed for me, not moved silently
```

**Counter-measures.**
- This is the one legitimate use of "move a user to an account" — it runs through the scope rule and
  is platform-admin only. It must refuse a person who **already has** an account; moving between
  accounts is out of scope (see §7).
- Their existing maps carry `account_id 0`. Re-homing data is a migration: **list only** here, and
  ask the founder before any backfill (clone first, per the safety rules).

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | **No change to `user` or `account`.** No new table in this epic |
| Deletes | Only story 07, only an empty account, in one transaction. Ask the founder before the first live run |
| Validation | Shared with `admin/user_create`; friendly message, code, typing kept |
| Error codes | New range `E-PADM-001`–`004` (confirmed unused 2026-11-14 — re-check). `001` account not found · `002` an account needs a name · `003` account still has content · `004` not your own account. Reuses `E-OBS-001`, `E-USR-001/002/003/008/012/014` |
| Events | Feature `PADM-1`; every platform action logs `account_id` = the **target** account and, in metadata, `acting_as: "platform_admin"` and the founder's user id |
| Health page | A refused cross-account attempt must be visible there the same day |
| Rollback | Saved `getAPI` source per changed endpoint; new endpoints can be unpublished; the screen is one route |

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| FT-PADM-1-01 | Function | `resolve_admin_scope`, six rows |
| FT-PADM-1-02 | Live HTTP | **Golden replay**: Team-page requests before vs after, identical |
| FT-PADM-1-03 | Live HTTP | Each of the nine endpoints as: account admin, member, founder with scope, customer with scope |
| FT-PADM-1-04 | Live HTTP | Status and grant rows land in the target account |
| FT-PADM-1-05 | Live HTTP | Create account: happy path, duplicate email, rollback on failure |
| FT-PADM-1-06 | Live HTTP | Delete: empty, not empty, own account |
| UT-PADM-1-01 | Unit | Request builder omits `as_account_id` when no account is set |
| UT-PADM-1-02 | Unit | `teamModel` rules with a viewer who is not in the account |
| UI-PADM-1-01 | Browser | Accounts list, open an account, banner, every control |
| UI-PADM-1-02 | Browser | Non-platform user: no menu item, `/accounts` redirects |
| UI-PADM-1-03 | Browser | **The founder's own `/team` page still works exactly as before** |
| REG | Suites | `npm test`, `tsc`, build, USR-1/USR-2 tests, existing Playwright specs |

## 6. Test results

Not run. Nothing built.

## 7. Keep a pulse on

- **Out of scope, on purpose:** signing in *as* a customer (D-6); moving a person between two
  accounts; one person in several accounts; invitation emails; a "change password at next sign-in"
  flag. Each was already deferred in USR-1.
- A second platform admin. Today the flag is set by hand and there is no endpoint that writes it.
  Keep it that way until there is a second support person.
- Which API group the `platform/*` endpoints live in decides the frontend's base URL. Check with
  `listAPIGroups` before wiring the screen — a wrong group is a silent 404 (CLAUDE.md).
