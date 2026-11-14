# EPIC-PADM-2 — Switch an account off and on, and make a new one work first time

**Epic folder:** Epic-22 — Accounts
**Status:** 📋 Not started. Written 2026-11-14.
**Model:** **Opus 5.5.** This can lock a whole customer out — or fail to. Opus review pass after.
**Depends on:** SEC-2 and PADM-1. Story 02 also depends on knowing the answer to F-6 (are the module
doors actually enforced live?).
**Risk:** high. One wrong default here signs every customer out.

---

## 1. Goal

**Pain, part 1:** there is no way to pause a customer. The only tools are deleting their data or
switching off each person one by one.

**Pain, part 2:** a brand-new account's admin has no modules switched on, so the first thing they
are likely to see is "Nothing has been switched on yet" (F-5).

**Fix:** one on/off switch per account, checked in the same place a person's on/off is checked; and
a new account's first admin starts with all three modules.

**Win:** pausing a customer is one click and loses nothing; a new customer lands on a working app.

---

## 2. Design

### The switch

`account` cannot take a new column (its text validators would be dropped), so the state lives in a
side table, exactly like `user_status`:

| Table `account_status` (new) | |
|---|---|
| `account_id` | unique — at most one row per account |
| `is_active` | **no row means active**, so nothing existing needs a backfill |
| `switched_off_at`, `switched_off_by_user_id` | who and when |
| `reason` | short text the founder types; shown to nobody but platform admins |

Plus `GET platform/account_status` (a side table needs its own list endpoint, or the screen never
sees it) and `POST platform/account_status`.

### Where the check runs

One function, `usr/assert_account_active`, called from the places a person's on/off is already
checked — nowhere else:

| Place | What a paused account gets |
|---|---|
| `auth/login`, magic-link login | Refused with `E-PADM-005` **after** the password is checked |
| `usr/assert_module_access` (every Intelligent Layer, Planner and Execution request) | Refused with `E-PADM-005` |
| `usr/assert_team_admin` (Manage users) | Refused with `E-PADM-005` |
| `auth/me` | **Not refused.** Returns the user plus `account_active: false` — see below |

🔴 **Why `auth/me` must not refuse.** `AuthContext.tsx` treats a 401/403 from `auth/me` as "this
token is dead": it deletes the token and shows the login form with no explanation. A paused customer
would just be signed out, over and over. Instead `auth/me` gains one field, and the app shows a
"paused" page.

### The paused page

`/paused` — signed-in only, gated on nothing, and **nothing redirects away from it**. Same rule that
keeps `/no-access` from looping.

```
        This workspace is paused

   Your Emgram workspace has been paused.
   Your maps, plans and history are safe.
   Please contact support to switch it back on.

                [ Sign out ]
```

---

## 3. Stories

### US-PADM-2-01 — The founder switches an account off and on
**Status:** 📋 Not started.

**As the** founder **I want** to pause a customer without touching their data **so that** I can
stop access for non-payment or a security worry and undo it in one click.

```gherkin
Scenario: Switching off
  Given I am a platform admin on the Accounts screen
  When I switch an account off and give a reason
  Then the list shows it as Paused, with who did it and when

Scenario: Nothing is lost
  Then every person, map, plan, job and log entry in that account still exists, unchanged
  And each person's own active state and module ticks are untouched

Scenario: Switching back on
  When I switch it on
  Then everyone can sign in again with exactly what they had

Scenario: Not my own account
  When I try to switch off the account I belong to
  Then I am refused with E-PADM-004

Scenario: Not a platform admin
  When an account admin calls platform/account_status
  Then they are refused with E-OBS-001 and it is logged
```

**Counter-measures.**
- **Never cascade.** Pausing writes one row in `account_status` and nothing else. No `user_status`
  rows are written "to be safe" — that would make switching back on lossy.
- The row is edited in place: patch by `id`, never by `account_id` and "assume one".
- `is_active` is a bool. `false == null` is true here — read `== true`, through a `single` query and
  `|get:"is_active":true` with a **literal** key.
- The founder's own account is refused on the server, not just greyed out. Losing it loses the only
  platform admin.
- The new static path must not be shadowed by a dynamic one in its API group — `listAPIs` first.

---

### US-PADM-2-02 — A paused account is refused everywhere, by one rule
**Status:** 📋 Not started.

**As the** founder **I want** "paused" to mean every door **so that** it cannot be worked around
with a saved link, an open tab or the AI.

