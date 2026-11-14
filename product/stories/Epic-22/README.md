# Epic-22 — START HERE. Accounts: every customer gets their own Emgram, and you can run them all

> ## 📋 WRITTEN, NOT BUILT (2026-11-14). Nothing in Xano or the app was changed.
>
> Founder's ask: *"create epics to enhance the platform admin check user endpoints … review the
> screens holistically … have countermeasures so you don't break something else."*
> Wait for the founder's "execute" before building. **Ask before every Xano push** (CLAUDE.md).

| File | What it is |
|---|---|
| `README.md` | This file. What the review found, the order, the models, the open decisions. |
| `EPIC-SEC-2-close-the-open-account-doors.md` | Fix four holes that are live today. **Do this first.** |
| `EPIC-PADM-1-accounts-console.md` | The founder's screen: see, create and manage every account and its people. |
| `EPIC-PADM-2-account-switch-and-first-run.md` | Switch a whole account off and on; a new account works on its first sign-in. |

---

## 1. Who you are working for

- Product manager, not an engineer, and the only support person. ADHD/INTP-leaning.
- **5 short bullets per reply, one line each.** Pain → fix → win lands best.
- A question is a question. A short reply is not a go. Ask before any Xano push.

---

## 2. What the founder wants

**Pain:** "I want to CRUD new users so they can have their own instance of Emgram." Today each
customer can sign up and get an account, but the founder cannot see, create, fix or switch off an
account without opening the database.

**Fix:** a platform-admin-only **Accounts** screen, built on the user endpoints that already exist.

**Win:** onboarding and supporting a customer becomes a few clicks, with a log entry for each.

Two words that must never be mixed up (already the house rule in `main.tsx`):

| Word | Means | Stored in |
|---|---|---|
| **Account admin** | Runs the people inside **one** account | `user.role == "admin"` |
| **Platform admin** | The founder. Acts across **all** accounts | `user.is_platform_admin` |

---

## 3. What already exists (verified 2026-11-14)

| Thing | State |
|---|---|
| Sign-up creates an account and makes the person its admin | ✅ live (`auth/signup`, api 2) |
| Account admin adds, edits, re-roles, switches off, deletes people | ✅ live (apis 11, 17–20), Team page |
| Module access per person (Intelligent Layer, Planner, Execution) | 🟡 grants are stored and shown (apis 21, 22) but **not enforced live** — see F-6 |
| Platform admin guard | ✅ `ops/require_platform_admin`, used by the Health page and maintenance tools |
| A way to list, create, switch off or delete **accounts** | ❌ nothing |
| A way to become platform admin | Set by hand in the database, on purpose. **Keep it that way.** |

---

## 4. 🔴 What the review found (read live with `getAPI`, 2026-11-14)

These are **live today**. The first three were inherited from the Xano starter template and predate
phase 4. They are the reason SEC-2 goes first: an Accounts screen on top of them would be a locked
front door with the back door open.

