# EPIC-SEC-2 — Close the open account doors

**Epic folder:** Epic-22 — Accounts
**Status:** ✅ Built, pushed and verified live (Fable 5.2, 2026-11-14). 17/17 live after-tests. **F-6 remains open and is not this epic's** — see §6. Opus-level review pass still to do.
**Model:** **Opus 5.5** — guards and tenancy. Opus review pass after.
**Depends on:** nothing. **Everything else in Epic-22 depends on this.**
**Risk:** high if skipped, low to build. Four small edits to endpoints that almost nothing calls.

---

## 1. Goal

**Pain:** four doors are open on the live system today (README §4, F-1 to F-4). A signed-in user can
move into another customer's account; anyone can read any account's details without signing in; a
user can walk out of their account and strand it; a switched-off person can still sign in.

**Fix:** close each door in place, with a friendly refusal, a code and a log entry.

**Win:** one customer can never reach another's data, and "switched off" means switched off.

---

## 2. Design

Nothing new is built. Four existing endpoints change, and each keeps its name and path so nothing
that calls it gets a 404.

| Endpoint | Today | After |
|---|---|---|
| `POST user/join_account` (api 14) | Anyone signed in, any account | **Platform admin only.** Everyone else is refused and logged |
| `GET account/details` (api 13) | No sign-in | Signed-in, and **only your own account** (platform admin: any) |
| `POST account` (api 15) | Anyone signed in | **Platform admin only** (PADM-1 gives the founder a proper way to create accounts) |
| `POST auth/login` (api 1) | Ignores `user_status` | A switched-off person is refused with `E-USR-005` |

**Why lock instead of delete (D-2):** a delete cannot be undone and a forgotten caller would break
with no explanation. A lock is one `precondition` that can be lifted.

**One rule, one function.** "Is this person switched on?" already lives inside
`usr/assert_module_access`. Login must not grow its own copy. Extract it to
`usr/assert_user_active` and have **both** call it — the LOG-1 lesson.

---

## 3. Stories

### US-SEC-2-01 — Prove the doors are open, before closing them
**Status:** ✅ Done (Fable 5.2, 2026-11-14) — every door proven open on live. Results §6.

**Description.** A failing test for each finding, run against live with two throwaway test accounts.
If a door turns out to be already shut, the finding is struck out in the README rather than "fixed".

**As the** founder **I want** to see each hole demonstrated **so that** I know the fix is real and
not a guess from reading code.

```gherkin
Scenario: F-1 is real
  Given test user A in account X and test user B in account Y
  When A calls user/join_account with account Y's number
  Then (today) A's account becomes Y and A can list Y's team members

Scenario: F-2 is real
  When account/details is called with no sign-in and a valid account number
  Then (today) the account's name and AI context come back

Scenario: F-3 is real
  Given A is the only admin of account X
  When A calls POST account
  Then (today) A is in a new account and X has no admin

Scenario: F-4 is real
  Given a member who has been switched off on the Team page
  When they sign in with the right password
  Then (today) they receive a token

Scenario: The module doors are checked too (F-6)
  When a user with no Planner grant calls a Planner endpoint over real HTTP
  Then the result is recorded as "refused with E-USR-006" or "allowed — middleware not attached"
```

**Counter-measures.**
- Test accounts only, created for this and removed after (standing OK for test-data cleanup).
  **Never** the founder's account 2.
- Get a real token with the documented magic-link route. A token minted through
  `runWorkspaceFunction` is rejected by the live API (CLAUDE.md).
- If F-6 comes back "allowed", **stop and tell the founder** — that is USR-2 story 03 unfinished,
  not something to patch quietly here.

**Keep a pulse on.** The results table in §6 is the before picture. Do not overwrite it after the fix;
add an "after" column.

---

### US-SEC-2-02 — Nobody moves themselves into another account
**Status:** ✅ Built and live (Fable 5.2, 2026-11-14).