```gherkin
Scenario: Signing in
  Given my account is paused
  When I sign in with the right password
  Then I am refused with E-PADM-005 and no token is issued

Scenario: Wrong password
  Then I see only "Invalid Credentials"

Scenario: Already signed in
  Given I had the app open when the account was paused
  When I make my next request to any module
  Then it is refused with E-PADM-005 (D-3)

Scenario: The pages with no module gate
  When I call the catalog, account settings or team endpoints
  Then each is refused the same way

Scenario: The AI
  When the AI agent or an MCP tool acts for a user of a paused account
  Then it is refused before it reads or writes anything

Scenario: An active account
  Then nothing about any request changes

Scenario: A person switched off inside an active account
  Then they still get E-USR-005, not the account message
```

**Build notes.** Order inside the shared check: real module → **account active** → person active →
module granted. Account first, because "your workspace is paused" is the more useful thing to tell
someone whose whole company is off.

**Counter-measures.**
- 🔴 **Inventory before building.** List every API group and write down which guard its endpoints
  pass through: `journey-map`, `planner`, `catalog`, `Members & Accounts`, `Authentication`,
  `Reporting`, `Event Logs`, `mixpanel`, `seeding`, `Ops`. A group with **no** shared guard is a door
  this rule cannot reach — report it to the founder; do not bolt a copy of the check onto each
  endpoint.
- **F-6 first.** If the module middleware is not attached live, this story's main enforcement point
  does not exist. Settle that in SEC-2-01 and do not build on an assumption.
- `Ops` endpoints are platform-admin only and must **stay reachable** when the founder's tools are
  needed most. They are exempt, on purpose, and a test says so.
- **Fail open or fail closed?** If the `account_status` read itself errors, refusing would lock out
  every customer on a database hiccup. Default: a missing row or a failed read is **active**, and
  the failure is logged as an error event so the Health page shows it.
- One extra read on every request. Keep it to a single indexed `single` query on `account_id`; time
  a module request before and after and record both numbers.
- Users with account `0` have no account to pause. Treat `0` as active here; PADM-1-08 is where they
  get fixed.
- Re-run USR-1 and USR-2's tests after touching `assert_module_access` and `assert_team_admin` —
  three middlewares and the whole Team page sit on those two functions.

---

### US-PADM-2-03 — A paused customer sees why, not a blank screen
**Status:** 📋 Not started.

**As a** customer **I want** a clear message when my workspace is paused **so that** I know it is
not a bug and who to ask.

```gherkin
Scenario: Opening the app while paused
  Given I still have a valid token
  When any page loads
  Then I land on /paused, which explains and offers Sign out

Scenario: No redirect loop
  Then /paused never redirects anywhere, whatever my role or modules

Scenario: Signing in while paused
  Then the login form shows the E-PADM-005 message, not "wrong email or password"

Scenario: Mid-task on a phone
  Given a performer is on /perform when the account is paused
  When their next tap is refused
  Then they see the paused message and what they typed is not lost

Scenario: Switched back on
  When I reload
  Then I am back in the app with no need to sign in again
```

**Counter-measures.**
- The check belongs in `ProtectedRoute` (every signed-in route passes through it), **before**
  `ModuleRoute`. Putting it in `ModuleRoute` would miss `/account`, `/settings/catalog` and
  `/no-access`.
- While `auth/me` is loading, render nothing. A redirect fired on incomplete information is the
  loop bug again.
- `account_active` missing from the response (an old cached build, or the backend not yet pushed)
  must be read as **active**: `user.account_active !== false`, never `!user.account_active`.
- The performer screen has its own error boundary (`PerformErrorBoundary`). Check that an
  `E-PADM-005` from a tap shows the paused message rather than the boundary's generic one.
- The message never says *why* the account was paused. The reason is the founder's note.

---

### US-PADM-2-04 — A new account works on its first sign-in
**Status:** 📋 Not started.

**Description.** Fixes F-5 for sign-up, and gives PADM-1-04 (founder-created accounts) the same
start.

**As a** new customer **I want** to land on a working app **so that** my first minute is not a dead
end.

```gherkin
Scenario: Signing up
  When I register
  Then I am the admin of my own account
  And I have Intelligent Layer, Planner and Execution switched on (D-5)
  And I land on my architectures, not on "Nothing has been switched on yet"

Scenario: All or nothing
  Given writing the grants fails
  Then no account and no user were created either

Scenario: People my admin adds later
  Then they still start with all three modules off, as today

Scenario: A friendly refusal
  When I register with an email that is already used
  Then the message has a code and my typing is kept
```