| # | Finding | Why it matters | Proof | Epic |
|---|---|---|---|---|
| **F-1** | `POST user/join_account` (api 14) lets **any signed-in user move themselves into any account** by sending its number | One customer can read and edit another customer's maps, plans and work | Live source: no invite, no admin check, just `db.edit user {account_id: $input.account_id}` | SEC-2 |
| **F-2** | `GET account/details` (api 13) has **no sign-in at all** | Anyone on the internet can read any account's name, description, location and its private AI context, by counting 1, 2, 3… | Live: `auth: false` | SEC-2 |
| **F-3** | `POST account` (api 15) lets any user **start a new account and walk out of their old one** as its admin | Skips the "an account always has an admin" rule (USR-1 story 05); can strand an account with nobody in charge | Live: `auth: 1`, no checks. Local source also logs the whole user record | SEC-2 |
| **F-4** | `auth/login` (api 1) **does not check whether the person was switched off** | USR-1 story 04 says a deactivated person "cannot sign in" ✅. They can. They are only stopped later, at module doors | Live source has no `user_status` read; `E-USR-005` exists only in `usr/assert_module_access` | SEC-2 |
| **F-5** | Sign-up gives the new admin **no module grants** | Default is "all three off" (USR-2), and `Register.tsx` sends them to `/dashboard`, which is gated. First screen a new customer sees is likely "Nothing has been switched on yet" | Read from code (`auth/signup` writes no grant rows). **Not yet seen in a browser** | PADM-2 |
| **F-6** | The module middleware is **not attached** to anything | Module ticks and "switched off" change what the screen shows and nothing else. The server refuses nobody | ✅ **Confirmed live 2026-11-14:** a user with no grants, and a switched-off user, both got 200 from Planner and Intelligent Layer endpoints | USR-2 stories 03/04 — **founder to schedule** |
| **F-7** | `account` has **no on/off switch** and no "who created this" | Nothing to hang "suspend this customer" on | `static/tables/2_account.xs` | PADM-2 |
| **F-8** | Some users have **`account_id` 0** (old sign-ups from before 2026-10-14) | Any "list all accounts" screen must show them, or they become invisible people | A deleted test architecture was owned by user 6 with `account_id: 0` | PADM-1 |

**Not a finding, but a habit to keep:** `user/join_account` and `account` (POST) both write the whole
user record into the event log. The same leak was already fixed on login, sign-up and `auth/me`
(2026-10-14/15). SEC-2 closes it here too.

---

## 5. Screens reviewed, and what each epic must not break

Every screen that reads who you are, or which account you are in.

| Screen / route | Reads | Risk if we are careless | Counter-measure (where) |
|---|---|---|---|
| `/login` | `auth/login` | A switched-off person or account gets a confusing "Invalid Credentials" | Own message and code; wrong password still says only "Invalid Credentials" (SEC-2-04, PADM-2-02) |
| `/register` | `auth/signup` | New customer lands on "nothing switched on" | Grants written in the same transaction as the account (PADM-2-04) |
| Sidebar (`AppLayout.tsx`) | `role`, `is_platform_admin`, module grants | New "Accounts" item shown to the wrong person | One new item, shown only when `is_platform_admin`; route guarded by the existing `AdminRoute`; server refuses regardless (PADM-1-06) |
| `/team` (Manage users) | apis 10, 16, 21 + admin endpoints | Platform-admin powers leak into the account admin's page, or its behaviour changes | Team page gets **one optional prop**; existing endpoints get one optional input. Absence of either means "exactly as today", proven by a before/after replay (PADM-1-03, 05) |
| `/account` (settings) | `getAccountMe` | Founder renames an account from the console and the customer's page shows stale data | Same record, read fresh on load — verify, no change expected (PADM-1-04) |
| `/health` | `ops/*` | A refusal from the new console is invisible; or the founder's own tools get paused | Every refusal logs through `ops/log_event` with its own feature code; `Ops` endpoints are exempt from the account switch (all three epics, PADM-2-02) |
| Every signed-in page | `auth/me` | A refusal from `auth/me` deletes the token and silently signs the customer out (`AuthContext.tsx`) | `auth/me` never refuses for a paused account; it returns one extra field (PADM-2-02, 03) |
| `/architectures`, `/maps/:id`, `/dashboard` | intelligence module | Switched-off account bounces between gated pages forever | One terminal page, signed-in only, that nothing redirects away from — same rule `/no-access` already follows (PADM-2-03) |
| `/planner`, `/reports/*` | planning module | A plan's people belong to a switched-off account; history disappears | Switching off **never deletes or hides data**; it only refuses requests (PADM-2-01) |
| `/perform` (phone) | execution module | A performer mid-shift gets a blank screen | Friendly "this account is paused" message, typing kept; decision D-3 on timing (PADM-2-03) |
| `/settings/catalog`, `/no-access` | signed-in only | These have **no module gate**, so a switched-off account could still use them | The account check also runs on `auth/me`, which every page load calls (PADM-2-02) |
| AI chat and MCP tools | user token | A switched-off account's AI agent keeps writing maps | Same check sits in the one shared function the module doors already call (PADM-2-02) |
| Background jobs (`tasks/16`, `19`, `20`) | all accounts | Audits start reporting a paused account as broken | Audits keep running on every account; paused is a label, not an error (PADM-2-05) |