**Description.** `user/join_account` and `POST account` stop being self-service.

**As a** customer **I want** my account to contain only people my admin added **so that** a stranger
cannot let themselves in.

```gherkin
Scenario: A normal user is refused
  Given I am signed in and I am not a platform admin
  When I call user/join_account with any account number
  Then I am refused with E-SEC-201
  And my account has not changed
  And a "rejected" event is logged with my user id and the account I tried

Scenario: A normal user cannot start a second account
  When I call POST account
  Then I am refused with E-SEC-201 and nothing is created

Scenario: Signing up still creates an account
  When a new person registers
  Then they get their own account and are its admin, exactly as before

Scenario: The log carries no personal data
  When either endpoint runs, allowed or refused
  Then the event's metadata holds ids only — never a name, email or password hash
```

**Build notes.** Add `function.run "ops/require_platform_admin"` as the first step of both, passing
`what: "action"`, `feature: "SEC-2"` and a `step`. That function already logs its own refusal.
Its code is `E-OBS-001`; **decide before building** whether to reuse it (it already means exactly
"not a platform admin") or add `E-SEC-201`. Default: **reuse `E-OBS-001`** — GUARD-1-01 says a code
means one thing, and this is that thing. The Gherkin's `E-SEC-201` then becomes `E-OBS-001`.

**Counter-measures.**
- **Check for callers first.** `grep` both frontends, the MCP tools and `ai/tool/*` for
  `join_account` and `'/account'` with POST. The review found none in `webapp/protype-2/src`;
  confirm `planningFrontendv2` and `emgram1010v1` before pushing.
- Sign-up does **not** call either endpoint (it writes the account itself, in a transaction), so
  sign-up cannot be broken by this. A test proves it anyway.
- Replace `metadata: $updated_user` with ids — and remember the event log already holds old rows
  from these two endpoints. Listing them is story 05; cleaning them needs the founder's OK and the
  **two-step json patch** (CLAUDE.md, critical).

---

### US-SEC-2-03 — Account details are private
**Status:** ✅ Built and live (Fable 5.2, 2026-11-14).

**As a** customer **I want** my company's details and AI context kept to my own team **so that**
nobody can read them by guessing a number.

```gherkin
Scenario: Not signed in
  When account/details is called with no token
  Then it is refused as unauthorized

Scenario: Someone else's account
  Given I am signed in to account X
  When I ask for account Y
  Then I get "not found" — the same answer as an account that does not exist

Scenario: My own account
  When I ask for account X
  Then I get its details

Scenario: The platform admin
  Given I am a platform admin
  When I ask for any account
  Then I get its details
```

**Counter-measures.**
- "Not found", not "access denied", for another account — a refusal that says "that exists but is
  not yours" confirms the number is real.
- The settings page uses `getAccountMe`, a different endpoint. Confirm in the browser that
  `/account` still loads for an admin and a member after the push.
- The input stays an `int`. An omitted int arrives as `0`; treat `0` as "my own account" rather than
  as a lookup for account 0, where the legacy account-less users live (F-8).

---

### US-SEC-2-04 — A switched-off person cannot sign in
**Status:** ✅ Built and live (Fable 5.2, 2026-11-14). Closes sign-in only — see F-6 in §6.

**Description.** Closes the half of USR-1 story 04 that was marked done but is not live.

**As an** account admin **I want** switching someone off to stop them signing in **so that** people
who leave are out, not half out.

```gherkin
Scenario: Switched off, right password
  Given a member has been switched off
  When they sign in with the correct password
  Then they are refused with E-USR-005 and no token is issued
  And the refusal is logged

Scenario: Switched off, wrong password
  When they sign in with a wrong password
  Then they see only "Invalid Credentials" — nothing that says the account exists or is off

Scenario: Never touched
  Given a user with no row in user_status
  When they sign in
  Then it works — no row means active

Scenario: Switched back on
  When the admin reactivates them
  Then they can sign in again with the grants they had

Scenario: Magic-link sign-in follows the same rule
  When a switched-off person uses a reset / magic link
  Then they are refused with E-USR-005
```