**Counter-measures.**
- **Prove F-5 in a browser first** (fresh sign-up, screenshot). If a new admin already lands
  somewhere usable, shrink this story to what is actually broken.
- Grants go inside sign-up's existing `db.transaction`, written the same way
  `admin/user_module_access` writes them — through one shared function, not a second copy of the
  row shape.
- The default for people added by an admin (**all off**) was the founder's explicit decision on
  2026-10-22. This story changes the first admin only. A test pins the other case.
- `Register.tsx` navigates to `/dashboard`; `useMyModules` caches grants
  (`moduleGrantsCache`). Make sure the cache is reset after sign-up, or the new admin sees the
  pre-grant answer until they reload.
- **Existing accounts are not touched.** Whether any current admin is sitting with no modules is
  reported as a count; a backfill needs the founder's OK and a clone test first.

---

### US-PADM-2-05 — Paused is a label, not an error
**Status:** 📋 Not started.

**As the** founder **I want** the Health page and nightly audits to stay calm about paused accounts
**so that** a deliberate pause does not look like an outage.

```gherkin
Scenario: The Health page
  Given an account is paused
  Then refusals for it are grouped under "account paused", not counted as failures

Scenario: Nightly audits
  When the integrity audits run
  Then a paused account is audited like any other and reported with a "paused" label

Scenario: The log
  Then every switch off and on is an event with who, when and the reason
```

**Counter-measures.**
- A paused customer who keeps the app open will generate one refusal per click. Log them at `info`
  with outcome `rejected`, so they do not flood the issues list that `error` and `warn` feed.
- Do **not** make the audits skip paused accounts. Skipping is how a problem hides for the length of
  a pause and surfaces the day the customer comes back.
- The event log's own rate-limit / de-dup rule (endpoint `ops/event`) already exists — rely on it;
  do not add a second one.

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | One new side table, `account_status`. **Ask before the schema push.** No change to `account` or `user`. `auth/me` gains one response field |
| Indexes | Unique on `account_id`; index on `switched_off_by_user_id` (GOV-1 S3) |
| Deletes | None. Pausing never deletes or hides data |
| Validation | Reason is optional text, trimmed, capped in length; junk input list applies |
| Error codes | `E-PADM-005` "This workspace is paused." Added to `functions/ops/error_catalog.xs` and `src/ops/errorCatalog.json`; `errorCodeRegistry.test.ts` green |
| Events | Feature `PADM-2`: `account_switch_off`, `account_switch_on`, and `rejected` on every refused door |
| Rollback | Delete the `account_status` rows → every account is active again (absence means active). Saved `getAPI` source for each changed function and endpoint |

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| FT-PADM-2-01 | Function | `usr/assert_account_active`: no row, on, off, account 0, read failure |
| FT-PADM-2-02 | Live HTTP | Switch off / on; own account refused; non-platform caller refused |
| FT-PADM-2-03 | Live HTTP | Paused account: login, module endpoints (one per module), team, catalog, account settings, AI tool |
| FT-PADM-2-04 | Live HTTP | Active account: same calls, unchanged; timing before / after |
| FT-PADM-2-05 | Live HTTP | Sign-up writes three grants; forced failure leaves nothing behind |
| UT-PADM-2-01 | Unit | Route decision: `account_active` true / false / missing / still loading |
| UI-PADM-2-01 | Browser | Paused: `/paused` shows; no loop; login message; switch on → reload works |
| UI-PADM-2-02 | Browser | Fresh sign-up lands on a working page |
| UI-PADM-2-03 | Browser | `/perform` on phone width: paused mid-task keeps typing |
| REG | Suites | `npm test`, `tsc`, build, USR-1/USR-2 tests, existing Playwright specs |

## 6. Test results

Not run. Nothing built.

## 7. Keep a pulse on

- **Billing is not in this folder.** The switch is manual. Tying it to a payment system is a later
  epic, and the `reason` field is where that system would write.
- A scheduled "switch back on at a date" was considered and left out — nobody asked for it.
- If the inventory in story 02 finds an API group with no shared guard, that becomes its own
  GOV-1-shaped story rather than growing this epic.
- Token lifetime is 24 hours (`expiration = 86400`). With the request-time check, pausing takes
  effect on the next click; without F-6 settled it could take a day.