---

## 6. Build order and models

| # | Epic | Depends on | Model | Why that model |
|---|---|---|---|---|
| 1 | **SEC-2** Close the open account doors | none | **Opus 5.5** | Guards and tenancy (CLAUDE.md). Small, but every line is a permission |
| 2 | **PADM-1** Accounts console | SEC-2 | **Opus 5.5** for stories 01–03 (the scope rule), Sonnet 5.5 for the screen | A cross-account power added to live endpoints is the riskiest edit in this folder |
| 3 | **PADM-2** Account switch and first run | PADM-1 | **Opus 5.5** | Can lock a whole customer out, or fail to |

Run an **Opus review pass after each one**. Fixtures and the junk-input list can go to Haiku.

**House rules that apply to all three** (from CLAUDE.md — do not re-discover them):

- Additive only. No column added to `user` or `account` (both carry text validators that
  `updateTableSchema` drops). New facts go in a **side table with its own GET endpoint**.
- One rule, one function. Never copy a permission check into two places.
- An omitted optional input is `""` / `0` / `false`, never `null`. Pass an explicit flag.
- `db.patch` / `db.del` by a non-unique field touches **one** row. Query, then loop by `id`.
- Before pushing a new static path, check it is not shadowed by a dynamic one in the same group.
- After every push, a real smoke test with `runWorkspaceFunction` or real HTTP.
- Tests first. Then `npm test`, `tsc`, build, and the existing suites, all green.

---

## 7. Decisions the founder still owns

Each has a default so the build is never blocked. Say the word to change one.

| # | Question | Default written into the stories |
|---|---|---|
| **D-1** | Do you create customers' accounts, or do they sign up themselves? | **Both.** Sign-up stays as it is; you can also create an account and its first admin from the console |
| **D-2** | The three template endpoints (F-1, F-2, F-3): remove, or lock? | **Lock, don't delete.** Each is left in place and refuses everyone except what is safe. Reversible; a delete is not |
| **D-3** | When an account is switched off, do people already signed in stop at once? | **Yes, on their next click.** Same as switching off one person today |
| **D-4** | Can you delete a customer's account? | **Only if it is empty** (no maps, plans or work). Otherwise switch it off. Mirrors the map-delete rule |
| **D-5** | Should a new account's first admin get all three modules automatically? | **Yes.** Otherwise their first screen is a dead end |
| **D-6** | Can you sign in *as* a customer to see what they see? | **No — not in this folder.** It is a much larger permission and deserves its own epic |

---

## 8. How to report progress

- Edit each story's `**Status:**` line: `📋 Not started` → `🚧 In progress (model, date)` →
  `✅ Built (model, date)` or `🔴 Blocked — reason`.
- Every UI story is seen in Chrome on real data before it is called done.
- Fill each epic's Test Results with real results. Not run = "not run".
- Stage files by name. Never commit `product/learning-fixes.md`, `.obsidian/`, the frontend zip, or
  loose screenshots.

---

## 9. Status

| Item | State |
|---|---|
| Review of backend and screens | ✅ 2026-11-14 — findings in §4, screen table in §5 |
| Epics + stories written | ✅ 2026-11-14 |
| Founder review | ⏳ waiting |
| SEC-2 | ✅ Built, pushed, 17/17 live after-tests (Fable 5.2, 2026-11-14). Review pass still to do |
| F-6 (module grants and "switched off" not enforced on requests) | 🔴 Open — USR-2 stories 03/04, founder to schedule. Blocks PADM-2 |
| PADM-1 | 📋 Not started |
| PADM-2 | 📋 Not started |

**What the review did not do:** it read code and live endpoint definitions. It did not sign in as a
second user to *prove* F-1 or F-3 by moving accounts, and it did not open a browser for F-5. Each
epic's first test does exactly that, so the hole is seen before it is closed.