**Build notes.** Extract the status read from `usr/assert_module_access` into
`usr/assert_user_active` (`db.query … return = {type: "single"}`, then `|get:"is_active":true` with a
**literal** key — a variable key drops its default). Login, `reset/magic-link-login` and
`assert_module_access` all call it.

**Counter-measures.**
- **Check the password first, the status second.** Otherwise the login form tells a stranger which
  emails belong to switched-off people.
- `false == null` is **true** in this engine. Read `is_active == true`, never `!= null`.
- After the extract, re-run USR-2's own tests: the module doors must refuse exactly as before. This
  story changes a function three middlewares depend on.
- The Login screen must show the server's message for `E-USR-005`, not its generic "wrong email or
  password". Check `Login.tsx`'s error handling in the browser.
- Lockout guard: the founder's own user must have no `user_status` row saying off. Check before the
  push; a mistake here locks out the only platform admin.

---

### US-SEC-2-05 — Find out what the open doors already let through
**Status:** ✅ Done (Fable 5.2, 2026-11-14) — read-only. Results §6.

**As the** founder **I want** to know whether anyone ever used these doors **so that** I am not
guessing about past damage.

```gherkin
Scenario: History of the two endpoints
  When the event log is searched for "user_joins_account" and "new_account_created"
  Then I get a count and a list of who, when and which account — ids only

Scenario: Accounts with nobody in charge
  When accounts are checked for having zero active admins
  Then I get a list (expected: test accounts only)

Scenario: People with no account
  When users with account 0 are listed
  Then I get a count, to decide in PADM-1 what to do with them
```

**Counter-measures.**
- **Read-only.** One scratch function, run once, deleted after. No repair in this story — repairs
  are proposed to the founder with the list in hand.
- Old log rows from these endpoints contain whole user records. Report the **count** of such rows;
  do not print their contents into chat or a file.

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | No schema change |
| Deletes | None. Endpoints are locked, not removed (D-2) |
| Validation | Friendly message and a code on every refusal; a wrong password never reveals account state |
| Error codes | Reuse `E-OBS-001` (not a platform admin) and `E-USR-005` (switched off). If a new code is added, it goes in `functions/ops/error_catalog.xs` **and** `src/ops/errorCatalog.json`; `errorCodeRegistry.test.ts` must stay green |
| Events | `SEC-2` / `join_account`, `create_account`, `account_details`, `login` — success and rejected, ids only |
| Rollback | Each endpoint's previous source is saved from `getAPI` before the push; restoring it is one `updateAPI` |

## 5. Test plan

| ID | Kind | What |
|---|---|---|
| FT-SEC-2-01 | Live HTTP | The five "is it real" scenarios of story 01, before any change |
| FT-SEC-2-02 | Live HTTP | join_account and POST account refuse a normal user; account unchanged; event logged |
| FT-SEC-2-03 | Live HTTP | account/details: no token, other account, own account, platform admin |
| FT-SEC-2-04 | Live HTTP | login: off + right password, off + wrong password, no row, reactivated, magic link |
| FT-SEC-2-05 | Function | `usr/assert_user_active` on: no row, `is_active` true, `is_active` false |
| UI-SEC-2-01 | Browser | Login shows the E-USR-005 message; `/account` and `/team` still load |
| REG | Suites | `npm test`, `tsc`, build; USR-1 and USR-2 tests; sign-up end to end |
| WF | File | `workflow_tests/` file written and pushed; **cannot be run from a session** — say so in results |

## 6. Test results

### Before — the doors, proven open on live (2026-11-14, Fable 5.2)

Real HTTP, with throwaway accounts 8 (X), 9 (Y) and users 17 (A, admin of X), 18 (B, admin of Y),
19 (C, member of X, switched off). Script: `tests/sec2_probe.py` (password from an env var).

| Finding | What was done | Result | After the fix |
|---|---|---|---|
| F-1 | A called `user/join_account` with account 9 | 🔴 **200.** A's account went 8 → 9 and A listed Y's people ("SEC2 B", "SEC2 A"). The response also returned A's `password` and `password_reset` fields | ✅ closed — see After |
| F-2 | `account/details?account_id=9` with **no token** | 🔴 **200.** Name, description, location and `ai_context` returned | ✅ closed — see After |
| F-3 | A (the only admin of X) called `POST account` | 🔴 **200.** A moved to new account 10 as admin; X was left with no admin | ✅ closed — see After |
| F-4 | C, switched off, signed in with the right password | 🔴 **200, token issued** | ✅ closed — see After |
| F-6 | B (no module grants) called a Planner and an Intelligent Layer endpoint | 🔴 **200 on both — module grants are not enforced live** | **Not fixed by SEC-2.** See below |
| F-6b | C, switched off, used that token on the Planner and listed the team | 🔴 **200 on both — switching a person off currently stops nothing** | Sign-in is fixed by SEC-2; an already-issued token is not |

### 🔴 F-6 is confirmed, and it is bigger than this epic

The module middleware is attached to nothing (as `middlewares/usr_require_module_planning.xs` and the
USR-2 epic both say). So today, live:

- Ticking or unticking a module on the Team page changes what the **sidebar shows**, and nothing else.
- Switching a person off changes a label on the Team page, and nothing else.

SEC-2 closes **sign-in** for a switched-off person. Their existing token still works for up to 24
hours, and module grants stay unenforced, until **USR-2 stories 03/04** (attach the middleware) are
built. That is the founder's call to schedule — it was stopped here on purpose rather than patched
quietly. PADM-2 depends on it.

### Story 05 — history (read-only, 2026-11-14)

| Question | Answer |
|---|---|
| Did any real user ever use `join_account` or `POST account`? | **No.** The event log holds 4 such rows, all from this test (users 17–19). Caveat: the log is pruned nightly, so this covers only the retained window |
| Accounts with no active admin | Account 3 "PUB-1 QA Test Account" (test) and account 10 (this test's spin-off) |
| People with no account | 3 — users 3, 4, 5, all `member`, created 2026-05 |
| Accounts in total | 9, of which 1 is real (account 2, Emgram1010), 5 are older test accounts and 3 are this test's |

### What changed (pushed to live 2026-11-14, founder's OK given in session)

| File | Change |
|---|---|
| `functions/usr/assert_user_active.xs` | **New.** The one "is this person switched on?" rule; logs its refusal |
| `functions/usr/assert_module_access.xs` | Calls the new function instead of its own inline copy |
| `apis/authentication/1_auth_login_POST.xs` | Asks the rule after the password check |
| `apis/authentication/5_reset_magic_link_login_POST.xs` | Same |
| `apis/members_accounts/14_user_join_account_POST.xs` | Platform admin only; shaped response; ids-only event |
| `apis/members_accounts/15_account_POST.xs` | Platform admin only; **no longer moves the caller** (deviation, below) |
| `apis/members_accounts/13_account_details_GET.xs` | Sign-in required; own account only (platform admin: any) |
| `webapp/protype-2/src/loginError.ts` + test, `Login.tsx` | Login shows the server's sentence for `E-USR-005`; everything else stays generic |

### After — every door closed (live, 2026-11-14)

Script: `tests/sec2_after.py`, real HTTP, same test accounts. **17/17 passed.**

| Check | Result |
|---|---|
| Active users still sign in | ✅ |
| Switched off + right password → `E-USR-005`, no token | ✅ 403 |
| Switched off + wrong password → only "Invalid Credentials." | ✅ |
| Unknown email → only "Invalid Credentials." | ✅ |
| Switched off + magic link → `E-USR-005` | ✅ 403 |
| Magic link still works for an active user (the test-token route in CLAUDE.md) | ✅ |
| `account/details`: no token | ✅ 401 |
| `account/details`: someone else's account / a missing account | ✅ 404 "Account not found." — identical answers |
| `account/details`: own account, by number and with the number omitted | ✅ 200 |
| Normal user `join_account` → `E-OBS-001`, account unchanged (8 → 8) | ✅ 403 |
| Normal user `POST account` → `E-OBS-001`, stays put | ✅ 403 |
| Platform admin reads any account | ✅ |
| Platform admin creates an account **and stays in their own** | ✅ |
| Platform admin `join_account` works; response is `{id, account_id}` only | ✅ |
| Sign-up still creates an account and its admin | ✅ |

The platform-admin rows were run with a **test** user holding the flag for a few seconds, set by a
scratch function hard-wired to that one user id and removed afterwards. The founder's own login was
never used.

| Other checks | Result |
|---|---|
| `usr/assert_user_active` — no row / on / off | ✅ ok / ok / refused |
| `usr/assert_module_access` after the extract — granted user, switched-off user, unknown module | ✅ granted / refused / `E-USR-007` |
| Browser: switched-off test user on `/login` | ✅ shows "This account has been switched off. Ask your admin to turn it back on. (E-USR-005)" |
| Browser: wrong password on `/login` | ✅ shows "Invalid email or password." |
| Browser: `/account` and `/team` as an account admin | ✅ both load; Team shows the switched-off member as "Switched off" |
| `npm test` | ✅ **789/789** (784 before, +5 new) |
| `tsc`, `vite build` | ✅ clean |
| `workflow_tests/` file | ❌ **not written** — the two Python scripts in `tests/` are the functional tests for this epic |
| Existing Playwright specs | ❌ **not run** (they skip without `E2E_AUTH_TOKEN`; a skip is not a pass) |
| Founder's own sign-in, `/team`, `/health` | ❌ **not checked by me** — please sign in once to confirm |

### Cleanup

Removed: test users 17–20, test accounts 8–12, one `user_status` row, the 4 old-style event-log rows
that held those test users' records, and every scratch function. Kept: the `SEC-2` events from the
tests (ids only) — they are the audit trail of the refusals.

### Seen in passing, not fixed

- A new admin with no module grants lands on `/no-access` after signing in — **F-5 seen in the
  browser** (with a fixture admin; a sign-up admin has the same empty grants). PADM-2 story 04.
- The old `POST account` also overwrote the **caller's own name** with the new account's name (the
  test admin was renamed "SEC-2 spinoff…"). Gone with the rewrite; noted so nobody is surprised by a
  mis-named user from before today.

Local `.xs` files matched live before these edits (diffed against `getAPI` for apis 1, 5, 13, 14, 15),
so `git` holds the rollback source for each.

### Deviations from the stories

- **`POST account` no longer moves the caller into the new account.** The story only said "platform
  admin only". With the guard on, the only possible caller is the founder, and the old behaviour
  would move the founder out of their own account on every call.
- **`E-OBS-001` is reused, no `E-SEC-201`** — the default the story named. No new error code in this
  epic, so the catalog and `errorCodeRegistry.test.ts` are untouched.
- **A refused `account/details` has no error code.** It answers a bare "Account not found." on
  purpose (it must look identical to a missing account); the refusal is still logged.

## 7. Keep a pulse on

- `user/edit_profile` (api 12) and `reset/*` were not reviewed line by line. Add them to the Opus
  review pass.
- Whether old event-log rows holding user records get cleaned is the founder's call (story 05).
- The stale ✅ on USR-1 story 04 should be corrected in Epic-13 once this lands — **ask before
  editing that file** (CLAUDE.md: do not edit documents that were not part of the request).
